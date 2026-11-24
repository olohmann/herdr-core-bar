import Testing

@testable import HerdrCoreKit

@Suite("NotificationPolicy")
struct NotificationPolicyTests {
    @Test func initialSnapshotNeverAlerts() throws {
        var policy = NotificationPolicy()
        #expect(policy.alerts(from: nil, to: TerminalState(snapshot: try Fixture.snapshot)).isEmpty)
    }

    @Test func enteringBlockedAlertsOncePerTurn() throws {
        var policy = NotificationPolicy()
        let working = state(seq: 1, agent("t1", .working, turn: 3, seen: 3, title: "Task"))
        let blocked = state(
            seq: 2, agent("t1", .blocked, turn: 3, seen: 3, title: "Task", kind: .permission, msg: "allow write?"))

        let alerts = policy.alerts(from: working, to: blocked)
        let alert = try #require(alerts.first)
        #expect(alerts.count == 1)
        #expect(alert.kind == .blocked(.permission, message: "allow write?"))
        #expect(alert.address == "t1" && alert.turn == 3 && alert.title == "Task" && alert.id == "t1#3#blocked")

        #expect(policy.alerts(from: blocked, to: blocked).isEmpty, "staying blocked is not entering")
        #expect(policy.alerts(from: working, to: blocked).isEmpty, "flapping within one turn is deduplicated")

        let nextTurn = state(seq: 3, agent("t1", .blocked, turn: 4, seen: 3))
        #expect(policy.alerts(from: working, to: nextTurn).map(\.id) == ["t1#4#blocked"])
    }

    @Test func enteringUnreadDone() {
        var policy = NotificationPolicy()
        let working = state(agent("t1", .working, turn: 7, seen: 7))
        let doneSameTurn = state(agent("t1", .done, turn: 7, seen: 7))
        let doneNextTurn = state(agent("t1", .done, turn: 8, seen: 7))

        #expect(policy.alerts(from: working, to: doneSameTurn).isEmpty, "already seen: seen >= turn")
        let alerts = policy.alerts(from: doneSameTurn, to: doneNextTurn)
        #expect(alerts.map(\.kind) == [.done] && alerts.map(\.id) == ["t1#8#done"])
    }

    @Test func resyncDoesNotRealertExistingStates() throws {
        var policy = NotificationPolicy()
        let old = TerminalState(snapshot: try Fixture.snapshot)
        var resynced = try Fixture.snapshot
        resynced.seq = 500
        resynced.terminals.append(agent("t20", .blocked, turn: 1))
        let alerts = policy.alerts(from: old, to: TerminalState(snapshot: resynced))
        #expect(alerts.map(\.address) == ["t20"], "only the terminal that changed during the gap")
    }

    @Test func ignoresPlainAndFinishedTerminals() {
        var policy = NotificationPolicy()
        let before = state(Terminal(address: "t1"), agent("t2", .working, turn: 1))
        let after = state(
            Terminal(address: "t1"), agent("t2", .blocked, turn: 1, lifecycle: .finished))
        #expect(policy.alerts(from: before, to: after).isEmpty)
    }

    @Test func disabledKinds() {
        var policy = NotificationPolicy(enabled: .done)
        let before = state(agent("t1", .working, turn: 1), agent("t2", .working, turn: 1, seen: 1))
        let after = state(agent("t1", .blocked, turn: 1), agent("t2", .done, turn: 2, seen: 1))
        #expect(policy.alerts(from: before, to: after).map(\.address) == ["t2"])
        policy.enabled = []
        #expect(policy.alerts(from: before, to: state(agent("t3", .blocked, turn: 9))).isEmpty)
    }

    @Test func dedupeMemoryIsBounded() {
        var policy = NotificationPolicy(capacity: 2)
        let idle = state()
        for address in ["t1", "t2", "t3"] {
            #expect(policy.alerts(from: idle, to: state(agent(address, .blocked, turn: 1))).count == 1)
        }
        #expect(policy.alerts(from: idle, to: state(agent("t3", .blocked, turn: 1))).isEmpty)
        #expect(policy.alerts(from: idle, to: state(agent("t1", .blocked, turn: 1))).count == 1, "t1 was evicted")
    }

    @Test func shouldDeliverRechecksLaterState() throws {
        var policy = NotificationPolicy()
        let done = try #require(
            policy.alerts(
                from: state(agent("t1", .working, turn: 1, seen: 1)), to: state(agent("t1", .done, turn: 2, seen: 1))
            )
            .first)
        #expect(NotificationPolicy.shouldDeliver(done, in: state(agent("t1", .done, turn: 2, seen: 1))))
        #expect(!NotificationPolicy.shouldDeliver(done, in: state(agent("t1", .done, turn: 2, seen: 2))))
        #expect(!NotificationPolicy.shouldDeliver(done, in: state()))

        let blocked = try #require(
            policy.alerts(
                from: state(agent("t2", .working, turn: 4, seen: 4)), to: state(agent("t2", .blocked, turn: 4, seen: 4))
            )
            .first)
        #expect(NotificationPolicy.shouldDeliver(blocked, in: state(agent("t2", .blocked, turn: 5, seen: 4))))
        #expect(!NotificationPolicy.shouldDeliver(blocked, in: state(agent("t2", .blocked, turn: 5, seen: 5))))
        #expect(!NotificationPolicy.shouldDeliver(blocked, in: state(agent("t2", .working, turn: 5, seen: 4))))
    }
}
