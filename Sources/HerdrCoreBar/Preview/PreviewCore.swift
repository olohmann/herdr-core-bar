import Foundation
import HerdrCoreKit
import Synchronization

/// An in-memory core for `--preview`: serves `PreviewData` and applies "mark as read" locally.
nonisolated final class PreviewCore: CoreBackend, CoreCommanding, Sendable {
    private struct Storage {
        var state = PreviewData.state()
        var continuations: [UUID: AsyncStream<SessionUpdate>.Continuation] = [:]
    }

    private let storage = Mutex(Storage())

    func updates(socket: URL) -> AsyncStream<SessionUpdate> {
        let (stream, continuation) = AsyncStream<SessionUpdate>.makeStream()
        let id = UUID()
        let state = storage.withLock { storage in
            storage.continuations[id] = continuation
            return storage.state
        }
        continuation.onTermination = { [weak self] _ in
            _ = self?.storage.withLock { $0.continuations.removeValue(forKey: id) }
        }
        continuation.yield(.connecting(attempt: 0))
        continuation.yield(.live(PreviewData.hello, state))
        return stream
    }

    func commands(socket: URL) -> any CoreCommanding { self }

    func markRead(_ terminal: Terminal) async throws(CoreError) {
        let (state, continuations) = storage.withLock {
            storage -> (TerminalState, [AsyncStream<SessionUpdate>.Continuation]) in
            guard var updated = storage.state[terminal.address] else { return (storage.state, []) }
            updated.labels[Terminal.seenLabel] = String(updated.turn)
            var terminals = storage.state.terminals
            terminals[terminal.address] = updated
            storage.state = TerminalState(seq: storage.state.seq + 1, terminals: terminals)
            return (storage.state, Array(storage.continuations.values))
        }
        for continuation in continuations { continuation.yield(.state(state)) }
    }

    func fetchTerminalList() async throws(CoreError) -> TerminalList {
        let terminals = storage.withLock { $0.state.sorted }
        return TerminalList(terminals: terminals, machines: PreviewData.machines)
    }
}

/// Pretends to focus, so preview clicks never reach the real Herdr.app.
final class PreviewFocuser: TerminalFocusing {
    func focus(_ terminal: Terminal) async throws(FocusError) {
        try? await Task.sleep(for: .milliseconds(250))
    }
}
