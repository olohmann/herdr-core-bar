import Foundation

/// A live `events.subscribe` stream on its own connection.
public struct CoreSubscription: Sendable {
    public let hello: HelloResult
    public let snapshot: Snapshot
    /// Notifications after the snapshot. Finishes when the connection closes; cancelling the iterating task (or
    /// `cancel()`) closes the connection.
    public let notifications: AsyncThrowingStream<CoreNotification, any Error>
    private let onCancel: @Sendable () -> Void

    public init(
        hello: HelloResult, snapshot: Snapshot, notifications: AsyncThrowingStream<CoreNotification, any Error>,
        onCancel: @escaping @Sendable () -> Void
    ) {
        self.hello = hello
        self.snapshot = snapshot
        self.notifications = notifications
        self.onCancel = onCancel
    }

    /// Closes the subscription's connection.
    public func cancel() { onCancel() }
}

/// Something that can open a subscription; `CoreClient` in the app, a fake in tests.
public protocol CoreSubscribing: Sendable {
    func subscribe() async throws(CoreError) -> CoreSubscription
}

/// Talks to one herdr-core. Each call opens its own connection and says `hello` first; `subscribe` keeps its
/// connection for the stream, everything else closes it when done.
public struct CoreClient: CoreSubscribing, Hashable {
    public var socketPath: String
    public var configuration: JSONRPCConnection.Configuration

    public init(socketPath: String, configuration: JSONRPCConnection.Configuration = .init()) {
        self.socketPath = socketPath
        self.configuration = configuration
    }

    public init(socket: URL = SocketLocator.resolve(), configuration: JSONRPCConnection.Configuration = .init()) {
        self.init(socketPath: socket.path(percentEncoded: false), configuration: configuration)
    }

    public func hello() async throws(CoreError) -> HelloResult {
        try await withConnection { connection, hello in hello }
    }

    public func subscribe() async throws(CoreError) -> CoreSubscription {
        let (connection, hello) = try await open()
        let notifications = connection.notifications { (notification) throws(CoreError) in
            try CoreNotification(notification)
        }
        do {
            let snapshot = try await connection.call("events.subscribe", params: EmptyParams(), as: Snapshot.self)
            return CoreSubscription(
                hello: hello, snapshot: snapshot, notifications: notifications, onCancel: { connection.close() })
        } catch {
            connection.close()
            throw error
        }
    }

    public func listTerminals(all: Bool = false) async throws(CoreError) -> TerminalList {
        try await withConnection { connection, _ throws(CoreError) in
            try await connection.call("terminal.list", params: ListParams(all: all), as: TerminalList.self)
        }
    }

    /// Sets labels on a terminal (`t7` or `machine/t7`); an empty value removes the label.
    @discardableResult
    public func setLabels(terminal: String, labels: [String: String]) async throws(CoreError) -> Terminal {
        try await withConnection { connection, _ throws(CoreError) in
            try await connection.call(
                "terminal.label", params: LabelParams(terminal: terminal, labels: labels), as: Terminal.self)
        }
    }

    /// Marks the terminal's current turn as seen, as Herdr.app does when the user looks at it.
    @discardableResult
    public func markSeen(_ terminal: Terminal) async throws(CoreError) -> Terminal {
        try await setLabels(terminal: terminal.address, labels: [Terminal.seenLabel: String(terminal.turn)])
    }

    private func open() async throws(CoreError) -> (JSONRPCConnection, HelloResult) {
        let connection = try await JSONRPCConnection.connect(path: socketPath, configuration: configuration)
        do throws(CoreError) {
            let hello = try await connection.call(
                "hello", params: HelloParams(generation: Int(HerdrCoreKit.protocolGeneration)), as: HelloResult.self)
            guard hello.generation == Int(HerdrCoreKit.protocolGeneration) else { throw .unsupportedGeneration }
            return (connection, hello)
        } catch {
            connection.close()
            throw error
        }
    }

    private func withConnection<T>(
        _ body: (JSONRPCConnection, HelloResult) async throws(CoreError) -> T
    ) async throws(CoreError) -> T {
        let (connection, hello) = try await open()
        defer { connection.close() }
        return try await body(connection, hello)
    }
}

private struct HelloParams: Encodable {
    var generation: Int
}

private struct ListParams: Encodable {
    var all: Bool
}

private struct LabelParams: Encodable {
    var terminal: String
    var labels: [String: String]
}
