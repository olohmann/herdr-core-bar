import Testing

@testable import HerdrCoreKit

@Suite("Presentation")
struct PresentationTests {
    @Test func attentionFromSnapshot() throws {
        let state = TerminalState(snapshot: try Fixture.snapshot)
        let attention = state.terminals.mapValues(\.attention)
        #expect(
            attention == [
                "t1": .working, "t2": .blocked, "devbox/t4": .doneUnread, "t5": .plain, "t6": .plain, "t7": .idle,
            ])
        #expect(state["t5"]?.isAgent == false && state["t7"]?.isAgent == true)
    }

    @Test func urgencyOrder() {
        let order: [AgentAttention] = [.blocked, .error, .doneUnread, .working, .idle, .plain]
        #expect(order == order.sorted(by: >))
        #expect(AgentAttention.idle.urgency == AgentAttention.doneSeen.urgency)
        #expect(AgentAttention.doneSeen > .plain && AgentAttention.doneSeen < .working)
    }

    @Test(
        arguments: [
            (nil, 0, true), (nil, 4, true), (3, 4, true), (4, 4, false), (9, 4, false),
        ] as [(Int?, Int, Bool)])
    func unreadDone(seen: Int?, turn: Int, unread: Bool) {
        let terminal = agent("t1", .done, turn: turn, seen: seen)
        #expect(terminal.seenTurn == seen)
        #expect(terminal.isUnreadDone == unread)
        #expect(terminal.attention == (unread ? .doneUnread : .doneSeen))
    }

    @Test func reportedWithoutStatusIsIdleAgent() {
        var terminal = Terminal(address: "t1", reported: true)
        #expect(terminal.isAgent && terminal.attention == .idle)
        terminal.labels[Terminal.seenLabel] = "not a number"
        #expect(terminal.seenTurn == nil)
    }

    @Test func displayTitleFallbacks() {
        var terminal = Terminal(address: "t1", argv: ["/usr/bin/agentx", "--flag"])
        #expect(terminal.displayTitle == "agentx")
        terminal.foreground = Foreground(name: "node")
        #expect(terminal.displayTitle == "node")
        terminal.name = "reviewer"
        #expect(terminal.displayTitle == "reviewer")
        terminal.title = "  "
        #expect(terminal.displayTitle == "reviewer")
        terminal.title = "Fix the bug"
        #expect(terminal.displayTitle == "Fix the bug")
        #expect(Terminal(address: "t9").displayTitle == "t9")
    }

    @Test func appNameFallbacks() {
        var terminal = Terminal(address: "t1", argv: ["/opt/tools/agenty"])
        #expect(terminal.appName == "agenty")
        terminal.foreground = Foreground(name: "python3")
        #expect(terminal.appName == "python3")
        terminal.status = TerminalStatus(state: .working, app: "copilot")
        #expect(terminal.appName == "copilot")
    }

    @Test func groupFromWhereLabelOrCwd() {
        var terminal = Terminal(address: "box/t1", cwd: "/home/sample/projects/alpha")
        #expect(terminal.group == TerminalGroup(space: "alpha"))
        #expect(terminal.machine == "box")
        terminal.labels["where"] = "Alpha Space / 2"
        #expect(terminal.group == TerminalGroup(space: "Alpha Space", tab: "2"))
        #expect(terminal.group.title == "Alpha Space / 2")
        terminal.labels["where"] = "Solo"
        #expect(terminal.group == TerminalGroup(space: "Solo"))
        #expect(TerminalGroup(where: "a / b / c") == TerminalGroup(space: "a / b", tab: "c"))
        #expect(Terminal(address: "t1", cwd: "/").group.space == "/")
        #expect(TerminalGroup(space: "b") > TerminalGroup(space: "a", tab: "9"))
    }

    @Test func summaryCountsLiveTerminals() throws {
        let terminals = try Fixture.snapshot.terminals
        #expect(StatusSummary(terminals) == StatusSummary(blocked: 1, doneUnread: 1, working: 1, idle: 1))
        let all = StatusSummary(terminals, agentsOnly: false)
        #expect(all == StatusSummary(blocked: 1, doneUnread: 1, working: 1, idle: 2))
        #expect(all.total == 5 && all.needsAttention == 2 && all.mostUrgent == .blocked)
        #expect(StatusSummary([agent("t1", .error)]).mostUrgent == .error)
        #expect(StatusSummary([agent("t1", .done, turn: 2, seen: 2)]) == StatusSummary(idle: 1))
        #expect(StatusSummary([Terminal]()).mostUrgent == nil)
    }
}
