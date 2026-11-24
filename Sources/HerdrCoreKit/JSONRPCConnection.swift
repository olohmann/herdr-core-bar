import Dispatch
import Foundation
import Synchronization

#if canImport(Darwin)
    import Darwin
#endif

/// A JSON-RPC notification as received: its method plus the raw line, decoded on demand.
public struct JSONRPCNotification: Sendable, Hashable {
    public let method: String
    public let line: Data

    public init(method: String, line: Data) {
        self.method = method
        self.line = line
    }

    /// The `params` member, or nil when absent or null.
    public func params<P: Decodable>(as type: P.Type = P.self) throws(CoreError) -> P? {
        do {
            return try JSONDecoder().decode(ParamsEnvelope<P>.self, from: line).params
        } catch {
            throw .invalidResponse("\(method) params: \(error)")
        }
    }
}

/// One JSON-RPC 2.0 connection to herdr-core over a UNIX stream socket, with newline-delimited framing.
///
/// Transport choice: POSIX `socket`/`connect` plus a `DispatchIO` stream channel. A UNIX-socket `connect` fails
/// immediately with a precise errno (`ENOENT` = core not running, `ECONNREFUSED` = stale socket), which
/// `NWConnection` hides behind an endlessly retrying `.waiting` state. DispatchIO then gives ordered, non-blocking
/// reads and writes on one serial queue and owns the descriptor: its cleanup handler closes it exactly once.
///
/// State lives in a `Mutex` rather than an actor so the I/O callbacks can resolve requests and emit notifications
/// synchronously and in wire order.
public final class JSONRPCConnection: Sendable {
    public struct Configuration: Sendable, Hashable {
        /// Longest accepted line in bytes; longer lines close the connection with `CoreError.lineTooLong`.
        public var maxLineLength: Int
        public var connectTimeout: Duration
        /// Per-request deadline; nil waits forever.
        public var requestTimeout: Duration?

        public init(
            maxLineLength: Int = 4 << 20, connectTimeout: Duration = .seconds(5),
            requestTimeout: Duration? = .seconds(15)
        ) {
            self.maxLineLength = maxLineLength
            self.connectTimeout = connectTimeout
            self.requestTimeout = requestTimeout
        }
    }

    private typealias Reply = CheckedContinuation<Result<Data, CoreError>, Never>

    private struct NotificationSink: Sendable {
        let yield: @Sendable (JSONRPCNotification) -> Void
        let finish: @Sendable ((any Error)?) -> Void
    }

    private struct State {
        var nextID = 1
        var pending: [Int: Reply] = [:]
        var buffer: LineBuffer
        var closedBy: CoreError?
        var sink: NotificationSink?
    }

    public let configuration: Configuration
    private let state: Mutex<State>
    private let queue: DispatchQueue
    private let io: DispatchIO

