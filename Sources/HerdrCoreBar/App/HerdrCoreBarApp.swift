import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        let options = LaunchOptions(arguments: CommandLine.arguments)
        if let directory = options.renderDirectory {
            do {
                let written = try PreviewRenderer.renderAll(to: directory)
                for url in written { print(url.path(percentEncoded: false)) }
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
                exit(1)
            }
        }
        if !options.preview, SingleInstance.activateOtherInstance() { exit(0) }
        AppContainer.model = options.preview ? AppModel.preview() : AppModel.live()
        AppContainer.options = options
        HerdrCoreBarApp.main()
    }
}

/// Holds the model the `App` and its delegate share.
enum AppContainer {
    static var model: AppModel?
    static var options = LaunchOptions()
}

struct HerdrCoreBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppContainer.model ?? AppModel.live()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…", action: model.updater.checkForUpdates)
                    .disabled(!model.updater.canCheckForUpdates)
            }
            CommandGroup(replacing: .newItem) {
                Button("Reconnect", action: model.reconnect)
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let model = AppContainer.model else { return }
        model.start()
        #if DEBUG
            if let address = AppContainer.options.debugFocusAddress {
                Task { await model.debugFocus(address) }
            }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppContainer.model?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Keeps one copy of the app running.
enum SingleInstance {
    /// Activates another running instance with our bundle identifier; true if one exists.
    static func activateOtherInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier, AppBundle.isProperBundle else { return false }
        let current = ProcessInfo.processInfo.processIdentifier
        guard
            let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { $0.processIdentifier != current })
        else { return false }
        other.activate()
        return true
    }
}
