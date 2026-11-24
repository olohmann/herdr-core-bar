import HerdrCoreKit
import SwiftUI

@main
struct HerdrCoreBarApp: App {
    var body: some Scene {
        MenuBarExtra("Herdr Core Bar", systemImage: "circle.grid.2x2") {
            Text("Herdr Core Bar \(HerdrCoreKit.version)")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
