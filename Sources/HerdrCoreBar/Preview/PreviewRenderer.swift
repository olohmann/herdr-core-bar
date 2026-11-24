import AppKit
import HerdrCoreKit
import SwiftUI

/// `--render-preview <dir>`: writes PNG screenshots of the popover and menu bar item from preview data.
enum PreviewRenderer {
    enum RenderError: Error, CustomStringConvertible {
        case renderFailed(String)
        case encodeFailed(String)

        var description: String {
            switch self {
            case .renderFailed(let name): "could not render \(name)"
            case .encodeFailed(let name): "could not encode \(name)"
            }
        }
    }

    static let scale: CGFloat = 2

    @discardableResult
    static func renderAll(to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date()
        let offline = CoreError.connectFailed(
            path: "~/.local/state/herdr-core/default/default.sock", reason: "No such file or directory")
        let popovers: [(String, ColorScheme, (TerminalStore) -> Void)] = [
            ("popover-light.png", .light, { live($0, PreviewData.state(now: now)) }),
            ("popover-dark.png", .dark, { live($0, PreviewData.state(now: now)) }),
            ("popover-offline.png", .light, { $0.handle(.offline(offline, retryIn: .seconds(8))) }),
            ("popover-empty.png", .dark, { live($0, PreviewData.emptyState) }),
        ]
        var written: [URL] = []
        for (name, scheme, setup) in popovers {
            let model = makeModel()
            setup(model.store)
            let view = PopoverView()
                .environment(model)
                .environment(\.isSnapshot, true)
                .environment(\.colorScheme, scheme)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.18 : 0.08), lineWidth: 1)
                }
                .environment(\.colorScheme, scheme)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
                .padding(32)
            written.append(try write(view, to: directory.appending(path: name)))
        }

        let summary = StatusSummary(PreviewData.terminals(now: now), agentsOnly: true)
        let busy = MenuBarContent(summary: summary, connection: .live(CoreSummary(PreviewData.hello)))
        for (name, scheme) in [("menubar-light.png", ColorScheme.light), ("menubar-dark.png", .dark)] {
            let view = MenuBarStrip(items: [busy, MenuBarContent(), MenuBarContent(isOffline: true)], scheme: scheme)
            written.append(try write(view, to: directory.appending(path: name)))
        }
        written += try renderSettings(to: directory)
        return written
    }

    /// Settings use AppKit-backed controls, which `ImageRenderer` can't draw; snapshot a hosting view instead.
    private static func renderSettings(to directory: URL) throws -> [URL] {
        _ = NSApplication.shared
        let model = makeModel()
        live(model.store, PreviewData.state())
        var written: [URL] = []
        for tab in SettingsTab.allCases {
            model.settingsTab = tab
            let host = NSHostingView(rootView: SettingsView().environment(model))
            let window = NSWindow(
                contentRect: CGRect(x: -10_000, y: -10_000, width: 540, height: 400), styleMask: [.titled],
                backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            let size = host.fittingSize
            window.setContentSize(size)
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                throw RenderError.renderFailed(tab.rawValue)
            }
            host.cacheDisplay(in: host.bounds, to: rep)
            let url = directory.appending(path: "settings-\(tab.rawValue).png")
            guard let data = rep.representation(using: .png, properties: [:]) else {
                throw RenderError.encodeFailed(url.lastPathComponent)
            }
            try data.write(to: url)
            written.append(url)
        }
        return written
    }

    private static func live(_ store: TerminalStore, _ state: TerminalState) {
        store.handle(.live(PreviewData.hello, state))
        store.replaceMachines(PreviewData.machines)
    }

    private static func makeModel() -> AppModel {
        let suite = "\(AppBundle.identifier).render"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        return AppModel(
            preferences: Preferences(defaults: defaults), backend: PreviewCore(), focuser: PreviewFocuser(),
            notifications: NotificationService(isAvailable: false), updater: UpdaterService(enabled: false),
            loginItem: LoginItemService(isAvailable: false), isPreview: true)
    }

    private static func write(_ view: some View, to url: URL) throws -> URL {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage else { throw RenderError.renderFailed(url.lastPathComponent) }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw RenderError.encodeFailed(url.lastPathComponent)
        }
        try data.write(to: url)
        return url
    }
}

/// A slice of menu bar with a few states of the item side by side.
private struct MenuBarStrip: View {
    let items: [MenuBarContent]
    let scheme: ColorScheme

    var body: some View {
        HStack(spacing: 22) {
            ForEach(items, id: \.self) { item in
                Image(nsImage: MenuBarIconRenderer.render(item))
                    .renderingMode(.template)
                    .foregroundStyle(scheme == .dark ? Color.white : Color.black.opacity(0.85))
            }
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text("Tue 9:41").monospacedDigit()
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(scheme == .dark ? Color.white : Color.black.opacity(0.85))
        .padding(.horizontal, 16)
        .frame(height: 24)
        .background(scheme == .dark ? Color(white: 0.14) : Color(white: 0.93))
        .environment(\.colorScheme, scheme)
    }
}
