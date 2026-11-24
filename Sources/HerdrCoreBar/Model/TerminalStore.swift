import Foundation
import HerdrCoreKit
import OSLog
import Observation

/// The terminals herdr-core knows about and the state of the link to it. Consumes `CoreSession` updates.
@Observable
final class TerminalStore {
    private(set) var connection: ConnectionState = .connecting(attempt: 0)
    private(set) var state = TerminalState()
    /// True once any snapshot arrived for the current socket.
    private(set) var hasSnapshot = false
    private(set) var machines: [MachineView] = []
    private(set) var socketURL: URL

    /// Called after every state change with the state before it. `previous` is nil for the first snapshot after
    /// start or a socket change, and the last known state after a reconnect (so `NotificationPolicy` stays quiet).
    @ObservationIgnored var onStateChange: ((TerminalState?, TerminalState) -> Void)?

    @ObservationIgnored private let backend: any CoreBackend
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastKnown: TerminalState?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let log = Logger(subsystem: "com.olohmann.herdr-core-bar", category: "store")

    init(backend: any CoreBackend, socketURL: URL, now: @escaping () -> Date = Date.init) {
        self.backend = backend
        self.socketURL = socketURL
        self.now = now
    }

    var commands: any CoreCommanding { backend.commands(socket: socketURL) }

    var isRunning: Bool { task != nil }

    func start() {
        guard task == nil else { return }
        let stream = backend.updates(socket: socketURL)
        task = Task { [weak self] in
            for await update in stream {
                guard let self, !Task.isCancelled else { return }
                self.handle(update)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Reconnects now, optionally to another socket (which forgets everything known about the old one).
    func restart(socket: URL? = nil) {
        stop()
        if let socket, socket != socketURL {
            socketURL = socket
            lastKnown = nil
            state = TerminalState()
            hasSnapshot = false
            machines = []
        }
        connection = .connecting(attempt: 0)
        start()
    }

    func replaceMachines(_ machines: [MachineView]) {
        self.machines = machines
    }

    /// Refreshes `machines` from `terminal.list`.
    func refreshMachines() async {
        guard connection.isLive else { return }
        if let list = try? await commands.fetchTerminalList() {
            replaceMachines(list.machines)
        }
    }

    func handle(_ update: SessionUpdate) {
        switch update {
        case .connecting(let attempt):
            if case .offline = connection {
                connection = .connecting(attempt: attempt)
            } else if !connection.isLive {
                connection = .connecting(attempt: attempt)
            }
        case .live(let hello, let snapshot):
            log.info(
                "Live: \(hello.core.name, privacy: .public) v\(hello.version, privacy: .public), \(snapshot.terminals.count) terminals"
            )
            connection = .live(CoreSummary(hello))
            apply(snapshot, previous: lastKnown)
            Task { await refreshMachines() }
        case .state(let next):
            apply(next, previous: state)
        case .offline(let error, let retryIn):
            log.info("Offline: \(error.description, privacy: .public); retry in \(retryIn, privacy: .public)")
            let retryAt = now().addingTimeInterval(retryIn.timeInterval)
            connection = .offline(
                OfflineInfo(error: error, socketPath: socketURL.path(percentEncoded: false), retryAt: retryAt))
        }
    }

    private func apply(_ next: TerminalState, previous: TerminalState?) {
        state = next
        hasSnapshot = true
        lastKnown = next
        onStateChange?(previous, next)
    }
}

extension Duration {
    nonisolated var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
