import Foundation
import Testing

@testable import HerdrCoreKit

@Suite("CoreClient", .serialized, .timeLimit(.minutes(1)))
struct CoreClientTests {
    @Test func subscribeOverRealSocket() async throws {
        let server = try UnixServer()
        let client = CoreClient(socketPath: server.path)
        async let subscription = client.subscribe()
        let peer = try #require(await server.accept())

        let hello = try await peer.readRequest()
        #expect(hello.method == "hello" && hello.params == ["generation": "1"])
        peer.respond(hello.id, result: String(decoding: try Fixture.data("hello.json"), as: UTF8.self))
        let subscribe = try await peer.readRequest()
        #expect(subscribe.method == "events.subscribe")
        peer.respond(subscribe.id, result: String(decoding: try Fixture.data("snapshot.json"), as: UTF8.self))
        for line in try Fixture.lines("events.jsonl") { peer.send(String(decoding: line, as: UTF8.self) + "\n") }

        let live = try await subscription
        #expect(live.hello.core.name == "examplehost")
        #expect(live.snapshot.terminals.count == 6)
        var received: [CoreNotification] = []
        for try await notification in live.notifications {
            received.append(notification)
            if case .heartbeat = notification { break }
        }
        #expect(received == (try Fixture.notifications("events.jsonl")))
        #expect(await peer.read(timeout: 0.2) == .silence, "still subscribed")
        live.cancel()
        #expect(await peer.sawEOF())
    }

    @Test func setLabelsUsesItsOwnConnection() async throws {
        let server = try UnixServer()
        let client = CoreClient(socketPath: server.path)
        async let labelled = client.setLabels(terminal: "devbox/t4", labels: ["herdr.seen": "8"])
        let peer = try #require(await server.accept())
        peer.respond(
            try await peer.readRequest().id, result: String(decoding: try Fixture.data("hello.json"), as: UTF8.self))
        let request = try await peer.readRequest()
        #expect(request.method == "terminal.label")
        #expect(request.params["terminal"] == "devbox/t4")
        #expect(request.params["labels"]?.contains("herdr.seen") == true)
        peer.respond(request.id, result: #"{"address":"devbox/t4","labels":{"herdr.seen":"8"}}"#)
        #expect(try await labelled.seenTurn == 8)
        #expect(await peer.sawEOF(), "short-lived connection is closed")
    }

    @Test func listTerminals() async throws {
        let server = try UnixServer()
        async let list = CoreClient(socketPath: server.path).listTerminals(all: true)
        let peer = try #require(await server.accept())
        peer.respond(
            try await peer.readRequest().id, result: String(decoding: try Fixture.data("hello.json"), as: UTF8.self))
        let request = try await peer.readRequest()
        #expect(request.method == "terminal.list" && request.params["all"] == "1")
        peer.respond(request.id, result: String(decoding: try Fixture.data("list.json"), as: UTF8.self))
        #expect(try await list.machines.count == 2)
    }

    @Test func rejectsOtherGenerations() async throws {
        let server = try UnixServer()
        let hello = Task { try await CoreClient(socketPath: server.path).hello() }
        let peer = try #require(await server.accept())
        peer.respond(
            try await peer.readRequest().id, result: #"{"core":{"id":"x","name":"y"},"generation":2,"version":"2"}"#)
        await #expect(throws: CoreError.unsupportedGeneration) { try await hello.value }
    }

    @Test func missingCoreIsConnectFailed() async {
        await #expect {
            _ = try await CoreClient(socketPath: "/nonexistent-herdr-test/core.sock").hello()
        } throws: { error in
            if case .connectFailed = error as? CoreError { return true }
            return false
        }
    }
}
