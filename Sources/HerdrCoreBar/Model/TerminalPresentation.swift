import Foundation
import HerdrCoreKit

/// Display strings for a terminal row and its accessibility description.
nonisolated extension Terminal {
    /// The title without a trailing " - <App>" suffix that agents like to append.
    var rowTitle: String { Self.trimmingAppSuffix(displayTitle, app: appName) }

    static func trimmingAppSuffix(_ title: String, app: String) -> String {
        let app = app.lowercased()
        guard !app.isEmpty, let separator = title.range(of: " - ", options: .backwards) else { return title }
        let suffix = title[separator.upperBound...].lowercased()
        let head = title[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
        guard suffix.contains(app), !head.isEmpty else { return title }
        return head
    }

    /// "Copilot" for `copilot`; unknown programs keep their name with a capital first letter.
    var appDisplayName: String { Self.displayName(forApp: appName) }

    static func displayName(forApp app: String) -> String {
        let known = [
            "copilot": "Copilot", "claude": "Claude", "codex": "Codex", "pi": "Pi", "gemini": "Gemini",
            "opencode": "OpenCode", "aider": "Aider", "amp": "Amp", "cursor-agent": "Cursor", "goose": "Goose",
        ]
        let trimmed = app.trimmingCharacters(in: .whitespaces)
        if let name = known[trimmed.lowercased()] { return name }
        guard let first = trimmed.first else { return "Agent" }
        return first.uppercased() + trimmed.dropFirst()
    }

    /// One or two letters for the avatar chip.
    var appInitials: String {
        let name = appDisplayName
        let letters = name.filter(\.isLetter)
        return letters.first.map { String($0).uppercased() } ?? "•"
    }

    /// What the terminal is doing, in a few words.
    var statusLine: String {
        let message = status?.msg?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        switch attention {
        case .blocked:
            let reason = Self.blockedText(status?.kind)
            return message.map { "\(reason): \($0)" } ?? reason
        case .error: return message ?? "Error"
        case .doneUnread: return message ?? "Finished"
        case .doneSeen: return message ?? "Done"
        case .working: return message ?? "Working"
        case .idle: return message ?? "Idle"
        case .plain: return foreground?.name.nonEmpty ?? (isLive ? "Shell" : "Exited")
        }
    }

    static func blockedText(_ kind: BlockedKind?) -> String {
        switch kind {
        case .permission: "Needs permission"
        case .question: "Has a question"
        case .auth: "Needs sign-in"
        case .unknown, nil: "Needs you"
        }
    }

    /// Short status word for accessibility and tooltips.
    var attentionText: String {
        switch attention {
        case .blocked: Self.blockedText(status?.kind)
        case .error: "Error"
        case .doneUnread: "Finished, unread"
        case .doneSeen: "Done"
        case .working: "Working"
        case .idle: "Idle"
        case .plain: "Shell"
        }
    }

    /// "Space / Tab", prefixed with the machine for remote terminals.
    var locationText: String {
        let title = group.title
        guard let machine else { return title }
        return title.isEmpty ? machine : "\(machine) · \(title)"
    }

    var progressFraction: Double? {
        guard let progress = status?.progress, attention == .working || attention == .blocked else { return nil }
        return min(max(Double(progress) / 100, 0), 1)
    }

    var lastChangeDate: Date? {
        let ms = lastChangeMs
        return ms > 0 ? Date(timeIntervalSince1970: TimeInterval(ms) / 1000) : nil
    }

    func accessibilityDescription(now: Date) -> String {
        var parts = [appDisplayName, rowTitle, statusLine]
        if !locationText.isEmpty { parts.append(locationText) }
        if let progress = status?.progress, progressFraction != nil { parts.append("\(progress) percent") }
        if let date = lastChangeDate { parts.append(RelativeTime.spoken(from: date, to: now)) }
        return parts.joined(separator: ", ")
    }
}

/// Compact relative times for rows: "now", "42s", "5m", "3h", "2d".
nonisolated enum RelativeTime {
    static func compact(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<10: return "now"
        case ..<60: return "\(seconds)s"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86_400)d"
        }
    }

    static func spoken(from date: Date, to now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 10 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

nonisolated extension StatusSummary {
    /// "1 blocked, 2 finished, 3 working" for VoiceOver; "No agents" when empty.
    var spokenDescription: String {
        var parts: [String] = []
        if blocked > 0 { parts.append("\(blocked) blocked") }
        if error > 0 { parts.append(error == 1 ? "1 error" : "\(error) errors") }
        if doneUnread > 0 { parts.append("\(doneUnread) finished") }
        if working > 0 { parts.append("\(working) working") }
        if parts.isEmpty { return total == 0 ? "no agents" : "\(total) idle" }
        return parts.joined(separator: ", ")
    }
}

nonisolated extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
