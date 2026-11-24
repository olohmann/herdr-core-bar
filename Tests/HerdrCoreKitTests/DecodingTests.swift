import Foundation
import Testing

@testable import HerdrCoreKit

@Suite("Decoding")
struct DecodingTests {
    @Test func helloIgnoresUnknownFields() throws {
        let hello = try Fixture.hello
        #expect(hello.core == CoreInfo(id: "c0ffee00", name: "examplehost"))
        #expect(hello.generation == 1)
        #expect(hello.version == "9.9.9")
        #expect(hello.methods.contains("events.subscribe"))
        #expect(hello.loginSession == LoginSession(id: 7, user: 501, gui: true))
        #expect(hello.keepsRunningAfterLogout == true)
        #expect(hello.logoutLingerUser == nil)
    }

    @Test func snapshotDecodesAllTerminals() throws {
        let snapshot = try Fixture.snapshot
        #expect(snapshot.seq == 100)
        #expect(snapshot.terminals.map(\.address) == ["t1", "t2", "devbox/t4", "t5", "t6", "t7"])

        let first = snapshot.terminals[0]
        #expect(first.status == TerminalStatus(state: .working, app: "agentx", progress: 40, msg: "thinking"))
        #expect(first.statusMs == 1_700_000_001_000)
        #expect(
            first.foreground
                == Foreground(argv: ["agentx"], cwd: "/home/sample/projects/alpha", name: "agentx", pid: 4101))
        #expect(first.labels["where"] == "Alpha / 1")
        #expect(first.turn == 3 && first.reported && first.notify && first.lifecycle == .live)

        let blocked = snapshot.terminals[1]
        #expect(blocked.status?.kind == .permission)
        #expect(blocked.foreground == nil && blocked.name == nil && blocked.records.isEmpty)

