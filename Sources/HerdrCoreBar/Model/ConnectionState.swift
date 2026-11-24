import Foundation
import HerdrCoreKit

/// What the popover header and empty states show about the link to herdr-core.
nonisolated enum ConnectionState: Equatable, Sendable {
    case connecting(attempt: Int)
    case live(CoreSummary)
    case offline(OfflineInfo)

    var isLive: Bool {
        if case .live = self { return true }
        return false
    }

    var core: CoreSummary? {
        if case .live(let core) = self { return core }
        return nil
    }
}

nonisolated struct CoreSummary: Equatable, Sendable {
    var id: String
    var name: String
    var version: String
    var generation: Int

    init(id: String, name: String, version: String, generation: Int) {
        self.id = id
        self.name = name
        self.version = version
        self.generation = generation
    }

    init(_ hello: HelloResult) {
        self.init(id: hello.core.id, name: hello.core.name, version: hello.version, generation: hello.generation)
    }
}

nonisolated struct OfflineInfo: Equatable, Sendable {
    enum Reason: Equatable {
        /// Nothing listens on the socket (core not running, or a different path).
        case notRunning
        case permissionDenied
        case incompatible
        /// Was connected, or answered strangely; detail is technical.
        case failed(String)
    }

    var reason: Reason
    var socketPath: String
    var retryAt: Date
    var detail: String

    init(error: CoreError, socketPath: String, retryAt: Date) {
        self.socketPath = socketPath
        self.retryAt = retryAt
        detail = error.description
        switch error {
        case .connectFailed(_, let why):
            let lower = why.lowercased()
            if lower.contains("permission") || lower.contains("not permitted") {
                reason = .permissionDenied
            } else if lower.contains("no such file") || lower.contains("refused") || lower.contains("not found") {
                reason = .notRunning
            } else {
                reason = .failed(why)
            }
        case .unsupportedGeneration:
            reason = .incompatible
        default:
            reason = .failed(error.description)
        }
    }

    var title: String {
        switch reason {
        case .notRunning: "herdr-core isn't running"
        case .permissionDenied: "Can't open the herdr-core socket"
        case .incompatible: "Incompatible herdr-core"
        case .failed: "Lost connection to herdr-core"
        }
    }

    var explanation: String {
        switch reason {
        case .notRunning:
            "Nothing is listening at the socket. Open Herdr to start it, or choose another socket in Settings."
        case .permissionDenied:
            "The socket exists but this app may not open it. Check its permissions or choose another path."
        case .incompatible:
            "This herdr-core speaks a different protocol generation. Update Herdr and Herdr Core Bar."
        case .failed(let detail):
            detail
        }
    }
}
