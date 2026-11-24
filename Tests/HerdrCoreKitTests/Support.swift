import Foundation
import Synchronization
import Testing

@testable import HerdrCoreKit

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: data(name))
    }

    static func lines(_ name: String) throws -> [Data] {
        try data(name).split(separator: 0x0A).map { Data($0) }
    }

    static func notification(_ line: Data) throws -> JSONRPCNotification {
        let object = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        return JSONRPCNotification(method: try #require(object["method"] as? String), line: line)
    }

    static func notifications(_ name: String) throws -> [CoreNotification] {
        try lines(name).compactMap { try CoreNotification(notification($0)) }
    }

    static func events(_ name: String = "events.jsonl") throws -> [CoreEvent] {
        try notifications(name).compactMap {
            if case .event(let event) = $0 { return event }
            return nil
        }
    }

    static var snapshot: Snapshot {
        get throws { try decode(Snapshot.self, from: "snapshot.json") }
    }

    static var hello: HelloResult {
        get throws { try decode(HelloResult.self, from: "hello.json") }
    }
}

func agent(
    _ address: String, _ state: StatusWord?, turn: Int = 0, seen: Int? = nil, title: String = "",
    kind: BlockedKind? = nil, msg: String? = nil, lifecycle: TerminalLifecycle = .live
) -> Terminal {
    var labels: [String: String] = [:]
    if let seen { labels[Terminal.seenLabel] = String(seen) }
    return Terminal(
        address: address, labels: labels, argv: ["agent"], cwd: "/home/sample/work", lifecycle: lifecycle,
        title: title, status: state.map { TerminalStatus(state: $0, kind: kind, msg: msg) }, turn: turn,
        reported: state != nil)
}

func state(seq: Int = 1, _ terminals: Terminal...) -> TerminalState {
    TerminalState(snapshot: Snapshot(seq: seq, terminals: terminals))
}

// MARK: - Socket peers

/// The far end of a socket, driven by blocking calls on a background queue.
final class SocketPeer: Sendable {
    let fd: Int32
    private let buffer = Mutex(Data())

    init(fd: Int32) {
        self.fd = fd
        var on: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    deinit { _ = Darwin.close(fd) }

    /// A connection and its peer joined by `socketpair`.
    static func pair(
        _ configuration: JSONRPCConnection.Configuration = .init()
    ) throws -> (JSONRPCConnection, SocketPeer) {
        var fds: [Int32] = [-1, -1]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        return (JSONRPCConnection(fileDescriptor: fds[0], configuration: configuration), SocketPeer(fd: fds[1]))
    }

    func send(_ text: String) {
        var bytes = Array(text.utf8)
        while !bytes.isEmpty {
            let written = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            guard written > 0 else { return }
            bytes.removeFirst(written)
        }
    }

    func close() {
        _ = shutdown(fd, SHUT_RDWR)
    }

    enum ReadOutcome: Sendable, Equatable {
        case line(String)
        case eof
        case silence
    }

    /// Next line, or nil on EOF or after `timeout` seconds of silence.
    func readLine(timeout: Double = 5) async -> String? {
        if case .line(let line) = await read(timeout: timeout) { return line }
        return nil
    }

    /// True when the other side closed the connection (not merely went quiet).
    func sawEOF(timeout: Double = 5) async -> Bool {
        await read(timeout: timeout) == .eof
    }

    func read(timeout: Double) async -> ReadOutcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: self.blockingRead(timeout: timeout)) }
        }
    }

    /// Reads a request and returns its id, method and params.
    func readRequest() async throws -> (id: Int, method: String, params: [String: String]) {
        let line = try #require(await readLine())
        let object = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let params = (object["params"] as? [String: Any] ?? [:]).mapValues { "\($0)" }
        return (try #require(object["id"] as? Int), try #require(object["method"] as? String), params)
    }

    /// Sends a result; newlines in `result` (pretty fixtures) are dropped to keep it one line.
    func respond(_ id: Int, result: String) {
        let result = result.replacingOccurrences(of: "\n", with: "")
        send(#"{"jsonrpc":"2.0","id":\#(id),"result":\#(result)}"# + "\n")
    }

    func respond(_ id: Int, errorKind: String) {
        send(
            #"{"jsonrpc":"2.0","id":\#(id),"error":{"code":-32000,"message":"\#(errorKind)","data":{"kind":"\#(errorKind)"}}}"#
                + "\n")
    }

    private func blockingRead(timeout: Double) -> ReadOutcome {
        while true {
            let line: Data? = buffer.withLock { buffer in
                guard let newline = buffer.firstIndex(of: 0x0A) else { return nil }
                defer { buffer.removeSubrange(...newline) }
                return buffer[..<newline]
            }
            if let line { return .line(String(decoding: line, as: UTF8.self)) }
            var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, Int32(timeout * 1000)) > 0 else { return .silence }
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            let count = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            guard count > 0 else { return .eof }
            buffer.withLock { $0.append(contentsOf: chunk[..<count]) }
        }
    }
}

