import HerdrCoreKit
import SwiftUI

/// The menu bar window: header, what needs you, everything else, footer.
struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.colorScheme) private var colorScheme

    @State private var selection: String?
    @State private var listHeight: CGFloat = 0
    @FocusState private var isFocused: Bool

    private static let chromeHeight: CGFloat = 104

    private enum Mode: Equatable {
        case connecting
        case notInstalled
        case offline(OfflineInfo)
        case empty
        case list(stale: Bool)
    }

    private var store: TerminalStore { model.store }

    private var mode: Mode {
        switch store.connection {
        case .offline(let info):
            return model.isHerdrInstalled ? .offline(info) : .notInstalled
        case .connecting:
            if !store.hasSnapshot { return model.isHerdrInstalled ? .connecting : .notInstalled }
            return model.sections.isEmpty ? .empty : .list(stale: true)
        case .live:
            return model.sections.isEmpty ? .empty : .list(stale: false)
        }
    }

    var body: some View {
        if isSnapshot {
            popover
        } else {
            popover
                .focusable()
                .focusEffectDisabled()
                .focused($isFocused)
                .onKeyPress(phases: .down, action: handleKey)
                .onAppear {
                    isFocused = true
                    selection = nil
                    model.popoverDidAppear()
                }
                .background(
                    WindowAccessor { window in
                        model.closePopover = { [weak window] in window?.close() }
                    })
        }
    }

    private var popover: some View {
        VStack(spacing: 0) {
            HeaderView(
                connection: store.connection, machines: store.machines, onReconnect: model.reconnect
            )
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            if let banner = model.banner {
                BannerView(banner: banner, onDismiss: model.dismissBanner)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider().opacity(0.6)
            content
            Divider().opacity(0.6)

            FooterView(
                unreadCount: model.unreadTerminals.count,
                agentsOnly: Bindable(model.preferences).agentsOnly,
                onMarkAllRead: { Task { await model.markAllRead() } },
                onSettings: { showSettings(.general) },
                onAbout: { showSettings(.about) },
                onCheckForUpdates: model.updater.checkForUpdates,
                canCheckForUpdates: model.updater.canCheckForUpdates
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(width: Theme.popoverWidth)
        .background {
            if isSnapshot {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.snapshotBackground(colorScheme))
            }
        }
        .backgroundStyle(isSnapshot ? AnyShapeStyle(Theme.snapshotBackground(colorScheme)) : AnyShapeStyle(.background))
        .animation(.smooth(duration: 0.25), value: model.banner)
        .animation(.smooth(duration: 0.25), value: mode)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .connecting:
            EmptyStateView(
                symbol: "antenna.radiowaves.left.and.right", title: "Connecting…",
                message: "Looking for herdr-core."
            ) {}
        case .notInstalled:
            EmptyStateView(
                symbol: "shippingbox", tint: Theme.working, title: "Herdr isn't installed",
                message: "Herdr Core Bar shows the agents running in Herdr. Install Herdr to get started."
            ) {
                if let url = AppBundle.herdrURL {
                    Link(destination: url) { Label("Get Herdr", systemImage: "arrow.down.circle") }
                        .buttonStyle(PillButtonStyle(prominent: true))
                }
                Button("Settings…") { showSettings(.connection) }
                    .buttonStyle(PillButtonStyle())
            }
        case .offline(let info):
            EmptyStateView(
                symbol: "network.slash", tint: Theme.error, title: info.title, message: info.explanation,
                detail: (info.socketPath as NSString).abbreviatingWithTildeInPath
            ) {
                Button("Retry", action: model.reconnect)
                    .buttonStyle(PillButtonStyle(prominent: true))
                Button("Open Herdr", action: model.openHerdr)
                    .buttonStyle(PillButtonStyle())
                Button("Settings…") { showSettings(.connection) }
                    .buttonStyle(PillButtonStyle())
            }
            .overlay(alignment: .bottom) {
                if !isSnapshot {
                    RetryCountdown(retryAt: info.retryAt).padding(.bottom, 8)
                }
            }
        case .empty:
            EmptyStateView(
                symbol: "moon.stars", tint: .indigo, title: "All quiet",
                message: emptyMessage
            ) {
                if !model.preferences.showIdle || !model.preferences.showRemote {
                    Button("Show Everything") {
                        model.preferences.showIdle = true
                        model.preferences.showRemote = true
                    }
                    .buttonStyle(PillButtonStyle())
                }
            }
        case .list(let stale):
            list
                .opacity(stale ? 0.55 : 1)
        }
    }

    private var emptyMessage: String {
        if !model.preferences.showIdle {
            return "No agent needs you or is working. Idle agents are hidden."
        }
        return "No agents are running. Start one in Herdr and it shows up here."
    }

    @ViewBuilder
    private var list: some View {
        let sections = model.sections
        if isSnapshot {
            listBody(sections, now: Date())
                .padding(8)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        listBody(sections, now: context.date)
                    }
                    .padding(8)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: {
                        listHeight = $0
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(max(listHeight, 44), Theme.popoverMaxHeight - Self.chromeHeight))
                .onChange(of: selection) { _, address in
                    guard let address else { return }
                    withAnimation(.smooth(duration: 0.15)) { proxy.scrollTo(address) }
                }
            }
        }
    }

    private func listBody(_ sections: TerminalSections, now: Date) -> some View {
        TerminalListView(
            sections: sections, now: now, selection: selection, openingAddress: model.openingAddress,
            onHover: { selection = $0 },
            onOpen: { terminal in Task { await model.open(terminal) } }
        )
    }

    // MARK: - Keyboard

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.command) {
            switch press.key {
            case "r":
                model.reconnect()
                return .handled
            case ",":
                showSettings(.general)
                return .handled
            default:
                return .ignored
            }
        }
        switch press.key {
        case .upArrow:
            moveSelection(by: -1)
        case .downArrow:
            moveSelection(by: 1)
        case .return:
            let ordered = model.sections.ordered
            guard let terminal = ordered.first(where: { $0.address == selection }) ?? ordered.first else {
                return .ignored
            }
            Task { await model.open(terminal) }
        case .escape:
            model.closePopover?()
        default:
            return .ignored
        }
        return .handled
    }

    private func moveSelection(by offset: Int) {
        let ordered = model.sections.ordered.map(\.address)
        guard !ordered.isEmpty else { return }
        guard let current = selection, let index = ordered.firstIndex(of: current) else {
            selection = offset > 0 ? ordered.first : ordered.last
            return
        }
        selection = ordered[min(max(index + offset, 0), ordered.count - 1)]
    }

    private func showSettings(_ tab: SettingsTab) {
        model.settingsTab = tab
        model.closePopover?()
        openSettings()
        SettingsWindow.bringToFront()
    }
}
