import Foundation
import HerdrCoreKit
import Observation

/// User settings, persisted in `UserDefaults`.
@Observable
final class Preferences {
    enum Key {
        static let socketPath = "socketPath"
        static let herdrAppPath = "herdrAppPath"
        static let agentsOnly = "agentsOnly"
        static let showRemote = "showRemote"
        static let showIdle = "showIdle"
        static let notifyBlocked = "notifyBlocked"
        static let notifyDone = "notifyDone"
        static let notificationSound = "notificationSound"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// herdr-core socket override; empty means auto-detect.
    var socketPath: String { didSet { defaults.set(socketPath, forKey: Key.socketPath) } }
    /// `herdr-app` executable override; empty means auto-detect.
    var herdrAppPath: String { didSet { defaults.set(herdrAppPath, forKey: Key.herdrAppPath) } }
    var agentsOnly: Bool { didSet { defaults.set(agentsOnly, forKey: Key.agentsOnly) } }
    var showRemote: Bool { didSet { defaults.set(showRemote, forKey: Key.showRemote) } }
    var showIdle: Bool { didSet { defaults.set(showIdle, forKey: Key.showIdle) } }
    var notifyBlocked: Bool { didSet { defaults.set(notifyBlocked, forKey: Key.notifyBlocked) } }
    var notifyDone: Bool { didSet { defaults.set(notifyDone, forKey: Key.notifyDone) } }
    var notificationSound: Bool { didSet { defaults.set(notificationSound, forKey: Key.notificationSound) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        socketPath = defaults.string(forKey: Key.socketPath) ?? ""
        herdrAppPath = defaults.string(forKey: Key.herdrAppPath) ?? ""
        agentsOnly = defaults.object(forKey: Key.agentsOnly) as? Bool ?? true
        showRemote = defaults.object(forKey: Key.showRemote) as? Bool ?? true
        showIdle = defaults.object(forKey: Key.showIdle) as? Bool ?? true
        notifyBlocked = defaults.object(forKey: Key.notifyBlocked) as? Bool ?? true
        notifyDone = defaults.object(forKey: Key.notifyDone) as? Bool ?? true
        notificationSound = defaults.object(forKey: Key.notificationSound) as? Bool ?? true
    }

    var sectionOptions: SectionOptions {
        SectionOptions(agentsOnly: agentsOnly, showRemote: showRemote, showIdle: showIdle)
    }

    var notificationKinds: NotificationPolicy.Kinds {
        var kinds: NotificationPolicy.Kinds = []
        if notifyBlocked { kinds.insert(.blocked) }
        if notifyDone { kinds.insert(.done) }
        return kinds
    }

    /// The socket override, trimmed; nil when auto-detecting.
    var socketOverride: String? {
        let trimmed = socketPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var herdrAppOverride: String? {
        let trimmed = herdrAppPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