        #expect(snapshot.terminals[3].status == nil && !snapshot.terminals[3].reported)
        #expect(snapshot.terminals[4].lifecycle == .finished && snapshot.terminals[4].exitCode == 2)
    }

    @Test func unknownWordsSurvive() throws {
        let terminal = try Fixture.snapshot.terminals[5]
        #expect(terminal.status?.state == .unknown("pondering"))
        #expect(terminal.status?.kind == .unknown("telepathy"))
        #expect(terminal.title == "")

        let encoded = try JSONEncoder().encode(terminal)
        #expect(try JSONDecoder().decode(Terminal.self, from: encoded) == terminal)
    }

    @Test(arguments: ["idle", "working", "done", "blocked", "error", "pondering"])
    func statusWordRoundTrips(word: String) throws {
        let decoded = try JSONDecoder().decode(StatusWord.self, from: Data("\"\(word)\"".utf8))
        #expect(decoded.rawValue == word)
        #expect(String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self) == "\"\(word)\"")
        #expect((decoded == .unknown(word)) == (word == "pondering"))
    }

    @Test func minimalTerminalUsesDefaults() throws {
        let terminal = try JSONDecoder().decode(Terminal.self, from: Data(#"{"address":"t1"}"#.utf8))
        #expect(terminal == Terminal(address: "t1"))
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Terminal.self, from: Data("{}".utf8)) }
    }

    @Test func terminalListWithMachines() throws {
        let list = try Fixture.decode(TerminalList.self, from: "list.json")
        #expect(list.hiddenFinished == 2)
        #expect(list.terminals.map(\.address) == ["t1"])
        #expect(list.machines.map(\.name) == ["devbox", "lab"])
        #expect(list.machines[0].sinceMs == 1_700_000_000_000 && list.machines[0].state == "connected")
        #expect(list.machines[1].why == "timeout" && list.machines[1].session == nil && !list.machines[1].via)
    }

    @Test func everyEventKind() throws {
        let notifications = try Fixture.notifications("events.jsonl")
        #expect(notifications.count == 14, "unknown notification methods are skipped")
        let events = try Fixture.events()
        let kinds = events.map(\.kind)

        guard case .created(let created) = kinds[0] else { Issue.record("expected created"); return }
        #expect(created.address == "t9" && created.name == "probe" && created.status == nil)
        #expect(kinds[1] == .labels(["herdr.seen": "1", "where": "Zeta / 3"]))
        #expect(
            kinds[2]
                == .foreground(
                    Foreground(argv: ["sh", "-c", "echo hi"], cwd: "/home/sample/projects/zeta", name: "sh", pid: 5001))
        )
        #expect(
            kinds[3]
                == .status(
                    TerminalStatus(state: .blocked, app: "probe", kind: .question, msg: "which one?"), reported: true))
        #expect(kinds[4] == .turn(2, state: .blocked))
        #expect(kinds[5] == .title("Pick a color"))
        #expect(kinds[6] == .status(nil, reported: true))
        #expect(kinds[7] == .finished(exitCode: 3, reason: "exited", finishedMs: 1_700_000_020_000, signal: nil))
        #expect(kinds[8] == .removed)
        #expect(kinds[9] == .lost)
        #expect(kinds[10] == .restarted)
        #expect(kinds[11] == .other(type: "size"))
        #expect(events[12].terminal == "devbox/t4")
        #expect(notifications.last == .heartbeat(seq: 113))
        #expect(events.map(\.seq) == Array(101...113))
    }

    @Test(arguments: [
        #"{"seq":1,"terminal":"t1","type":"title","data":{}}"#,
        #"{"seq":1,"terminal":"t1","type":"turn","data":{"state":"done"}}"#,
        #"{"seq":1,"terminal":"t1","type":"labels","data":{"labels":"nope"}}"#,
        #"{"seq":1,"terminal":"t1","type":"created","data":{"argv":[]}}"#,
        #"{"terminal":"t1","type":"removed","data":{}}"#,
    ])
    func malformedKnownEventsThrow(params: String) throws {
        let line = Data(#"{"jsonrpc":"2.0","method":"event","params":\#(params)}"#.utf8)
        #expect {
            _ = try CoreNotification(Fixture.notification(line))
        } throws: { error in
            if case .invalidResponse = error as? CoreError { return true }
            return false
        }
    }

    @Test func foregroundEventMayBeEmpty() throws {
        for data in ["null", "{}"] {
            let line =
                #"{"jsonrpc":"2.0","method":"event","params":{"seq":1,"terminal":"t1","type":"foreground","data":\#(data)}}"#
            let notification = try CoreNotification(Fixture.notification(Data(line.utf8)))
            #expect(notification == .event(CoreEvent(seq: 1, terminal: "t1", kind: .foreground(nil))))
        }
    }

    @Test func missedWithAndWithoutSnapshot() throws {
        let withSnapshot = #"{"jsonrpc":"2.0","method":"missed","params":{"seq":42,"terminals":[{"address":"t1"}]}}"#
        let without = #"{"jsonrpc":"2.0","method":"missed","params":{"dropped":12}}"#
        let bare = #"{"jsonrpc":"2.0","method":"missed"}"#
        #expect(
            try CoreNotification(Fixture.notification(Data(withSnapshot.utf8)))
                == .missed(Snapshot(seq: 42, terminals: [Terminal(address: "t1")])))
        #expect(try CoreNotification(Fixture.notification(Data(without.utf8))) == .missed(nil))
        #expect(try CoreNotification(Fixture.notification(Data(bare.utf8))) == .missed(nil))
    }

    @Test(
        arguments: [
            ("192.168.10.94/t4", "192.168.10.94", "t4"),
            ("t3", nil, "t3"),
            ("hop/box/t9", "hop/box", "t9"),
            ("/t2", nil, "t2"),
        ] as [(String, String?, String)])
    func terminalAddresses(address: String, machine: String?, id: String) {
        let parsed = TerminalAddress(address)
        #expect(parsed.machine == machine && parsed.id == id)
        #expect(parsed.isLocal == (machine == nil))
    }
}
