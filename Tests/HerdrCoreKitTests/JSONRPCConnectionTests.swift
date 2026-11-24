import Foundation
import Testing

@testable import HerdrCoreKit

@Suite("LineBuffer")
struct LineBufferTests {
    @Test func splitsAcrossChunks() throws {
        var buffer = LineBuffer(maxLineLength: 100)
        #expect(try buffer.append(Array("{\"a\":".utf8)).isEmpty)
        let lines = try buffer.append(Array("1}\n\n{\"b\":2}\r\n{\"c\"".utf8))
        #expect(lines.map { String(decoding: $0, as: UTF8.self) } == [#"{"a":1}"#, #"{"b":2}"#])
        #expect(try buffer.append(Array(":3}\n".utf8)).map { String(decoding: $0, as: UTF8.self) } == [#"{"c":3}"#])
    }

    @Test func enforcesMaximum() throws {
        var exact = LineBuffer(maxLineLength: 4)
        #expect(try exact.append(Array("abcd\n".utf8)).count == 1)
        var long = LineBuffer(maxLineLength: 4)
        #expect(throws: CoreError.lineTooLong) { try long.append(Array("abcde\n".utf8)) }
        var unterminated = LineBuffer(maxLineLength: 4)
        _ = try unterminated.append(Array("abc".utf8))
        #expect(throws: CoreError.lineTooLong) { try unterminated.append(Array("de".utf8)) }
    }
}

@Suite("JSONRPCConnection", .timeLimit(.minutes(1)))
struct JSONRPCConnectionTests {
    struct Echo: Codable, Equatable {
        var value: String
    }

    @Test func correlatesOutOfOrderResponses() async throws {
        let (connection, peer) = try SocketPeer.pair()
        async let first = connection.call("echo", params: Echo(value: "a"), as: Echo.self)
        async let second = connection.call("echo", params: Echo(value: "b"), as: Echo.self)
        var requests = [try await peer.readRequest(), try await peer.readRequest()]
        requests.sort { $0.id > $1.id }
        for request in requests {
            #expect(request.method == "echo")
            peer.respond(request.id, result: #"{"value":"\#(request.params["value"]!)"}"#)
        }
        #expect(try await first == Echo(value: "a"))
        #expect(try await second == Echo(value: "b"))
    }

    @Test func interleavesNotificationsInOrder() async throws {
        let (connection, peer) = try SocketPeer.pair()
        let notifications = connection.notifications()
        async let reply = connection.call("ping", params: EmptyParams(), as: Echo.self)
        let request = try await peer.readRequest()
        peer.send(
            #"{"jsonrpc":"2.0","method":"heartbeat","params":{"seq":1}}"# + "\n"
                + #"{"jsonrpc":"2.0","id":\#(request.id),"result":{"value":"pong"}}"# + "\n"
                + #"{"jsonrpc":"2.0","method":"event","params":{"seq":2}}"# + "\n"
                + #"{"jsonrpc":"2.0","id":99,"method":"server.asks","params":{}}"# + "\n")
        #expect(try await reply == Echo(value: "pong"))
        var methods: [String] = []
        for try await notification in notifications {
            methods.append(notification.method)
            if methods.count == 2 { break }
        }
        #expect(methods == ["heartbeat", "event"])
        #expect(!connection.isClosed)
    }

    @Test func droppingTheNotificationStreamClosesTheConnection() async throws {
        let (connection, peer) = try SocketPeer.pair()
        _ = connection.notifications()
        #expect(connection.isClosed)
        #expect(await peer.sawEOF())
    }

    @Test func serverErrorsAreTyped() async throws {
        let (connection, peer) = try SocketPeer.pair()
        let missing = Task { try await connection.call("terminal.label", params: EmptyParams(), as: Terminal.self) }
        peer.respond(try await peer.readRequest().id, errorKind: "not_found")
        await #expect(throws: CoreError.server(kind: "not_found", message: "not_found")) { try await missing.value }

        let old = Task { try await connection.call("hello", params: EmptyParams(), as: HelloResult.self) }
        peer.respond(try await peer.readRequest().id, errorKind: "unsupported_generation")
        await #expect(throws: CoreError.unsupportedGeneration) { try await old.value }

        let wrongShape = Task { try await connection.call("hello", params: EmptyParams(), as: HelloResult.self) }
        peer.respond(try await peer.readRequest().id, result: #"{"nope":true}"#)
        await #expect {
            try await wrongShape.value
        } throws: { error in
            if case .invalidResponse = error as? CoreError { return true }
            return false
        }
    }

    @Test func lineTooLongClosesConnection() async throws {
        let (connection, peer) = try SocketPeer.pair(.init(maxLineLength: 64))
        let notifications = connection.notifications()
        let reply = Task { try await connection.call("ping", params: EmptyParams(), as: Echo.self) }
        _ = try await peer.readRequest()
        peer.send(String(repeating: "x", count: 100))
        await #expect(throws: CoreError.lineTooLong) { try await reply.value }
        await #expect(throws: CoreError.lineTooLong) {
            for try await _ in notifications {}
        }
        await #expect(throws: CoreError.lineTooLong) {
            try await connection.call("ping", params: EmptyParams(), as: Echo.self)
        }
    }

