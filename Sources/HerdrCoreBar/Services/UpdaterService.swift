import Foundation
import Observation
import Sparkle

/// Owns Sparkle's updater. Only starts it from a proper app bundle so debug runs stay quiet.
@Observable
final class UpdaterService: NSObject {
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    private(set) var canCheckForUpdates = false
    private(set) var lastUpdateCheckDate: Date?

    var isAvailable: Bool { controller != nil }

    init(enabled: Bool = AppBundle.isProperBundle) {
        super.init()
        guard enabled else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        controller.startUpdater()
        let updater = controller.updater
        canCheckForUpdates = updater.canCheckForUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.syncFromUpdater() }
            },
            updater.observe(\.lastUpdateCheckDate, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.syncFromUpdater() }
            },
        ]
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            access(keyPath: \.automaticallyChecksForUpdates)
            return controller?.updater.automaticallyChecksForUpdates ?? false
        }
        set {
            withMutation(keyPath: \.automaticallyChecksForUpdates) {
                controller?.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    private func syncFromUpdater() {
        guard let updater = controller?.updater else { return }
        canCheckForUpdates = updater.canCheckForUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

extension UpdaterService: SPUStandardUserDriverDelegate {
    /// A menu bar app has no Dock icon to badge; let Sparkle show gentle reminders instead of stealing focus.
    var supportsGentleScheduledUpdateReminders: Bool { true }
}
