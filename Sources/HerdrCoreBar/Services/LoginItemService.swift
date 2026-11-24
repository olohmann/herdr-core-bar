import Foundation
import Observation
import ServiceManagement

/// Launch at login through `SMAppService.mainApp`.
@Observable
final class LoginItemService {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var lastError: String?
    let isAvailable: Bool

    init(isAvailable: Bool = AppBundle.isProperBundle) {
        self.isAvailable = isAvailable
        refresh()
    }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    var statusText: String {
        guard isAvailable else { return "Available when running the installed app." }
        switch status {
        case .enabled: return "Opens automatically when you log in."
        case .requiresApproval: return "Waiting for approval in System Settings › Login Items."
        case .notFound: return "macOS couldn't find this app. Move it to Applications and try again."
        case .notRegistered: return "Off"
        @unknown default: return "Unknown"
        }
    }

    func refresh() {
        guard isAvailable else { return }
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
