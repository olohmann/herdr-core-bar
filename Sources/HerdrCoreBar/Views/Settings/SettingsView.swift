import ServiceManagement
import SwiftUI
import UserNotifications

/// The Settings window.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            Tab("General", systemImage: "gearshape", value: SettingsTab.general) {
                GeneralSettingsView()
            }
            Tab("Notifications", systemImage: "bell.badge", value: SettingsTab.notifications) {
                NotificationSettingsView()
            }
            Tab("Connection", systemImage: "point.3.connected.trianglepath.dotted", value: SettingsTab.connection) {
                ConnectionSettingsView()
            }
            Tab("Updates", systemImage: "arrow.triangle.2.circlepath", value: SettingsTab.updates) {
                UpdatesSettingsView()
            }
            Tab("About", systemImage: "info.circle", value: SettingsTab.about) {
                AboutSettingsView()
            }
        }
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences
        let loginItem = model.loginItem
        Form {
            Section {
                Toggle(
                    "Open at login",
                    isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })
                )
                .disabled(!loginItem.isAvailable)
                LabeledContent("Status") {
                    Text(loginItem.statusText).foregroundStyle(.secondary)
                }
                if loginItem.status == .requiresApproval {
                    Button("Open Login Items Settings…", action: loginItem.openSystemSettings)
                }
                if let error = loginItem.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.blocked)
                }
            }
            Section("Show") {
                Toggle("Agents only", isOn: $preferences.agentsOnly)
                Text("Hide plain shells that don't report a status.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Remote machines", isOn: $preferences.showRemote)
                Toggle("Idle agents", isOn: $preferences.showIdle)
                Text("Agents that need you always show, whatever these say.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
    }
}

struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var sentTest = false

    var body: some View {
        @Bindable var preferences = model.preferences
        let notifications = model.notifications
        Form {
            Section {
                LabeledContent("Permission") {
                    HStack(spacing: 6) {
                        Image(systemName: authorizationSymbol)
                            .foregroundStyle(authorizationColor)
                        Text(authorizationText)
                    }
                }
                if notifications.authorization == .denied {
                    Button("Open Notification Settings…", action: notifications.openSystemSettings)
                } else if notifications.authorization == .notDetermined, notifications.isAvailable {
                    Button("Allow Notifications…") {
                        Task { await notifications.requestAuthorization() }
                    }
                }
            }
            Section("Notify me when an agent") {
                Toggle("Needs me (permission, question, sign-in)", isOn: $preferences.notifyBlocked)
                Toggle("Finishes a turn", isOn: $preferences.notifyDone)
                Toggle("Play sound", isOn: $preferences.notificationSound)
            }
            Section {
                HStack {
                    Button("Send Test Notification") {
                        Task {
                            await notifications.sendTest(sound: preferences.notificationSound)
                            sentTest = true
                        }
                    }
                    .disabled(!notifications.isAvailable || notifications.authorization == .denied)
                    if sentTest {
                        Text("Sent").foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Notifications wait a moment and stay quiet if you already looked at the agent in Herdr.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await notifications.refreshAuthorization() }
    }

    private var authorizationText: String {
        guard model.notifications.isAvailable else { return "Unavailable outside the app bundle" }
        switch model.notifications.authorization {
        case .authorized: return "Allowed"
        case .provisional: return "Delivered quietly"
        case .denied: return "Denied in System Settings"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Unknown"
        }
    }

    private var authorizationSymbol: String {
        switch model.notifications.authorization {
        case .authorized, .provisional: "checkmark.circle.fill"
        case .denied: "xmark.circle.fill"
        default: "questionmark.circle"
        }
    }

    private var authorizationColor: Color {
        switch model.notifications.authorization {
        case .authorized, .provisional: Theme.done
        case .denied: Theme.error
        default: .secondary
        }
    }
}
