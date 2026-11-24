import Foundation
import HerdrCoreKit

/// Which terminals the popover shows.
nonisolated struct SectionOptions: Hashable, Sendable {
    var agentsOnly = true
    var showRemote = true
    var showIdle = true
}

/// The popover's content: what needs the user first, then everything else by machine and space.
nonisolated struct TerminalSections: Equatable, Sendable {
    struct Space: Identifiable, Equatable {
        var id: String
        var name: String
        var terminals: [Terminal]
    }

    struct Machine: Identifiable, Equatable {
        /// `nil` for this Mac.
        var name: String?
        var spaces: [Space]

        var id: String { name ?? "" }
        var isLocal: Bool { name == nil }
        var count: Int { spaces.reduce(0) { $0 + $1.terminals.count } }
    }

    var attention: [Terminal] = []
    var machines: [Machine] = []

    var isEmpty: Bool { attention.isEmpty && machines.isEmpty }

    /// Every shown terminal in display order, for keyboard navigation.
    var ordered: [Terminal] {
        attention + machines.flatMap { $0.spaces.flatMap(\.terminals) }
    }

    init(attention: [Terminal] = [], machines: [Machine] = []) {
        self.attention = attention
        self.machines = machines
    }

    init(_ terminals: some Sequence<Terminal>, options: SectionOptions) {
        let shown = terminals.filter { Self.isShown($0, options: options) }
        attention = shown.filter(\.needsUser).sorted(by: Self.urgencyThenRecency)

        let rest = shown.filter { !$0.needsUser }
        let byMachine = Dictionary(grouping: rest, by: \.machine)
        machines = byMachine.keys
            .sorted { lhs, rhs in
                guard let lhs else { return true }
                guard let rhs else { return false }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            .map { machine in
                let bySpace = Dictionary(grouping: byMachine[machine] ?? [], by: \.group.space)
                let spaces = bySpace.keys
                    .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                    .map { space in
                        Space(
                            id: "\(machine ?? "")|\(space)",
                            name: space.isEmpty ? "Other" : space,
                            terminals: (bySpace[space] ?? []).sorted(by: Self.urgencyThenRecency))
                    }
                return Machine(name: machine, spaces: spaces)
            }
    }

    static func isShown(_ terminal: Terminal, options: SectionOptions) -> Bool {
        guard terminal.isLive else { return false }
        if options.agentsOnly, !terminal.isAgent { return false }
        if !options.showRemote, terminal.machine != nil { return false }
        if !options.showIdle, [.idle, .doneSeen, .plain].contains(terminal.attention) { return false }
        return true
    }

    /// Most urgent first, then most recently changed, then by address.
    static func urgencyThenRecency(_ lhs: Terminal, _ rhs: Terminal) -> Bool {
        let (left, right) = (lhs.attention.urgency, rhs.attention.urgency)
        if left != right { return left > right }
        let (leftTime, rightTime) = (lhs.lastChangeMs, rhs.lastChangeMs)
        if leftTime != rightTime { return leftTime > rightTime }
        return lhs.address.localizedStandardCompare(rhs.address) == .orderedAscending
    }
}

nonisolated extension Terminal {
    /// Blocked, errored or finished-and-unread: shown in "Needs you".
    var needsUser: Bool { [.blocked, .error, .doneUnread].contains(attention) }

    var lastChangeMs: Int { statusMs ?? createdMs }
}

nonisolated extension StatusSummary {
    /// Counts for the menu bar: agents only, honoring the remote filter.
    init(_ terminals: some Sequence<Terminal>, options: SectionOptions) {
        self.init(terminals.filter { options.showRemote || $0.machine == nil }, agentsOnly: true)
    }
}
