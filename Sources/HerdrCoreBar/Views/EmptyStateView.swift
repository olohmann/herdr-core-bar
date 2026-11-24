import SwiftUI

/// A centered icon, title, explanation and actions.
struct EmptyStateView<Actions: View>: View {
    let symbol: String
    var tint: Color = .secondary
    let title: String
    let message: String
    var detail: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
                .padding(.bottom, 2)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) { actions }
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .accessibilityElement(children: .contain)
    }
}

/// Capsule buttons for empty states; prominent ones are filled with the accent color.
struct PillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background {
                Capsule().fill(
                    prominent
                        ? AnyShapeStyle(Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1))
                        : AnyShapeStyle(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.09)))
            }
            .contentShape(Capsule())
    }
}

/// "Retrying in 5 s" that counts down by itself.
struct RetryCountdown: View {
    let retryAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = Int(retryAt.timeIntervalSince(context.date).rounded(.up))
            Text(remaining > 0 ? "Retrying in \(remaining) s" : "Retrying…")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText(countsDown: true))
        }
    }
}
