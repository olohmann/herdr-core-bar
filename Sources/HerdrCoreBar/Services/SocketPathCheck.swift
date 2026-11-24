import Foundation

/// Checks a path the user typed for the herdr-core socket.
nonisolated enum SocketPathCheck: Equatable, Sendable {
    case socket
    case missing
    case notSocket

    init(path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: expanded) else {
            self = .missing
            return
        }
        self = attributes[.type] as? FileAttributeType == .typeSocket ? .socket : .notSocket
    }

    var message: String {
        switch self {
        case .socket: "herdr-core socket found."
        case .missing: "Nothing exists at this path (herdr-core may not be running)."
        case .notSocket: "This is not a socket."
        }
    }
}