/// A listening UNIX socket under the package directory (sockets are not written to temporary directories).
final class UnixServer: Sendable {
    let path: String
    private let fd: Int32

    init() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = root.appending(path: ".build-sockets")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appending(path: "k\(String(UInt32.random(in: .min ... .max), radix: 36)).sock")
            .path(percentEncoded: false)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        try #require(bytes.count < MemoryLayout.size(ofValue: address.sun_path), "socket path too long: \(path)")
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        try #require(bound == 0 && listen(fd, 4) == 0)
    }

    deinit {
        _ = Darwin.close(fd)
        unlink(path)
    }

    func accept() async -> SocketPeer? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                var poller = pollfd(fd: self.fd, events: Int16(POLLIN), revents: 0)
                guard poll(&poller, 1, 5000) > 0 else { return continuation.resume(returning: nil) }
                let client = Darwin.accept(self.fd, nil, nil)
                continuation.resume(returning: client >= 0 ? SocketPeer(fd: client) : nil)
            }
        }
    }
}

// MARK: - Fakes for the session

/// A clock whose sleeps complete at once, advancing virtual time to the deadline.
final class TestClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private let state = Mutex((now: Instant(offset: .zero), sleeps: [Duration]()))

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }
    var sleeps: [Duration] { state.withLock { $0.sleeps } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        state.withLock { state in
            state.sleeps.append(state.now.duration(to: deadline))
            if deadline > state.now { state.now = deadline }
        }
        await Task.yield()
        try Task.checkCancellation()
    }
}

/// A scripted `CoreSubscribing`: each `subscribe` takes the next step; successful ones expose their stream.
final class FakeCore: CoreSubscribing {
    enum Step: Sendable {
        case fail(CoreError)
        case succeed(Snapshot)
    }

    typealias Feed = AsyncThrowingStream<CoreNotification, any Error>.Continuation

    private let state: Mutex<(steps: [Step], feeds: [Feed], cancelled: Int, calls: Int)>
    let hello = HelloResult(core: CoreInfo(id: "c1", name: "fake"), version: "0.0.0")

    init(_ steps: [Step]) {
        state = Mutex((steps, [], 0, 0))
    }

    var feeds: [Feed] { state.withLock { $0.feeds } }
    var cancelled: Int { state.withLock { $0.cancelled } }
    var calls: Int { state.withLock { $0.calls } }

    func subscribe() async throws(CoreError) -> CoreSubscription {
        let step: Step = state.withLock { state in
            state.calls += 1
            return state.steps.isEmpty ? .fail(.connectFailed(path: "fake", reason: "gone")) : state.steps.removeFirst()
        }
        switch step {
        case .fail(let error):
            throw error
        case .succeed(let snapshot):
            let (stream, feed) = AsyncThrowingStream<CoreNotification, any Error>.makeStream()
            state.withLock { $0.feeds.append(feed) }
            return CoreSubscription(hello: hello, snapshot: snapshot, notifications: stream) { [weak self] in
                self?.state.withLock { $0.cancelled += 1 }
                feed.finish()
            }
        }
    }

    /// Waits until `count` subscriptions succeeded and returns the latest feed.
    func feed(_ count: Int) async throws -> Feed {
        for _ in 0..<500 {
            let feeds = self.feeds
            if feeds.count >= count { return feeds[count - 1] }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CoreError.timeout
    }
}
