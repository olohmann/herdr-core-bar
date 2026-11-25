import AppKit
import HerdrCoreKit
import SwiftUI

/// Title, core identity and the connection pill.
struct HeaderView: View {
    let connection: ConnectionState
    let machines: [MachineView]
    var onReconnect: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            AppGlyph()
            VStack(alignment: .leading, spacing: 1) {
                Text("Herdr Core Bar")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            ConnectionPill(connection: connection, onReconnect: onReconnect)
        }
        .accessibilityElement(children: .contain)
    }

    private var subtitle: String {
        switch connection {
        case .live(let core):
            let remote = machines.count
            var parts = [core.name, "v\(core.version)"]
            if remote > 0 { parts.append(remote == 1 ? "1 remote Mac" : "\(remote) remote Macs") }
            return parts.joined(separator: " · ")
        case .connecting:
            return "Connecting to herdr-core…"
        case .offline:
            return "Not connected"
        }
    }
}

/// The app icon. Unbundled runs (`swift run`, tests) get a drawn stand-in instead of the generic icon.
struct AppGlyph: View {
    @ScaledMetric private var size: CGFloat

    init(size: CGFloat = 32) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .headline)
    }

    var body: some View {
        Group {
            if let icon = Self.bundleIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                DrawnAppIcon()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Read from the bundle rather than `NSWorkspace`, which puts `--render-preview` renders in an inactive, dimmed state.
    private static let bundleIcon: NSImage? =
        AppBundle.isProperBundle ? Bundle.main.image(forResource: "AppIcon") : nil
}

/// A simplified copy of the app icon: indigo tile, menu bar strip, three status dots.
struct DrawnAppIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            // The icon art sits inside an 80 % safe area, like macOS app icons.
            let tile = side * 0.82
            RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.20, green: 0.25, blue: 0.43), Color(red: 0.07, green: 0.08, blue: 0.16)],
                        startPoint: .top, endPoint: .bottom)
                )
                .overlay {
                    VStack(spacing: tile * 0.14) {
                        Capsule()
                            .fill(.white.opacity(0.88))
                            .frame(width: tile * 0.66, height: tile * 0.11)
                        HStack(spacing: tile * 0.05) {
                            ForEach([Theme.blocked, Theme.working, Theme.done], id: \.self) { color in
                                Circle().fill(color).frame(width: tile * 0.19, height: tile * 0.19)
                            }
                        }
                    }
                }
                .frame(width: tile, height: tile)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Live / Connecting… / Offline, with the reason as a tooltip.
struct ConnectionPill: View {
    let connection: ConnectionState
    var onReconnect: () -> Void = {}

    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onReconnect) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(color)
                    .symbolEffect(.pulse, isActive: isConnecting && !reduceMotion && !isSnapshot)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.85))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .adaptiveGlass(tint: color, snapshot: isSnapshot, interactive: true)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel("Connection: \(title)")
        .accessibilityHint(isLive ? "" : "Reconnects now")
    }

    private var isLive: Bool { connection.isLive }

    private var isConnecting: Bool {
        if case .connecting = connection { return true }
        return false
    }

    private var symbol: String { "circle.fill" }

    private var color: Color {
        switch connection {
        case .live: Theme.done
        case .connecting: .yellow
        case .offline: Theme.error
        }
    }

    private var title: String {
        switch connection {
        case .live: "Live"
        case .connecting: "Connecting…"
        case .offline: "Offline"
        }
    }

    private var help: String {
        switch connection {
        case .live(let core): "Connected to herdr-core \(core.name) (v\(core.version)). Click to reconnect."
        case .connecting(let attempt): attempt == 0 ? "Connecting…" : "Reconnecting (attempt \(attempt + 1))…"
        case .offline(let info):
            "\(info.title). \(info.detail). Retries \(info.retryAt.formatted(.relative(presentation: .named))). "
                + "Click to retry now."
        }
    }
}
