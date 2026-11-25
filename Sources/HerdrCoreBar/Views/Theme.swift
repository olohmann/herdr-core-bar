import HerdrCoreKit
import SwiftUI

extension EnvironmentValues {
    /// True while rendering with `ImageRenderer`: no materials, scroll views or AppKit-backed controls.
    @Entry var isSnapshot = false
}

/// Shared spacing and colors.
enum Theme {
    static let popoverWidth: CGFloat = 380
    static let popoverMaxHeight: CGFloat = 560
    static let rowCorner: CGFloat = 8

    static let blocked = Color.orange
    static let error = Color.red
    static let done = Color.green
    static let working = Color.blue

    /// Solid stand-in for the window's glass material in snapshots.
    static func snapshotBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.13, green: 0.13, blue: 0.15) : Color(red: 0.965, green: 0.965, blue: 0.975)
    }

    static func appColor(_ app: String) -> Color {
        switch app.lowercased() {
        case "copilot": return Color(red: 0.42, green: 0.36, blue: 0.95)
        case "claude": return Color(red: 0.85, green: 0.47, blue: 0.34)
        case "codex": return Color(red: 0.16, green: 0.62, blue: 0.56)
        case "pi": return Color(red: 0.20, green: 0.55, blue: 0.85)
        case "gemini": return Color(red: 0.26, green: 0.52, blue: 0.96)
        default:
            let palette: [Color] = [.purple, .pink, .teal, .indigo, .mint, .cyan, .brown]
            let hash = app.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
            return palette[hash % palette.count]
        }
    }
}

extension AgentAttention {
    var tint: Color {
        switch self {
        case .blocked: Theme.blocked
        case .error: Theme.error
        case .doneUnread: Theme.done
        case .working: Theme.working
        case .doneSeen, .idle, .plain: Color.secondary
        }
    }

    /// Small badge on the avatar for states that need a glance.
    var badgeSymbol: String? {
        switch self {
        case .blocked: "exclamationmark"
        case .error: "xmark"
        case .doneUnread: "checkmark"
        case .working, .doneSeen, .idle, .plain: nil
        }
    }
}

extension View {
    /// Liquid Glass in the live UI, a flat tinted fill in snapshots (which can't render materials).
    @ViewBuilder
    func adaptiveGlass(tint: Color? = nil, in shape: some Shape = Capsule(), snapshot: Bool, interactive: Bool = false)
        -> some View
    {
        if snapshot {
            background(shape.fill((tint ?? Color.primary).opacity(tint == nil ? 0.07 : 0.16)))
        } else {
            glassEffect(
                interactive
                    ? Glass.regular.tint(tint?.opacity(0.25)).interactive() : Glass.regular.tint(tint?.opacity(0.25)),
                in: shape)
        }
    }
}
