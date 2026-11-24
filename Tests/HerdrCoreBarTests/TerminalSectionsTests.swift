import Foundation
import HerdrCoreKit
import Testing

@testable import HerdrCoreBar

@Suite struct TerminalSectionsTests {
    @Test func attentionComesFirstSortedByUrgencyThenRecency() {
        let terminals = [
            agent("t1", .done, turn: 2, seen: 1, statusMs: 500),
            agent("t2", .blocked, statusMs: 100),
            agent("t3", .error, statusMs: 900),
            agent("t4", .blocked, statusMs: 300),
            agent("t5", .working, statusMs: 999),
        ]
        let sections = TerminalSections(terminals, options: SectionOptions())
        #expect(sections.attention.map(\.address) == ["t4", "t2", "t3", "t1"])
        #expect(sections.machines.flatMap { $0.spaces.flatMap(\.terminals) }.map(\.address) == ["t5"])
    }

    @Test func groupsByMachineLocalFirstThenSpaceAlphabetically() {
        let terminals = [
            agent("zeta/t1", .working, where: "render / a"),
            agent("t2", .idle, where: "web / docs"),
            agent("alpha/t3", .idle, where: "ops / b"),
            agent("t4", .working, where: "api / tests"),
            agent("t5", .idle, where: "api / main"),
        ]
        let sections = TerminalSections(terminals, options: SectionOptions())
        #expect(sections.machines.map(\.name) == [nil, "alpha", "zeta"])
        #expect(sections.machines[0].spaces.map(\.name) == ["api", "web"])
        #expect(sections.machines[0].spaces[0].terminals.map(\.address) == ["t4", "t5"])
        #expect(sections.ordered.map(\.address) == ["t4", "t5", "t2", "alpha/t3", "zeta/t1"])
    }

    @Test func filtersShellsRemoteIdleAndFinished() {
        let terminals = [
            agent("t1", .working),
            shell("t2"),
            agent("t3", .idle),
            agent("t4", .done, turn: 3, seen: 3),
            agent("m/t5", .blocked),
            agent("t6", .working, lifecycle: .finished),
        ]
        let all = TerminalSections(terminals, options: SectionOptions(agentsOnly: false))
        #expect(Set(all.ordered.map(\.address)) == ["t1", "t2", "t3", "t4", "m/t5"])

        let defaults = TerminalSections(terminals, options: SectionOptions())
        #expect(!defaults.ordered.contains { $0.address == "t2" })

        let quiet = TerminalSections(terminals, options: SectionOptions(showRemote: false, showIdle: false))
        #expect(quiet.ordered.map(\.address) == ["t1"])
    }

    @Test func summaryHonorsRemoteFilterAndCountsAgentsOnly() {
        let terminals = [agent("t1", .blocked), agent("m/t2", .blocked), shell("t3"), agent("t4", .working)]
        let local = StatusSummary(terminals, options: SectionOptions(agentsOnly: false, showRemote: false))
        #expect(local == StatusSummary(blocked: 1, working: 1))
        #expect(local.spokenDescription == "1 blocked, 1 working")
        #expect(StatusSummary().spokenDescription == "no agents")
    }

    @Test func spacesWithoutWhereLabelUseTheWorkingDirectory() {
        let sections = TerminalSections([agent("t1", .working)], options: SectionOptions())
        #expect(sections.machines.first?.spaces.first?.name == "project")
    }
}

@Suite struct PresentationTests {
    @Test func rowTitleDropsAppSuffix() {
        let terminal = agent("t1", .working, title: "Fix login - Running tests - GitHub Copilot")
        #expect(terminal.rowTitle == "Fix login - Running tests")
        #expect(agent("t2", .working, app: "claude", title: "A - B").rowTitle == "A - B")
    }

    @Test func statusLineDescribesBlockedKinds() {
        #expect(agent("t1", .blocked, kind: .permission).statusLine == "Needs permission")
        #expect(agent("t1", .blocked, kind: .question, msg: "Which DB?").statusLine == "Has a question: Which DB?")
        #expect(agent("t1", .blocked, kind: .auth).statusLine == "Needs sign-in")
        #expect(agent("t1", .done, turn: 2, seen: 1).statusLine == "Finished")
        #expect(agent("t1", .working, msg: "Compiling").statusLine == "Compiling")
    }

    @Test func compactRelativeTime() {
        let now = Date(timeIntervalSince1970: 100_000)
        #expect(RelativeTime.compact(from: now.addingTimeInterval(-5), to: now) == "now")
        #expect(RelativeTime.compact(from: now.addingTimeInterval(-42), to: now) == "42s")
        #expect(RelativeTime.compact(from: now.addingTimeInterval(-300), to: now) == "5m")
        #expect(RelativeTime.compact(from: now.addingTimeInterval(-7_200), to: now) == "2h")
        #expect(RelativeTime.compact(from: now.addingTimeInterval(-200_000), to: now) == "2d")
    }

    @Test func menuBarLabelSpeaksCounts() {
        let summary = StatusSummary(blocked: 1, doneUnread: 2, working: 3)
        let content = MenuBarContent(summary: summary, connection: .connecting(attempt: 0))
        #expect(content == MenuBarContent(attention: 1, doneUnread: 2, working: 3))
        #expect(content.accessibilityLabel(summary: summary) == "Herdr Core Bar, 1 blocked, 2 finished, 3 working")
    }
}
