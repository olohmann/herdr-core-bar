/// A notification-worthy change of one terminal.
public struct AgentAlert: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case blocked(BlockedKind?, message: String?)
        case done
    }

    public var kind: Kind
    public var address: String
    public var turn: Int
    public var title: String
    public var app: String
    public var group: TerminalGroup
    public var message: String?

    public init(kind: Kind, terminal: Terminal) {
        self.kind = kind
        address = terminal.address
        turn = terminal.turn
        title = terminal.displayTitle
        app = terminal.appName
        group = terminal.group
        message = terminal.status?.msg
    }

    public var word: StatusWord {
        switch kind {
        case .blocked: .blocked
        case .done: .done
        }
    }

    /// Stable per (address, turn, word); usable as a notification identifier.
    public var id: String { "\(address)#\(turn)#\(word.rawValue)" }
}

/// Decides which state changes deserve a user notification. Pure apart from its bounded dedupe memory.
///
/// Alerts fire when a live agent *enters* blocked or unread-done between two states. Pass `previous: nil` for the
/// first snapshot of a session (never alerts); after a resync (`missed`, reconnect) pass the last state you had,
/// so terminals already in that state stay quiet.
public struct NotificationPolicy: Sendable {
    public struct Kinds: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let blocked = Kinds(rawValue: 1 << 0)
        public static let done = Kinds(rawValue: 1 << 1)
        public static let all: Kinds = [.blocked, .done]
    }

    public var enabled: Kinds
    public let capacity: Int
    private var recent: [String] = []
    private var recentSet: Set<String> = []

    public init(enabled: Kinds = .all, capacity: Int = 512) {
        self.enabled = enabled
        self.capacity = max(1, capacity)
    }

    /// Alerts for terminals that entered blocked or unread-done going from `previous` to `next`.
    public mutating func alerts(from previous: TerminalState?, to next: TerminalState) -> [AgentAlert] {
        guard let previous else { return [] }
        var alerts: [AgentAlert] = []
        for terminal in next.sortedByAttention where terminal.isLive && terminal.isAgent {
            let was = previous[terminal.address].map(\.attention)
            let alert: AgentAlert
            switch terminal.attention {
            case .blocked where enabled.contains(.blocked) && was != .blocked:
                alert = AgentAlert(
                    kind: .blocked(terminal.status?.kind, message: terminal.status?.msg), terminal: terminal)
            case .doneUnread where enabled.contains(.done) && was != .doneUnread:
                alert = AgentAlert(kind: .done, terminal: terminal)
            default:
                continue
            }
            if remember(alert.id) { alerts.append(alert) }
        }
        return alerts
    }

    /// Whether an alert still applies in a later state. Herdr.app marks a turn seen shortly after the change when
    /// the user is looking at it; delaying delivery briefly and re-checking avoids notifying about what they see.
    public static func shouldDeliver(_ alert: AgentAlert, in state: TerminalState) -> Bool {
        guard let terminal = state[alert.address], terminal.isLive else { return false }
        switch alert.kind {
        case .blocked:
            guard terminal.status?.state == .blocked else { return false }
            return !(terminal.turn > alert.turn && (terminal.seenTurn ?? -1) >= terminal.turn)
        case .done:
            return terminal.isUnreadDone
        }
    }

    /// Records a key; false if it was already known.
    private mutating func remember(_ key: String) -> Bool {
        guard recentSet.insert(key).inserted else { return false }
        recent.append(key)
        if recent.count > capacity {
            recentSet.remove(recent.removeFirst())
        }
        return true
    }
}
