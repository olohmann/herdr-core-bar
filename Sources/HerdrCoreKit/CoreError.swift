/// Everything that can go wrong talking to herdr-core.
public enum CoreError: Error, Sendable, Hashable, CustomStringConvertible {
    /// The socket could not be opened (core not running, wrong path, permissions).
    case connectFailed(path: String, reason: String)
    /// The core does not speak protocol generation 1.
    case unsupportedGeneration
    /// The core answered with a JSON-RPC error; `kind` is `error.data.kind` (e.g. `not_found`).
    case server(kind: String, message: String)
    /// A line was not valid JSON-RPC or a result/notification did not have the expected shape.
    case invalidResponse(String)
    /// A line exceeded the configured maximum length.
    case lineTooLong
    /// The connection was closed (by us or by the core).
    case closed
    /// No answer or no traffic in time.
    case timeout
    /// The waiting task was cancelled.
    case cancelled

    public var description: String {
        switch self {
        case .connectFailed(let path, let reason): "cannot connect to \(path): \(reason)"
        case .unsupportedGeneration: "herdr-core does not support protocol generation 1"
        case .server(let kind, let message): kind == message ? "core error: \(kind)" : "core error \(kind): \(message)"
        case .invalidResponse(let detail): "invalid response from core: \(detail)"
        case .lineTooLong: "core sent a line that is too long"
        case .closed: "connection to core closed"
        case .timeout: "core did not answer in time"
        case .cancelled: "cancelled"
        }
    }
}
