import Foundation
import Testing

@testable import HerdrCoreKit

@Suite("CoreSession", .timeLimit(.minutes(1)))
struct CoreSessionTests {
    let snapshot = Snapshot(seq: 10, terminals: [agent("t1", .working, turn: 1)])

    @Test func backoffDoublesUpToCap() async throws {
        let clock = TestClock()
        let core = FakeCore([])
        let session = CoreSession(client: core, clock: clock)
        var retries: [Duration] = []
        var attempts: [Int] = []
        for await update in session.updates() {
            switch update {
            case .connecting(let attempt): attempts.append(attempt)
            case .offline(let error, let retryIn):
                #expect(error == .connectFailed(path: "fake", reason: "gone"))
                retries.append(retryIn)
            default: Issue.record("unexpected \(update)")
            }
            if retries.count == 7 { break }
        }
        #expect(retries == [1, 2, 4, 8, 16, 30, 30].map { Duration.seconds($0) })
        #expect(attempts == Array(0...6))
        #expect(Array(clock.sleeps.prefix(6)) == [1, 2, 4, 8, 16, 30].map { Duration.seconds($0) })
    }

    @Test func backoffResetsAfterSuccessAndReconnects() async throws {
        let core = FakeCore([.fail(.closed), .fail(.closed), .succeed(snapshot), .succeed(snapshot)])
        let session = CoreSession(
            client: core, configuration: .init(initialBackoff: .milliseconds(5), maxBackoff: .milliseconds(50)))
        var log: [String] = []
        for await update in session.updates() {
            switch update {
            case .connecting(let attempt): log.append("connecting \(attempt)")
            case .offline(let error, let retryIn): log.append("offline \(error) \(retryIn)")
            case .live(let hello, let state):
                log.append("live \(hello.core.name) \(state.seq)")
                if log.filter({ $0.hasPrefix("live") }).count == 1 { try await core.feed(1).finish() }
            case .state: log.append("state")
            }
            if log.filter({ $0.hasPrefix("live") }).count == 2 { break }
        }
        #expect(
            log == [
                "connecting 0", "offline connection to core closed 0.005 seconds",
                "connecting 1", "offline connection to core closed 0.01 seconds",
                "connecting 2", "live fake 10",
                "offline connection to core closed 0.005 seconds",
                "connecting 1", "live fake 10",
            ])
    }

    @Test func appliesEventsAndStampsStatusTime() async throws {
        let core = FakeCore([.succeed(snapshot)])
        let session = CoreSession(client: core, clock: ContinuousClock(), now: { 42_000 })
        var states: [TerminalState] = []
        for await update in session.updates() {
            switch update {
            case .live:
                let feed = try await core.feed(1)
                feed.yield(.heartbeat(seq: 10))
                feed.yield(.event(CoreEvent(seq: 9, terminal: "t1", kind: .title("stale"))))
                feed.yield(
                    .event(
                        CoreEvent(
                            seq: 11, terminal: "t1", kind: .status(TerminalStatus(state: .blocked), reported: true))))
                feed.yield(.event(CoreEvent(seq: 12, terminal: "t1", kind: .title("now"))))
            case .state(let state): states.append(state)
            default: break
            }
            if states.count == 2 { break }
        }
        #expect(states.map(\.seq) == [11, 12])
        #expect(states[0]["t1"]?.status?.state == .blocked && states[0]["t1"]?.statusMs == 42_000)
        #expect(states[1]["t1"]?.title == "now")
    }

    @Test func missedResyncsOrResubscribes() async throws {
        let replacement = Snapshot(seq: 50, terminals: [agent("t2", .done, turn: 1)])
        let core = FakeCore([.succeed(snapshot), .succeed(snapshot)])
        let session = CoreSession(client: core)
        var log: [String] = []
        for await update in session.updates() {
            switch update {
            case .connecting: log.append("connecting")
            case .live:
                log.append("live")
                if log.count == 2 {
                    let feed = try await core.feed(1)
                    feed.yield(.missed(replacement))
                    feed.yield(.event(CoreEvent(seq: 50, terminal: "t2", kind: .title("dropped"))))
                    feed.yield(.event(CoreEvent(seq: 51, terminal: "t2", kind: .title("kept"))))
                    feed.yield(.missed(nil))
                }
            case .state(let state):
                log.append("state \(state.seq) \(state.terminals.keys.sorted()) \(state["t2"]?.title ?? "")")
            case .offline: log.append("offline")
            }
            if log.count == 5 { break }
        }
        #expect(log == ["connecting", "live", "state 50 [\"t2\"] ", "state 51 [\"t2\"] kept", "live"])
        #expect(core.calls == 2 && core.cancelled >= 1)
    }

    @Test func silentConnectionTimesOut() async throws {
        let clock = TestClock()
        let core = FakeCore([.succeed(snapshot)])
        let session = CoreSession(client: core, configuration: .init(heartbeatTimeout: .seconds(40)), clock: clock)
        var offline: CoreError?
        for await update in session.updates() {
            if case .offline(let error, _) = update {
                offline = error
                break
            }
        }
        #expect(offline == .timeout)
        #expect(core.cancelled >= 1)
        #expect(clock.sleeps.first == .seconds(40))
    }

    @Test func streamErrorsGoOffline() async throws {
        let core = FakeCore([.succeed(snapshot)])
        let session = CoreSession(client: core, configuration: .init(initialBackoff: .seconds(3)))
        for await update in session.updates() {
            if case .live = update { try await core.feed(1).finish(throwing: CoreError.lineTooLong) }
            if case .offline(let error, let retryIn) = update {
                #expect(error == .lineTooLong && retryIn == .seconds(3))
                break
            }
        }
    }

    @Test func droppingTheStreamCancelsTheSubscription() async throws {
        let core = FakeCore([.succeed(snapshot)])
        let session = CoreSession(client: core)
        for await update in session.updates() {
            if case .live = update { break }
        }
        for _ in 0..<200 where core.cancelled == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(core.cancelled == 1)
        #expect(core.calls == 1)
    }
}
