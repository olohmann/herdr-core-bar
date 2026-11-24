import Testing

@testable import HerdrCoreKit

@Suite("TerminalState")
struct TerminalStateTests {
    @Test func replaysFixtureEvents() throws {
        var state = TerminalState(snapshot: try Fixture.snapshot)
        let events = try Fixture.events()
        var accepted = 0

        for event in events.prefix(6) where state.apply(event, now: 5_000) { accepted += 1 }
        #expect(accepted == 6)
        let probe = try #require(state["t9"])
        #expect(probe.labels == ["herdr.seen": "1", "where": "Zeta / 3"])
        #expect(probe.foreground?.name == "sh")
        #expect(probe.status?.state == .blocked && probe.reported && probe.statusMs == 5_000)
        #expect(probe.turn == 2 && probe.title == "Pick a color")

        state.apply(events[6], now: 6_000)
        #expect(state["t9"]?.status == nil && state["t9"]?.statusMs == 6_000)

        state.apply(events[7], now: 7_000)
        let finished = try #require(state["t9"])
        #expect(finished.lifecycle == .finished && finished.exitCode == 3 && finished.reason == "exited")
        #expect(finished.finishedMs == 1_700_000_020_000)

        state.apply(events[8], now: 8_000)
        #expect(state["t9"] == nil)
        #expect(state.seq == 109)
    }

    @Test func staleEventsAreDropped() throws {
        var state = TerminalState(snapshot: try Fixture.snapshot)
        let before = state
        let stale = CoreEvent(seq: 100, terminal: "t1", kind: .title("old news"))
        let accepted1 = state.apply(stale, now: 1)
        #expect(!accepted1)
        #expect(state == before)
        let accepted2 = state.apply(CoreEvent(seq: 101, terminal: "t1", kind: .title("fresh")), now: 1)
        #expect(accepted2)
        let accepted3 = state.apply(CoreEvent(seq: 101, terminal: "t1", kind: .title("dup")), now: 1)
        #expect(!accepted3)
        #expect(state["t1"]?.title == "fresh")
    }

    @Test func labelsReplaceTheWholeSet() throws {
        var state = TerminalState(snapshot: try Fixture.snapshot)
        state.apply(CoreEvent(seq: 101, terminal: "t1", kind: .labels(["k": "v"])), now: 0)
        #expect(state["t1"]?.labels == ["k": "v"])
    }

    @Test func missedSnapshotResyncs() throws {
        var state = TerminalState(snapshot: try Fixture.snapshot)
        state.apply(CoreEvent(seq: 150, terminal: "t1", kind: .title("before")), now: 0)
        state.apply(snapshot: Snapshot(seq: 200, terminals: [agent("t1", .done, turn: 4)]))
        #expect(state.terminals.keys.sorted() == ["t1"])
        let accepted4 = state.apply(CoreEvent(seq: 180, terminal: "t1", kind: .title("late")), now: 0)
        #expect(!accepted4)
        let accepted5 = state.apply(CoreEvent(seq: 201, terminal: "t1", kind: .title("after")), now: 0)
        #expect(accepted5)
        #expect(state["t1"]?.title == "after")
    }

    @Test func eventsForUnknownTerminalsAdvanceSeq() {
        var state = TerminalState()
        let accepted6 = state.apply(CoreEvent(seq: 3, terminal: "t8", kind: .title("ghost")), now: 0)
        #expect(accepted6)
        #expect(state.isEmpty && state.seq == 3)
    }

    @Test func createdUsesEventAddressAndLostRestarted() {
        var state = TerminalState()
        state.apply(CoreEvent(seq: 1, terminal: "box/t2", kind: .created(Terminal(address: "t2"))), now: 0)
        #expect(state["box/t2"]?.address == "box/t2")
        state.apply(CoreEvent(seq: 2, terminal: "box/t2", kind: .lost), now: 0)
        #expect(state["box/t2"]?.isLost == true)
        state.apply(CoreEvent(seq: 3, terminal: "box/t2", kind: .restarted), now: 0)
        #expect(state["box/t2"]?.isLost == false)
        state.apply(CoreEvent(seq: 4, terminal: "box/t2", kind: .other(type: "size")), now: 0)
        #expect(state.seq == 4)
    }

    @Test func sortedNaturallyLocalFirst() {
        let state = state(
            Terminal(address: "t10"), Terminal(address: "b/t1"), Terminal(address: "t2"),
            Terminal(address: "a/t3"), Terminal(address: "t1"))
        #expect(state.sorted.map(\.address) == ["t1", "t2", "t10", "a/t3", "b/t1"])
    }

    @Test func sortedByAttention() throws {
        let state = TerminalState(snapshot: try Fixture.snapshot)
        #expect(state.sortedByAttention.map(\.address) == ["t2", "devbox/t4", "t1", "t7", "t5", "t6"])
    }
}
