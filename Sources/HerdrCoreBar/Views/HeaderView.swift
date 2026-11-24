import HerdrCoreKit
import SwiftUI

/// Title, core identity and the connection pill.
struct HeaderView: View {
    let connection: ConnectionState
    let machines: [MachineView]
    var onReconnect: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
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

/// A small rendition of the app icon.
struct AppGlyph: View {
    @ScaledMetric private var size: CGFloat

    init(size: CGFloat = 26) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .headline)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.20, green: 0.26, blue: 0.43), Color(red: 0.07, green: 0.08, blue: 0.16)],
                    startPoint: .top, endPoint: .bottom)
            )
            .overlay {
                Image(systemName: Theme.baseSymbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
