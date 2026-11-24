import Foundation
import HerdrCoreKit

/// One-shot requests to herdr-core besides the subscription.
nonisolated protocol CoreCommanding: Sendable {
    /// Writes `herdr.seen = turn`, as Herdr.app does when the user looks at a terminal.
    func markRead(_ terminal: Terminal) async throws(CoreError)
    func fetchTerminalList() async throws(CoreError) -> TerminalList
}

/// Where terminal state comes from: the real core, or synthetic data in preview mode.
nonisolated protocol CoreBackend: Sendable {
    func updates(socket: URL) -> AsyncStream<SessionUpdate>
    func commands(socket: URL) -> any CoreCommanding
}

nonisolated struct LiveCoreBackend: CoreBackend {
    func updates(socket: URL) -> AsyncStream<SessionUpdate> {
        CoreSession(client: CoreClient(socket: socket)).updates()
    }

    func commands(socket: URL) -> any CoreCommanding {
        CoreClient(socket: socket)
    }
}

extension CoreClient: CoreCommanding {
    func markRead(_ terminal: Terminal) async throws(CoreError) {
        try await markSeen(terminal)
    }

    func fetchTerminalList() async throws(CoreError) -> TerminalList {
        try await listTerminals(all: false)
    }
}
