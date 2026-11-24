import Foundation

/// Facts about how the app was launched.
enum AppBundle {
    static let identifier = "com.olohmann.herdr-core-bar"

    /// Running from an assembled `.app` (not `swift run` or a test host); required for Sparkle, notifications and
    /// login items.
    static var isProperBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }

    static let repositoryURL = URL(string: "https://github.com/olohmann/herdr-core-bar")
    static let herdrURL = URL(string: "https://herdr.dev")
}
