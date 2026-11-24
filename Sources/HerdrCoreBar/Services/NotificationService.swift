import AppKit
import Foundation
import HerdrCoreKit
import OSLog
import Observation
@preconcurrency import UserNotifications

/// Posts and withdraws user notifications and routes their actions back to the app.
@Observable
final class NotificationService: NSObject {
    enum Action: Equatable {
        case open(address: String)
        case markRead(address: String)
    }

    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// `UNUserNotificationCenter` needs a real app bundle; `swift run` has none.
    let isAvailable: Bool
    @ObservationIgnored var onAction: ((Action) -> Void)?
    @ObservationIgnored var playsSoundInForeground: () -> Bool = { true }
    @ObservationIgnored private let log = Logger(subsystem: "com.olohmann.herdr-core-bar", category: "notifications")
    @ObservationIgnored private var requested = false

    init(isAvailable: Bool = AppBundle.isProperBundle) {
        self.isAvailable = isAvailable
        super.init()
    }

    private var center: UNUserNotificationCenter? { isAvailable ? .current() : nil }

    func activate() {
        guard let center else { return }
        center.delegate = self
        let open = UNNotificationAction(
            identifier: NotificationContent.openAction, title: "Open", options: [.foreground])
        let markRead = UNNotificationAction(
            identifier: NotificationContent.markReadAction, title: "Mark as Read", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: NotificationContent.blockedCategory, actions: [open], intentIdentifiers: []),
            UNNotificationCategory(
                identifier: NotificationContent.doneCategory, actions: [open, markRead], intentIdentifiers: []),
        ])
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        guard let center else { return }
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// Asks once per launch, and only while the user hasn't decided.
    func requestAuthorizationIfNeeded() async {
        guard isAvailable, !requested else { return }
        requested = true
        await requestAuthorization()
    }

    /// Shows the system prompt if the user hasn't decided yet.
    func requestAuthorization() async {
        guard let center else { return }
        await refreshAuthorization()
        guard authorization == .notDetermined else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            log.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
        }
        await refreshAuthorization()
    }

    func post(_ content: NotificationContent) async {
        guard let center else { return }
        let payload = UNMutableNotificationContent()
        payload.title = content.title
        payload.body = content.body
        payload.threadIdentifier = content.threadIdentifier
        payload.categoryIdentifier = content.categoryIdentifier
        payload.userInfo = [NotificationContent.addressKey: content.address, NotificationContent.turnKey: content.turn]
        payload.sound = content.playsSound ? .default : nil
        payload.interruptionLevel =
            content.categoryIdentifier == NotificationContent.blockedCategory ? .timeSensitive : .active
        do {
            try await center.add(UNNotificationRequest(identifier: content.identifier, content: payload, trigger: nil))
        } catch {
            log.error("Posting notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func remove(identifiers: [String]) {
        guard let center, !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func sendTest(sound: Bool) async {
        await requestAuthorization()
        var alert = AgentAlert(
            kind: .done,
            terminal: Terminal(
                address: "test", labels: [Terminal.whereLabel: "Herdr Core Bar / Settings"],
                title: "Test notification", status: TerminalStatus(state: .done, app: "copilot", msg: "All set")))
        alert.app = "Herdr Core Bar"
        var content = NotificationContent(alert: alert, sound: sound)
        content.identifier = "test-\(UUID().uuidString)"
        await post(content)
    }

    func openSystemSettings() {
        let bundle = Bundle.main.bundleIdentifier ?? ""
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundle)")
        if let url { NSWorkspace.shared.open(url) }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let sound = await MainActor.run { playsSoundInForeground() }
        return sound ? [.banner, .list, .sound] : [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let address = info[NotificationContent.addressKey] as? String else { return }
        let actionIdentifier = response.actionIdentifier
        await MainActor.run {
            switch actionIdentifier {
            case NotificationContent.markReadAction: onAction?(.markRead(address: address))
            case NotificationContent.openAction, UNNotificationDefaultActionIdentifier:
                onAction?(.open(address: address))
            default: break
            }
        }
    }
}
