import SwiftUI

/// Mark all read, the agents-only filter and the app menu.
struct FooterView: View {
    let unreadCount: Int
    @Binding var agentsOnly: Bool
    var onMarkAllRead: () -> Void = {}
    var onSettings: () -> Void = {}
    var onAbout: () -> Void = {}
    var onCheckForUpdates: () -> Void = {}
    var canCheckForUpdates = true

    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        HStack(spacing: 4) {
            if unreadCount > 0 {
                Button(action: onMarkAllRead) {
                    Label("Mark All Read", systemImage: "checkmark.circle")
                        .contentTransition(.numericText())
                }
                .buttonStyle(FooterButtonStyle())
                .help("Mark \(unreadCount) finished \(unreadCount == 1 ? "agent" : "agents") as read")
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
            Spacer(minLength: 8)
            Button {
                agentsOnly.toggle()
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .symbolVariant(agentsOnly ? .fill : .none)
                    .foregroundStyle(agentsOnly ? Color.accentColor : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(FooterButtonStyle(iconOnly: true))
            .help(agentsOnly ? "Showing agents only. Click to include shells." : "Showing all terminals.")
            .accessibilityLabel("Agents only")
            .accessibilityValue(agentsOnly ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
            gearMenu
        }
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder
    private var gearMenu: some View {
        let icon = Image(systemName: "gearshape").foregroundStyle(.secondary)
        if isSnapshot {
            icon.modifier(FooterButtonStyle.Chrome(iconOnly: true, isPressed: false))
        } else {
            Menu {
                Button("Settings…", action: onSettings)
                    .keyboardShortcut(",", modifiers: .command)
                Button("Check for Updates…", action: onCheckForUpdates)
                    .disabled(!canCheckForUpdates)
                Button("About Herdr Core Bar", action: onAbout)
                Divider()
                Button("Quit Herdr Core Bar") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                icon
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(FooterButtonStyle(iconOnly: true))
            .fixedSize()
            .help("Settings and more")
            .accessibilityLabel("More")
        }
    }
}

/// Quiet footer buttons with a hover highlight, drawn entirely in SwiftUI.
struct FooterButtonStyle: ButtonStyle {
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(Chrome(iconOnly: iconOnly, isPressed: configuration.isPressed))
    }

    struct Chrome: ViewModifier {
        let iconOnly: Bool
        let isPressed: Bool
        @State private var isHovered = false

        func body(content: Content) -> some View {
            content
                .font(iconOnly ? .body : .callout)
                .padding(.horizontal, iconOnly ? 6 : 8)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(isPressed ? 0.14 : isHovered ? 0.08 : 0))
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .onHover { isHovered = $0 }
        }
    }
}