    @Test func invalidJSONClosesConnection() async throws {
        let (connection, peer) = try SocketPeer.pair()
        let notifications = connection.notifications()
        peer.send("this is not json\n")
        await #expect {
            for try await _ in notifications {}
        } throws: { error in
            if case .invalidResponse = error as? CoreError { return true }
            return false
        }
    }

    @Test func peerCloseFailsPendingAndEndsStream() async throws {
        let (connection, peer) = try SocketPeer.pair()
        let notifications = connection.notifications()
        let reply = Task { try await connection.call("ping", params: EmptyParams(), as: Echo.self) }
        _ = try await peer.readRequest()
        peer.close()
        await #expect(throws: CoreError.closed) { try await reply.value }
        await #expect(throws: CoreError.closed) {
            for try await _ in notifications {}
        }
    }

    @Test func cancellationFailsOnlyThatCall() async throws {
        let (connection, peer) = try SocketPeer.pair()
        let task = Task { try await connection.call("slow", params: EmptyParams(), as: Echo.self) }
        let slow = try await peer.readRequest()
        task.cancel()
        await #expect(throws: CoreError.cancelled) { try await task.value }

        async let fast = connection.call("fast", params: EmptyParams(), as: Echo.self)
        let request = try await peer.readRequest()
        peer.respond(slow.id, result: #"{"value":"too late"}"#)
        peer.respond(request.id, result: #"{"value":"ok"}"#)
        #expect(try await fast == Echo(value: "ok"))
        #expect(!connection.isClosed)
    }

    @Test func alreadyCancelledTaskDoesNotHang() async throws {
        let (connection, _) = try SocketPeer.pair()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await connection.call("x", params: EmptyParams(), as: Echo.self)
        }
        await #expect(throws: CoreError.cancelled) { try await task.value }
    }

    @Test func requestTimeout() async throws {
        let (connection, peer) = try SocketPeer.pair(.init(requestTimeout: .milliseconds(100)))
        let reply = Task { try await connection.call("ping", params: EmptyParams(), as: Echo.self) }
        _ = try await peer.readRequest()
        await #expect(throws: CoreError.timeout) { try await reply.value }
    }

    @Test func closeFailsPendingAndFinishesStreamQuietly() async throws {
        let (connection, peer) = try SocketPeer.pair()
        let notifications = connection.notifications()
        let reply = Task { try await connection.call("ping", params: EmptyParams(), as: Echo.self) }
        _ = try await peer.readRequest()
        connection.close()
        await #expect(throws: CoreError.closed) { try await reply.value }
        var count = 0
        for try await _ in notifications { count += 1 }
        #expect(count == 0)
        #expect(await peer.sawEOF())
        await #expect(throws: CoreError.closed) {
            try await connection.call("again", params: EmptyParams(), as: Echo.self)
        }
    }

    @Test func connectToMissingSocketFails() async {
        await #expect {
            _ = try await JSONRPCConnection.connect(path: "/nonexistent-herdr-test/x.sock")
        } throws: { error in
            guard case .connectFailed(let path, let reason) = error as? CoreError else { return false }
            return path == "/nonexistent-herdr-test/x.sock" && reason.contains("No such file")
        }
        await #expect(throws: CoreError.self) {
            _ = try await JSONRPCConnection.connect(path: String(repeating: "a", count: 200))
        }
    }
}
