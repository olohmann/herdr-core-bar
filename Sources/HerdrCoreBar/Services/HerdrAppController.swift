import AppKit
import Foundation
import HerdrCoreKit
import OSLog

/// Why showing a terminal in Herdr failed, phrased for the popover banner.
enum FocusError: Error, Equatable {
    case notInstalled
    case launchFailed(String)
    case herdr(String)
    case commandFailed(String)
    case timedOut

    var message: String {
        switch self {
        case .notInstalled: "Couldn't find herdr-app. Install Herdr or set its path in Settings."
        case .launchFailed(let detail): "Couldn't start Herdr: \(detail)"
        case .herdr(let detail): "Herdr: \(detail)"
        case .commandFailed(let detail): "herdr-app failed: \(detail)"
        case .timedOut: "Herdr didn't answer in time."
        }
    }
}

/// Shows a terminal to the user.
protocol TerminalFocusing: AnyObject {
    func focus(_ terminal: Terminal) async throws(FocusError)
}

/// Starts and brings Herdr.app forward; faked in tests.
protocol HerdrAppActivating {
    var isHerdrRunning: Bool { get }
    func launchHerdr() async throws(FocusError)
    func activateHerdr()
}

/// Focuses terminals in Herdr.app through `herdr-app do agent.focus`.
final class HerdrAppController: TerminalFocusing {
    static let timeout: Duration = .seconds(5)
    /// After launching Herdr.app its window takes a moment; retry this often, this far apart.
    static let launchRetries = 8
    static let launchRetryDelay: Duration = .milliseconds(500)

    private let locator: HerdrAppLocator
    private let runner: any CommandRunning
    private let activator: any HerdrAppActivating
    private let override: () -> String?
    private let sleep: (Duration) async -> Void
    private let log = Logger(subsystem: "com.olohmann.herdr-core-bar", category: "focus")

    init(
        locator: HerdrAppLocator = HerdrAppLocator(), runner: any CommandRunning = ProcessRunner(),
        activator: any HerdrAppActivating = WorkspaceHerdrActivator(), override: @escaping () -> String?,
        sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.locator = locator
        self.runner = runner
        self.activator = activator
        self.override = override
        self.sleep = sleep
    }

    static func focusArguments(for address: String) -> [String] {
        ["do", "agent.focus", "--terminal", address]
    }

    /// nil when the command succeeded. herdr-app prints `{ "error": "..." }` and exits 1 on failure.
    static func failure(in result: CommandResult) -> FocusError? {
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = output.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"], !(error is NSNull)
        {
            return .herdr(describe(error))
        }
        guard result.exitCode != 0 else { return nil }
        let detail = [result.stderr, result.stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return .commandFailed(detail ?? "exit code \(result.exitCode)")
    }

    private static func describe(_ error: Any) -> String {
        if let text = error as? String { return text }
        if let object = error as? [String: Any] {
            if let message = object["message"] as? String { return message }
            if let kind = object["kind"] as? String { return kind }
        }
        return String(describing: error)
    }

    func focus(_ terminal: Terminal) async throws(FocusError) {
        guard let tool = locator.locate(override: override()) else { throw .notInstalled }
        var attempts = 1
        if !activator.isHerdrRunning {
            log.info("Herdr is not running; launching it")
            try await activator.launchHerdr()
            attempts = Self.launchRetries
        }
        var lastError = FocusError.timedOut
        for attempt in 0..<attempts {
            if attempt > 0 { await sleep(Self.launchRetryDelay) }
            do {
                let result = try await runner.run(
                    tool, arguments: Self.focusArguments(for: terminal.address), timeout: Self.timeout)
                if let failure = Self.failure(in: result) {
                    lastError = failure
                    continue
                }
                activator.activateHerdr()
                return
            } catch {
                switch error {
                case .timedOut: lastError = .timedOut
                case .launchFailed(let detail): throw .commandFailed(detail)
                }
            }
        }
        log.error("Focus \(terminal.address, privacy: .public) failed: \(lastError.message, privacy: .public)")
        throw lastError
    }
}

/// Talks to the real Herdr.app through `NSWorkspace`.
struct WorkspaceHerdrActivator: HerdrAppActivating {
    var bundleIdentifier = HerdrAppLocator.bundleIdentifier

    private var runningApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    }

    var isHerdrRunning: Bool { runningApp != nil }

    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) }

    func launchHerdr() async throws(FocusError) {
        guard let appURL else { throw .notInstalled }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        } catch {
            throw .launchFailed(error.localizedDescription)
        }
    }

    func activateHerdr() {
        guard let app = runningApp else { return }
        NSApp.yieldActivation(to: app)
        if !app.activate(from: .current, options: []), let appURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        }
    }

    /// Opens Herdr.app (used by the offline empty state).
    func open() {
        guard let appURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }
}
