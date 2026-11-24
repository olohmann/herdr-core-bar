import Foundation
import HerdrCoreKit
import Synchronization
import Testing

@testable import HerdrCoreBar

private nonisolated final class ScriptedBackend: CoreBackend, CoreCommanding, Sendable {
    let marked = Mutex<[String]>([])

    func updates(socket: URL) -> AsyncStream<SessionUpdate> { AsyncStream { _ in } }
    func commands(socket: URL) -> any CoreCommanding { self }
    func markRead(_ terminal: Terminal) async throws(CoreError) { marked.withLock { $0.append(terminal.address) } }
    func fetchTerminalList() async throws(CoreError) -> TerminalList { TerminalList(terminals: []) }
}

@Suite struct TerminalStoreTests {
    private let hello = HelloResult(core: CoreInfo(id: "c1", name: "default"), version: "0.1.22")

    @Test func reportsPreviousStateForNotificationPolicy() {
        let store = TerminalStore(backend: ScriptedBackend(), socketURL: URL(filePath: "/tmp/a.sock"))
        var changes: [(TerminalState?, TerminalState)] = []
        store.onStateChange = { changes.append(($0, $1)) }

        let first = state(agent("t1", .working))
        let second = state(agent("t1", .blocked))
        store.handle(.live(hello, first))
        store.handle(.state(second))
        store.handle(.offline(.closed, retryIn: .seconds(1)))
        store.handle(.connecting(attempt: 1))
        store.handle(.live(hello, second))

        #expect(changes.count == 3)
        #expect(changes[0].0 == nil)
        #expect(changes[1].0 == first)
        #expect(changes[2].0 == second)
        #expect(store.connection == .live(CoreSummary(hello)))
    }

    @Test func offlineCarriesReasonAndRetryTime() {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = TerminalStore(backend: ScriptedBackend(), socketURL: URL(filePath: "/tmp/a.sock"), now: { now })
        store.handle(
            .offline(.connectFailed(path: "/tmp/a.sock", reason: "No such file or directory"), retryIn: .seconds(4)))
        guard case .offline(let info) = store.connection else {
            Issue.record("expected offline")
            return
        }
        #expect(info.reason == .notRunning)
        #expect(info.retryAt == now.addingTimeInterval(4))
        #expect(info.socketPath == "/tmp/a.sock")
    }

    @Test func socketChangeForgetsState() {
        let store = TerminalStore(backend: ScriptedBackend(), socketURL: URL(filePath: "/tmp/a.sock"))
        var previous: [TerminalState?] = []
        store.onStateChange = { old, _ in previous.append(old) }
        store.handle(.live(hello, state(agent("t1", .working))))
        store.restart(socket: URL(filePath: "/tmp/b.sock"))
        #expect(store.state.isEmpty)
        #expect(!store.hasSnapshot)
        store.handle(.live(hello, state(agent("t2", .blocked))))
        #expect(previous == [nil, nil])
        store.stop()
    }

    @Test func markAllReadMarksOnlyShownUnreadTerminals() async {
        let backend = ScriptedBackend()
        let model = AppModel(
            preferences: Preferences(defaults: makeDefaults()), backend: backend, focuser: PreviewFocuser(),
            notifications: NotificationService(isAvailable: false), updater: UpdaterService(enabled: false),
            loginItem: LoginItemService(isAvailable: false), isPreview: true)
        model.preferences.showRemote = false
        model.store.handle(
            .live(
                hello,
                state(
                    agent("t1", .done, turn: 3, seen: 2), agent("t2", .done, turn: 3, seen: 3),
                    agent("m/t3", .done, turn: 1), agent("t4", .working))))
        await model.markAllRead()
        #expect(backend.marked.withLock { $0 } == ["t1"])
    }
}
