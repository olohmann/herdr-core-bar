import Foundation

/// How much a terminal needs the user, most urgent last in declaration order.
/// `idle` and `doneSeen` are equally urgent.
public enum AgentAttention: Sendable, Hashable, CaseIterable, Comparable {
    /// A plain shell (no status reported) or a terminal that is no longer live.
    case plain
    case idle
    case doneSeen
    case working
    case doneUnread
    case error
    case blocked

    public var urgency: Int {
        switch self {
        case .plain: 0
        case .idle, .doneSeen: 1
        case .working: 2
        case .doneUnread: 3
        case .error: 4
        case .blocked: 5
        }
    }

    public static func < (lhs: AgentAttention, rhs: AgentAttention) -> Bool { lhs.urgency < rhs.urgency }
}

/// Where a terminal sits in Herdr.app: from the `where` label ("Space / Tab"), else its working directory.
public struct TerminalGroup: Sendable, Hashable, Comparable {
    public var space: String
    public var tab: String?

    public init(space: String, tab: String? = nil) {
        self.space = space
        self.tab = tab
    }

    /// Parses `"Space / Tab"`; without a separator the whole string is the space.
    public init(where value: String) {
        if let separator = value.range(of: " / ", options: .backwards) {
            space = String(value[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
            let tab = String(value[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
            self.tab = tab.isEmpty ? nil : tab
        } else {
            space = value.trimmingCharacters(in: .whitespaces)
            tab = nil
        }
    }

    public var title: String { tab.map { "\(space) / \($0)" } ?? space }

    public static func < (lhs: TerminalGroup, rhs: TerminalGroup) -> Bool {
        let order = lhs.space.localizedStandardCompare(rhs.space)
        if order != .orderedSame { return order == .orderedAscending }
        return (lhs.tab ?? "").localizedStandardCompare(rhs.tab ?? "") == .orderedAscending
    }
}

extension Terminal {
    /// Turn number the user last saw, written by Herdr.app (and by us after focusing).
    public static let seenLabel = "herdr.seen"
    /// "Space / Tab" display string written by Herdr.app.
    public static let whereLabel = "where"
    public static let spaceLabel = "herdr.space"
    public static let tabLabel = "herdr.tab"

    /// A program that reports status (a coding agent), as opposed to a plain shell.
    public var isAgent: Bool { reported || status != nil }

    public var isLive: Bool { lifecycle == .live }

    public var seenTurn: Int? {
        labels[Self.seenLabel].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Done, and the user has not looked since this turn.
    public var isUnreadDone: Bool { status?.state == .done && (seenTurn ?? -1) < turn }

    public var attention: AgentAttention {
        guard isLive, isAgent else { return .plain }
        switch status?.state {
        case .blocked: return .blocked
        case .error: return .error
        case .done: return isUnreadDone ? .doneUnread : .doneSeen
        case .working: return .working
        case .idle, .unknown, nil: return .idle
        }
    }

    public var terminalAddress: TerminalAddress { TerminalAddress(address) }

    /// The machine this terminal runs on; nil for the local core.
    public var machine: String? { terminalAddress.machine }

    /// Title, else name, else foreground process, else program.
    public var displayTitle: String {
        firstNonEmpty(title, name, foreground?.name, argv.first.map(Self.basename)) ?? address
    }

    /// The agent or program: reported app, else foreground process, else program.
    public var appName: String {
        firstNonEmpty(status?.app, foreground?.name, argv.first.map(Self.basename)) ?? ""
    }

    public var group: TerminalGroup {
        if let value = labels[Self.whereLabel], !value.trimmingCharacters(in: .whitespaces).isEmpty {
            return TerminalGroup(where: value)
        }
        let directory = cwd.isEmpty ? "" : URL(filePath: cwd).lastPathComponent
        return TerminalGroup(space: directory.isEmpty ? cwd : directory)
    }

    private static func basename(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    private func firstNonEmpty(_ candidates: String?...) -> String? {
        candidates.lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

/// Counts for the menu bar icon. Only live terminals count; seen-done and unknown words count as idle.
public struct StatusSummary: Sendable, Hashable {
    public var blocked: Int
    public var error: Int
    public var doneUnread: Int
    public var working: Int
    public var idle: Int

    public init(blocked: Int = 0, error: Int = 0, doneUnread: Int = 0, working: Int = 0, idle: Int = 0) {
        self.blocked = blocked
        self.error = error
        self.doneUnread = doneUnread
        self.working = working
        self.idle = idle
    }

    /// `agentsOnly: false` also counts plain shells, as idle.
    public init(_ terminals: some Sequence<Terminal>, agentsOnly: Bool = true) {
        self.init()
        for terminal in terminals where terminal.isLive && (!agentsOnly || terminal.isAgent) {
            switch terminal.attention {
            case .blocked: blocked += 1
            case .error: error += 1
            case .doneUnread: doneUnread += 1
            case .working: working += 1
            case .idle, .doneSeen, .plain: idle += 1
            }
        }
    }

    public var total: Int { blocked + error + doneUnread + working + idle }
    public var needsAttention: Int { blocked + error + doneUnread }

    public var mostUrgent: AgentAttention? {
        if blocked > 0 { return .blocked }
        if error > 0 { return .error }
        if doneUnread > 0 { return .doneUnread }
        if working > 0 { return .working }
        if idle > 0 { return .idle }
        return nil
    }
}
