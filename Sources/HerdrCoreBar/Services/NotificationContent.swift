import Foundation
import HerdrCoreKit

/// What one user notification says, independent of `UserNotifications` so it can be tested.
nonisolated struct NotificationContent: Equatable, Sendable {
    static let blockedCategory = "agent.blocked"
    static let doneCategory = "agent.done"
    static let openAction = "open"
    static let markReadAction = "mark-read"
    static let addressKey = "address"
    static let turnKey = "turn"

    var identifier: String
    var title: String
    var body: String
    var threadIdentifier: String
    var categoryIdentifier: String
    var address: String
    var turn: Int
    var playsSound: Bool

    init(alert: AgentAlert, sound: Bool) {
        let app = alert.app.isEmpty ? "An agent" : Terminal.displayName(forApp: alert.app)
        let detail: String?
        switch alert.kind {
        case .blocked(let kind, let message):
            title = "\(app) needs you"
            let reason = Terminal.blockedText(kind)
            detail = Self.clean(message).map { kind == nil ? $0 : "\(reason): \($0)" } ?? reason
            categoryIdentifier = Self.blockedCategory
        case .done:
            title = "\(app) finished"
            detail = Self.clean(alert.message)
            categoryIdentifier = Self.doneCategory
        }
        var location = alert.group.title
        if let machine = TerminalAddress(alert.address).machine {
            location = location.isEmpty ? machine : "\(machine) · \(location)"
        }
        let second = [detail, location.nonEmpty].compactMap(\.self).joined(separator: " · ")
        body = [Self.clean(Terminal.trimmingAppSuffix(alert.title, app: alert.app)), second.nonEmpty].compactMap(\.self)
            .joined(separator: "\n")
        identifier = alert.id
        threadIdentifier = "terminal:\(alert.address)"
        address = alert.address
        turn = alert.turn
        playsSound = sound
    }

    private static func clean(_ text: String?) -> String? {
        text?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }
}
