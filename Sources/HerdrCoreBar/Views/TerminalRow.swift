import HerdrCoreKit
import SwiftUI

/// One terminal in the popover list.
struct TerminalRow: View {
    enum Context {
        /// In "Needs you": show where it lives.
        case attention
        /// Under its machine and space: show the tab.
        case grouped
    }

    let terminal: Terminal
    let context: Context
    let now: Date
    var isSelected = false
    var isBusy = false

    private var attention: AgentAttention { terminal.attention }

    private var location: String {
        switch context {
        case .attention: terminal.locationText
        case .grouped: terminal.group.tab ?? ""
        }
    }

    private var statusColor: Color {
        switch attention {
        case .blocked, .error: attention.tint
        default: .secondary
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AgentChip(terminal: terminal, isBusy: isBusy)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(terminal.rowTitle)
                        .font(
                            .body.weight(attention.urgency >= AgentAttention.doneUnread.urgency ? .semibold : .regular)
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(terminal.isAgent ? .primary : .secondary)
                    Spacer(minLength: 4)
                    if terminal.isAgent {
                        meta
                    }
                }
                subtitle
                if let fraction = terminal.progressFraction {
                    ProgressCapsule(fraction: fraction, tint: attention.tint)
                        .padding(.top, 3)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.08) : .clear)
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(terminal.accessibilityDescription(now: now))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// "Claude · 3m": which agent, and how long since its status changed.
    private var meta: some View {
        HStack(spacing: 4) {
            Text(terminal.appDisplayName)
            if let date = terminal.lastChangeDate {
                Text("·")
                Text(RelativeTime.compact(from: date, to: now))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .fixedSize()
    }

    private var subtitle: some View {
        let status = Text(terminal.statusLine).foregroundStyle(statusColor)
        let line: Text =
            location.isEmpty
            ? status
            : Text("\(status)\(Text("  ·  \(location)").foregroundStyle(.tertiary))")
        return
            line
            .font(.callout)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// A thin progress bar drawn in SwiftUI (renders in snapshots, unlike `ProgressView`).
struct ProgressCapsule: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        Capsule()
            .fill(tint.opacity(0.18))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(4, proxy.size.width * fraction))
                }
            }
            .frame(height: 4)
            .animation(.smooth, value: fraction)
            .accessibilityHidden(true)
    }
}
