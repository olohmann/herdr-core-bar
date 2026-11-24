import HerdrCoreKit
import SwiftUI

/// The app's initial in a tinted circle, ringed by its status color, with a badge when it needs a glance.
struct AgentChip: View {
    let terminal: Terminal
    var isBusy = false

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 30
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSnapshot) private var isSnapshot

    private var attention: AgentAttention { terminal.attention }
    private var appColor: Color { Theme.appColor(terminal.appName) }

    var body: some View {
        ZStack {
            Circle()
                .fill(appColor.gradient.opacity(terminal.isAgent ? 0.22 : 0.12))
                .padding(4)
            if terminal.isAgent {
                Text(terminal.appInitials)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(appColor)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            ring
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) { badge }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var ring: some View {
        switch attention {
        case .working:
            if isSnapshot || reduceMotion {
                arc(rotation: .degrees(-90))
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let turns = context.date.timeIntervalSinceReferenceDate / 1.6
                    arc(rotation: .degrees((turns - turns.rounded(.down)) * 360 - 90))
                }
            }
        case .blocked, .error, .doneUnread:
            Circle().strokeBorder(attention.tint, lineWidth: 2)
        case .doneSeen, .idle:
            Circle().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
        case .plain:
            Circle().strokeBorder(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        }
        if isBusy {
            Circle().fill(.background.opacity(0.6)).padding(4)
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.primary)
                .symbolEffect(.pulse, isActive: !reduceMotion)
        }
    }

    private func arc(rotation: Angle) -> some View {
        ZStack {
            Circle().strokeBorder(Theme.working.opacity(0.18), lineWidth: 2)
            Circle()
                .inset(by: 1)
                .trim(from: 0, to: 0.7)
                .stroke(Theme.working, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(rotation)
        }
    }

    @ViewBuilder
    private var badge: some View {
        if let symbol = attention.badgeSymbol {
            Image(systemName: symbol)
                .font(.system(size: size * 0.24, weight: .black))
                .foregroundStyle(.white)
                .frame(width: size * 0.42, height: size * 0.42)
                .background(Circle().fill(attention.tint))
                .background(Circle().stroke(.background, lineWidth: 2))
                .offset(x: 3, y: 3)
                .symbolEffect(.bounce, value: terminal.turn)
        }
    }
}
