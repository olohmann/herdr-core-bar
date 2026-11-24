import AppKit
import SwiftUI

/// Hands out the hosting `NSWindow` once the view is in one.
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> AccessorView {
        let view = AccessorView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: AccessorView, context: Context) {
        view.onWindow = onWindow
    }

    final class AccessorView: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }
    }
}

/// Opening Settings from an accessory (menu bar only) app needs an explicit activation to come to the front.
enum SettingsWindow {
    static func bringToFront() {
        NSApp.activate()
        Task {
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(50))
                if let window = NSApp.windows.first(where: isSettingsWindow) {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                    return
                }
            }
        }
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.localizedCaseInsensitiveContains("settings") == true && window.isVisible
    }
}
