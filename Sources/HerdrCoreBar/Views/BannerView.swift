import SwiftUI

/// A transient inline message, e.g. when Herdr couldn't show a terminal.
struct BannerView: View {
    let banner: Banner
    var onDismiss: () -> Void

    @Environment(\.isSnapshot) private var isSnapshot

    private var tint: Color { banner.style == .error ? Theme.error : Theme.working }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: banner.style == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(tint)
            Text(banner.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .adaptiveGlass(tint: tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous), snapshot: isSnapshot)
        .accessibilityElement(children: .combine)
    }
}
