import AppKit
import HerdrCoreKit
import SwiftUI

/// What the menu bar item shows; equal values render the same image.
struct MenuBarContent: Hashable {
    var attention: Int
    var doneUnread: Int
    var working: Int
    var isOffline: Bool

    init(attention: Int = 0, doneUnread: Int = 0, working: Int = 0, isOffline: Bool = false) {
        self.attention = attention
        self.doneUnread = doneUnread
        self.working = working
        self.isOffline = isOffline
    }

    init(summary: StatusSummary, connection: ConnectionState) {
        if case .offline = connection {
            self.init(isOffline: true)
        } else {
            self.init(
                attention: summary.blocked + summary.error, doneUnread: summary.doneUnread, working: summary.working)
        }
    }

    func accessibilityLabel(summary: StatusSummary) -> String {
        isOffline ? "Herdr Core Bar, offline" : "Herdr Core Bar, \(summary.spokenDescription)"
    }
}

/// The glyph and counts, drawn in one color so it can become a template image.
struct MenuBarGlyph: View {
    let content: MenuBarContent

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                BrandMark()
                    .opacity(content.isOffline ? 0.4 : 1)
                if content.isOffline {
                    Capsule()
                        .frame(width: 4.5, height: 21)
                        .rotationEffect(.degrees(-45))
                        .blendMode(.destinationOut)
                    Capsule()
                        .frame(width: 1.75, height: 19)
                        .rotationEffect(.degrees(-45))
                }
            }
            .compositingGroup()
            if content.attention > 0 {
                group("exclamationmark.circle.fill", content.attention, weight: .bold)
            }
            if content.doneUnread > 0 {
                group("checkmark.circle", content.doneUnread, weight: .semibold)
            }
            if content.working > 0 {
                group("progress.indicator", content.working, weight: .medium)
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 1)
        .frame(height: 18)
        .fixedSize()
    }

    private func group(_ symbol: String, _ count: Int, weight: Font.Weight) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: weight))
            Text(count, format: .number)
                .font(.system(size: 13, weight: weight))
                .monospacedDigit()
        }
    }
}

/// The app icon's motif in one color: the menu bar strip above three status dots.
struct BrandMark: View {
    var body: some View {
        VStack(spacing: 3) {
            Capsule()
                .frame(width: 16, height: 3)
            HStack(spacing: 1.5) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().frame(width: 4.5, height: 4.5)
                }
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// Renders `MenuBarGlyph` into crisp template images, cached per content.
final class MenuBarIconRenderer {
    static let shared = MenuBarIconRenderer()

    private var cache: [MenuBarContent: NSImage] = [:]

    func image(for content: MenuBarContent) -> NSImage {
        if let cached = cache[content] { return cached }
        let image = Self.render(content)
        if cache.count > 64 { cache.removeAll() }
        cache[content] = image
        return image
    }

    static func render(_ content: MenuBarContent) -> NSImage {
        let renderer = ImageRenderer(content: MenuBarGlyph(content: content))
        let image = NSImage()
        var pointSize = CGSize(width: 18, height: 18)
        for scale in [2.0, 1.0, 3.0] {
            renderer.scale = scale
            guard let cgImage = renderer.cgImage else { continue }
            pointSize = CGSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
            let rep = NSBitmapImageRep(cgImage: cgImage)
            rep.size = pointSize
            image.addRepresentation(rep)
        }
        image.size = pointSize
        image.isTemplate = true
        return image
    }
}

/// The status item's label: a template image that the menu bar tints.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let summary = model.summary
        let content = MenuBarContent(summary: summary, connection: model.store.connection)
        Image(nsImage: MenuBarIconRenderer.shared.image(for: content))
            .accessibilityLabel(content.accessibilityLabel(summary: summary))
    }
}
