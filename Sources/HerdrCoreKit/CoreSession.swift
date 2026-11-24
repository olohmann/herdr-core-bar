import Foundation
import Synchronization

/// What a `CoreSession` reports to its owner (the app's store).
public enum SessionUpdate: Sendable, Hashable {
    /// About to (re)connect; `attempt` counts consecutive failures before this one.
    case connecting(attempt: Int)
    /// Subscribed: a fresh snapshot replacing everything known before.
    case live(HelloResult, TerminalState)
    /// The state after one or more events (or a `missed` snapshot).
    case state(TerminalState)
    /// Disconnected; the next attempt starts after `retryIn`.
    case offline(CoreError, retryIn: Duration)
}

/// Keeps a subscription to herdr-core alive: reconnects with exponential backoff, resubscribes when the core says
/// the subscriber fell behind, and treats a silent connection (no heartbeat) as dead.
public struct CoreSession<C: Clock>: Sendable where C.Duration == Duration {
    public struct Configuration: Sendable, Hashable {
        public var initialBackoff: Duration
        public var maxBackoff: Duration
        /// The core sends a heartbeat every 15 s; no line for this long means the connection is dead.
        public var heartbeatTimeout: Duration

        public init(
            initialBackoff: Duration = .seconds(1), maxBackoff: Duration = .seconds(30),
            heartbeatTimeout: Duration = .seconds(40)
        ) {
            self.initialBackoff = initialBackoff
            self.maxBackoff = maxBackoff
            self.heartbeatTimeout = heartbeatTimeout
        }

        /// Delay after `failures` consecutive failures (0-based): initial, doubled each time, capped.
        public func backoff(afterFailures failures: Int) -> Duration {
            min(initialBackoff * (1 << min(max(failures, 0), 30)), maxBackoff)
        }
    }

    public let client: any CoreSubscribing
    public let configuration: Configuration
    public let clock: C
    private let now: @Sendable () -> Int

    /// - Parameter now: Unix milliseconds, used to stamp `statusMs` on status events.
    public init(
        client: any CoreSubscribing, configuration: Configuration = .init(), clock: C,
        now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.client = client
        self.configuration = configuration
        self.clock = clock
        self.now = now
    }

    /// Runs the session until the stream is dropped or its consumer is cancelled.
    public func updates() -> AsyncStream<SessionUpdate> {
        let (stream, continuation) = AsyncStream<SessionUpdate>.makeStream()
        let task = Task {
            await run { continuation.yield($0) }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    /// Runs the session in the current task until it is cancelled.
    public func run(_ emit: (SessionUpdate) -> Void) async {
        var failures = 0
        var resubscribe = false
        while !Task.isCancelled {
            if !resubscribe { emit(.connecting(attempt: failures)) }
            resubscribe = false
            let error: CoreError
            do {
                let subscription = try await client.subscribe()
                failures = 0
                var state = TerminalState(snapshot: subscription.snapshot)
                emit(.live(subscription.hello, state))
                let outcome = await consume(subscription, state: &state, emit: emit)
                subscription.cancel()
                switch outcome {
                case .resubscribe:
                    resubscribe = true
                    continue
                case .cancelled:
                    return
                case .failed(let failure):
                    error = failure
                }
            } catch let failure {
                error = failure
            }
            if Task.isCancelled { return }
            let delay = configuration.backoff(afterFailures: failures)
            failures += 1
            emit(.offline(error, retryIn: delay))
            do {
                try await clock.sleep(for: delay)
            } catch {
                return
            }
        }
    }

    private enum Outcome {
        case resubscribe
        case failed(CoreError)
        case cancelled
    }

    private final class Watchdog: Sendable {
        let lastActivity: Mutex<C.Instant>
        let fired = Atomic<Bool>(false)

        init(now: C.Instant) {
            lastActivity = Mutex(now)
        }
    }

    private func consume(
        _ subscription: CoreSubscription, state: inout TerminalState, emit: (SessionUpdate) -> Void
    ) async -> Outcome {
        let watchdog = Watchdog(now: clock.now)
        let (clock, timeout) = (clock, configuration.heartbeatTimeout)
        return await withTaskGroup(of: Void.self) { group in
            group.addTask {
                while !Task.isCancelled {
                    let deadline = watchdog.lastActivity.withLock { $0 }.advanced(by: timeout)
                    if clock.now >= deadline {
                        watchdog.fired.store(true, ordering: .sequentiallyConsistent)
                        subscription.cancel()
                        return
                    }
                    do {
                        try await clock.sleep(until: deadline, tolerance: nil)
                    } catch {
                        return
                    }
                }
            }
            defer { group.cancelAll() }
            var timedOut: Bool { watchdog.fired.load(ordering: .sequentiallyConsistent) }
            do {
                for try await notification in subscription.notifications {
                    let instant = clock.now
                    watchdog.lastActivity.withLock { $0 = instant }
                    switch notification {
                    case .event(let event):
                        if state.apply(event, now: now()) { emit(.state(state)) }
                    case .heartbeat:
                        break
                    case .missed(let snapshot?):
                        state.apply(snapshot: snapshot)
                        emit(.state(state))
                    case .missed(nil):
                        return .resubscribe
                    }
                }
            } catch {
                if timedOut { return .failed(.timeout) }
                return .failed(error as? CoreError ?? .invalidResponse(String(describing: error)))
            }
            if timedOut { return .failed(.timeout) }
            return Task.isCancelled ? .cancelled : .failed(.closed)
        }
    }
}

extension CoreSession where C == ContinuousClock {
    public init(client: any CoreSubscribing, configuration: Configuration = .init()) {
        self.init(client: client, configuration: configuration, clock: ContinuousClock())
    }
}