    /// Opens the socket at `path`.
    public static func connect(
        path: String, configuration: Configuration = .init()
    ) async throws(CoreError) -> JSONRPCConnection {
        let timeout = configuration.connectTimeout
        let result: Result<Int32, CoreError> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do throws(CoreError) {
                    continuation.resume(returning: .success(try openSocket(path: path, timeout: timeout)))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
        return JSONRPCConnection(fileDescriptor: try result.get(), configuration: configuration)
    }

    /// Takes ownership of a connected stream socket.
    init(fileDescriptor: Int32, configuration: Configuration = .init()) {
        self.configuration = configuration
        state = Mutex(State(buffer: LineBuffer(maxLineLength: configuration.maxLineLength)))
        queue = DispatchQueue(label: "HerdrCoreKit.JSONRPCConnection")
        io = DispatchIO(type: .stream, fileDescriptor: fileDescriptor, queue: queue) { _ in
            _ = Darwin.close(fileDescriptor)
        }
        io.setLimit(lowWater: 1)
        io.read(offset: 0, length: Int.max, queue: queue) { [weak self] done, data, _ in
            guard let self else { return }
            if let data, !data.isEmpty { self.receive(data) }
            if done { self.shutdown(with: .closed, streamError: .closed) }
        }
    }

    deinit {
        shutdown(with: .closed, streamError: nil)
    }

    public var isClosed: Bool { state.withLock { $0.closedBy != nil } }

    /// Closes the connection. Pending calls fail with `.closed`; notification streams finish normally.
    public func close() {
        shutdown(with: .closed, streamError: nil)
    }

    /// Sends a request and waits for its response.
    public func call<P: Encodable, R: Decodable>(
        _ method: String, params: P, as type: R.Type = R.self
    ) async throws(CoreError) -> R {
        let id = state.withLock { state in
            defer { state.nextID += 1 }
            return state.nextID
        }
        var request: Data
        do {
            request = try JSONEncoder().encode(Request(id: id, method: method, params: params))
        } catch {
            throw .invalidResponse("cannot encode \(method) params: \(error)")
        }
        request.append(0x0A)
        let timeout = configuration.requestTimeout
        let line = try await withTaskCancellationHandler {
            await withCheckedContinuation { (reply: Reply) in
                let closed: CoreError? = state.withLock { state in
                    if let closedBy = state.closedBy { return closedBy }
                    state.pending[id] = reply
                    return nil
                }
                if let closed {
                    reply.resume(returning: .failure(closed))
                    return
                }
                write(request)
                if let timeout {
                    queue.asyncAfter(deadline: .now() + timeout.timeInterval) { [weak self] in
                        self?.resolve(id, with: .failure(.timeout))
                    }
                }
                if Task.isCancelled { resolve(id, with: .failure(.cancelled)) }
            }
        } onCancel: {
            resolve(id, with: .failure(.cancelled))
        }.get()
        do {
            return try JSONDecoder().decode(ResultEnvelope<R>.self, from: line).result
        } catch {
            throw .invalidResponse("\(method) result: \(error)")
        }
    }

    /// Notifications as they arrive. Only one stream is active: a new one finishes the previous.
    /// Cancelling the iterating task, or dropping the stream and its iterators, closes the connection.
    public func notifications() -> AsyncThrowingStream<JSONRPCNotification, any Error> {
        notifications { $0 }
    }

    /// Notifications mapped on the I/O queue; `transform` returns nil to skip one and throws to close the connection.
    public func notifications<T: Sendable>(
        _ transform: @escaping @Sendable (JSONRPCNotification) throws(CoreError) -> T?
    ) -> AsyncThrowingStream<T, any Error> {
        let (stream, continuation) = AsyncThrowingStream<T, any Error>.makeStream()
        let sink = NotificationSink(
            yield: { [weak self] notification in
                do throws(CoreError) {
                    if let value = try transform(notification) { continuation.yield(value) }
                } catch {
                    self?.shutdown(with: error, streamError: error)
                }
            },
            finish: { continuation.finish(throwing: $0) }
        )
        continuation.onTermination = { [weak self] _ in self?.close() }
        let (closed, previous): (CoreError?, NotificationSink?) = state.withLock { state in
            if let closedBy = state.closedBy { return (closedBy, nil) }
            defer { state.sink = sink }
            return (nil, state.sink)
        }
        previous?.finish(nil)
        if let closed { continuation.finish(throwing: closed) }
        return stream
    }

    // MARK: - I/O

    private func write(_ data: Data) {
        let chunk = data.withUnsafeBytes { DispatchData(bytes: $0) }
        io.write(offset: 0, data: chunk, queue: queue) { [weak self] done, _, error in
            if done, error != 0 { self?.shutdown(with: .closed, streamError: .closed) }
        }
    }

    private func receive(_ data: DispatchData) {
        var bytes = [UInt8](repeating: 0, count: data.count)
        bytes.withUnsafeMutableBufferPointer { _ = data.copyBytes(to: $0) }
        let lines: Result<[Data], CoreError> = state.withLock { state in
            do throws(CoreError) {
                return .success(try state.buffer.append(bytes))
            } catch {
                return .failure(error)
            }
        }
        switch lines {
        case .success(let lines):
            for line in lines where !isClosed { handle(line) }
        case .failure(let error):
            shutdown(with: error, streamError: error)
        }
    }

    private func handle(_ line: Data) {
        let message: Incoming
        do {
            message = try JSONDecoder().decode(Incoming.self, from: line)
        } catch {
            let error = CoreError.invalidResponse("not a JSON-RPC message: \(error)")
            shutdown(with: error, streamError: error)
            return
        }
        if let method = message.method {
            // Requests from the core (method + id) are not part of this client's protocol; ignore them.
            guard message.id == nil else { return }
            let sink = state.withLock { $0.sink }
            sink?.yield(JSONRPCNotification(method: method, line: line))
        } else if let id = message.id {
            if let error = message.error {
                resolve(id, with: .failure(error.coreError))
            } else {
                resolve(id, with: .success(line))
            }
        }
    }

    private func resolve(_ id: Int, with result: Result<Data, CoreError>) {
        let reply = state.withLock { $0.pending.removeValue(forKey: id) }
        reply?.resume(returning: result)
    }

    private func shutdown(with error: CoreError, streamError: CoreError?) {
        let taken: (pending: [Int: Reply], sink: NotificationSink?)? = state.withLock { state in
            guard state.closedBy == nil else { return nil }
            state.closedBy = error
            defer {
                state.pending = [:]
                state.sink = nil
            }
            return (state.pending, state.sink)
        }
        guard let taken else { return }
        io.close(flags: .stop)
        for reply in taken.pending.values { reply.resume(returning: .failure(error)) }
        taken.sink?.finish(streamError)
    }

    // MARK: - Socket

    private static func openSocket(path: String, timeout: Duration) throws(CoreError) -> Int32 {
        func failure(_ reason: String) -> CoreError { .connectFailed(path: path, reason: reason) }
        func errnoText(_ code: Int32) -> String { String(cString: strerror(code)) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard !pathBytes.isEmpty, pathBytes.count < capacity else { throw failure("socket path too long or empty") }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
            buffer[pathBytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw failure(errnoText(errno)) }
        var keep = false
        defer { if !keep { _ = Darwin.close(fd) } }

        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var on: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 {
            let code = errno
            guard code == EINPROGRESS || code == EINTR else { throw failure(errnoText(code)) }
            var poller = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let milliseconds = Int32(clamping: Int((timeout.timeInterval * 1000).rounded(.up)))
            let ready = poll(&poller, 1, milliseconds)
            guard ready > 0 else { throw ready == 0 ? .timeout : failure(errnoText(errno)) }
            var socketError: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            _ = getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &length)
            guard socketError == 0 else { throw failure(errnoText(socketError)) }
        }
        keep = true
        return fd
    }
}

private struct Request<P: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: P
}

