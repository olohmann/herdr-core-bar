import AppKit
import SwiftUI

struct UpdatesSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var updater = model.updater
        Form {
            Section {
                Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)
                    .disabled(!updater.isAvailable)
                LabeledContent("Last checked") {
                    if let date = updater.lastUpdateCheckDate {
                        Text(date, format: .relative(presentation: .named))
                    } else {
                        Text("Never").foregroundStyle(.secondary)
                    }
                }
                HStack {
                    if !updater.isAvailable {
                        Text("Updates are available when running the installed app.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check Now", action: updater.checkForUpdates)
                        .disabled(!updater.canCheckForUpdates)
                }
            } footer: {
                Text("Herdr Core Bar \(AppBundle.version) (\(AppBundle.build)). Updates are signed and verified.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            if AppBundle.isProperBundle {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
            } else {
                AppGlyph(size: 80).padding(8)
            }
            VStack(spacing: 4) {
                Text("Herdr Core Bar")
                    .font(.title2.weight(.semibold))
                Text("Version \(AppBundle.version) (\(AppBundle.build))")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text("Your agents at a glance, from the menu bar.")
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                if let url = AppBundle.repositoryURL {
                    Link("GitHub", destination: url)
                }
                if let url = AppBundle.herdrURL {
                    Link("herdr.dev", destination: url)
                }
            }
            Text("© 2026 Oliver Lohmann · MIT License")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