private struct ResultEnvelope<R: Decodable>: Decodable {
    let result: R
}

struct ParamsEnvelope<P: Decodable>: Decodable {
    let params: P?
}

private struct Incoming: Decodable {
    struct RPCError: Decodable {
        struct Details: Decodable {
            let kind: String?
        }

        let code: Int?
        let message: String?
        let data: Details?

        var coreError: CoreError {
            let message = message ?? "error \(code ?? 0)"
            let kind = data?.kind ?? message
            return kind == "unsupported_generation" ? .unsupportedGeneration : .server(kind: kind, message: message)
        }

        private enum CodingKeys: String, CodingKey { case code, message, data }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try? c.decodeIfPresent(Int.self, forKey: .code)
            message = try? c.decodeIfPresent(String.self, forKey: .message)
            data = try? c.decodeIfPresent(Details.self, forKey: .data)
        }
    }

    let id: Int?
    let method: String?
    let error: RPCError?

    private enum CodingKeys: String, CodingKey { case id, method, error }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try? c.decodeIfPresent(Int.self, forKey: .id)
        method = try? c.decodeIfPresent(String.self, forKey: .method)
        error = try c.decodeIfPresent(RPCError.self, forKey: .error)
    }
}

/// Encodes as `{}`.
public struct EmptyParams: Codable, Sendable, Hashable {
    public init() {}
}

extension Duration {
    var timeInterval: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
