import Foundation
import HerdrCoreKit
import Synchronization
import Testing

@testable import HerdrCoreBar

private nonisolated struct FakeFileSystem: FileSystemProbing {
    var executables: Set<String> = []
    var directories: Set<String> = []
    var files: [String: [String]] = [:]

    func isExecutableFile(atPath path: String) -> Bool { executables.contains(path) }
    func directoryExists(atPath path: String) -> Bool { directories.contains(path) }
    func filesRecursively(in directory: String) -> [String] { files[directory] ?? [] }
}

@Suite struct HerdrAppLocatorTests {
    private func locator(_ fileSystem: FakeFileSystem) -> HerdrAppLocator {
        HerdrAppLocator(fileSystem: fileSystem, home: "/Users/me", appBundles: ["/Applications/Herdr.app"])
    }

    @Test func prefersValidOverrideThenUserBinThenHomebrew() {
        var fileSystem = FakeFileSystem(executables: [
            "/custom/herdr-app", "/Users/me/.local/bin/herdr-app", "/opt/homebrew/bin/herdr-app",
            "/usr/local/bin/herdr-app",
        ])
        #expect(locator(fileSystem).locate(override: "/custom/herdr-app")?.path == "/custom/herdr-app")
        #expect(locator(fileSystem).locate(override: "/missing")?.path == "/Users/me/.local/bin/herdr-app")
        fileSystem.executables.remove("/Users/me/.local/bin/herdr-app")
        #expect(locator(fileSystem).locate()?.path == "/opt/homebrew/bin/herdr-app")
        fileSystem.executables.remove("/opt/homebrew/bin/herdr-app")
        #expect(locator(fileSystem).locate()?.path == "/usr/local/bin/herdr-app")
    }

    @Test func expandsTildeInOverride() {
        let fileSystem = FakeFileSystem(executables: ["/Users/me/tools/herdr-app"])
        #expect(locator(fileSystem).locate(override: "~/tools/herdr-app")?.path == "/Users/me/tools/herdr-app")
        #expect(locator(fileSystem).validateOverride("~/tools/herdr-app") == true)
        #expect(locator(fileSystem).validateOverride("/nope") == false)
        #expect(locator(fileSystem).validateOverride("  ") == nil)
    }

    @Test func searchesInsideTheAppBundleLast() {
        let resources = "/Applications/Herdr.app/Contents/Resources"
        var fileSystem = FakeFileSystem(
            executables: ["\(resources)/bin/herdr-app", "\(resources)/deep/nested/herdr-app"],
            directories: [resources],
            files: [resources: ["\(resources)/deep/nested/herdr-app", "\(resources)/bin/herdr-app", "\(resources)/x"]])
        #expect(locator(fileSystem).locate()?.path == "\(resources)/bin/herdr-app")
        fileSystem.executables.insert("/Applications/Herdr.app/Contents/MacOS/herdr-app")
        #expect(locator(fileSystem).locate()?.path == "/Applications/Herdr.app/Contents/MacOS/herdr-app")
        fileSystem.executables.insert("/usr/local/bin/herdr-app")
        #expect(locator(fileSystem).locate()?.path == "/usr/local/bin/herdr-app")
    }

    @Test func nothingFound() {
        #expect(locator(FakeFileSystem()).locate() == nil)
    }
}

private nonisolated final class FakeRunner: CommandRunning, Sendable {
    struct Call: Equatable {
        var executable: String
        var arguments: [String]
    }

    private let state: Mutex<(calls: [Call], results: [Result<CommandResult, CommandError>])>

    init(_ results: [Result<CommandResult, CommandError>]) {
        state = Mutex(([], results))
    }

    var calls: [Call] { state.withLock { $0.calls } }

    func run(_ executable: URL, arguments: [String], timeout: Duration) async throws(CommandError) -> CommandResult {
        let next = state.withLock { state in
            state.calls.append(Call(executable: executable.path, arguments: arguments))
            return state.results.isEmpty
                ? .success(CommandResult(exitCode: 0, stdout: "{}", stderr: "")) : state.results.removeFirst()
        }
        return try next.get()
    }
}

private final class FakeActivator: HerdrAppActivating {
    var isHerdrRunning: Bool
    var launched = 0
    var activated = 0

    init(running: Bool) { isHerdrRunning = running }

    func launchHerdr() async throws(FocusError) {
        launched += 1
        isHerdrRunning = true
    }

    func activateHerdr() { activated += 1 }
}

@Suite struct HerdrAppControllerTests {
    private let tool = "/Users/me/.local/bin/herdr-app"

    private func controller(_ runner: FakeRunner, _ activator: FakeActivator) -> HerdrAppController {
        HerdrAppController(
            locator: HerdrAppLocator(
                fileSystem: FakeFileSystem(executables: [tool]), home: "/Users/me", appBundles: []),
            runner: runner, activator: activator, override: { nil }, sleep: { _ in })
    }

    private func ok(_ stdout: String = "{}") -> Result<CommandResult, CommandError> {
        .success(CommandResult(exitCode: 0, stdout: stdout, stderr: ""))
    }

    @Test func buildsTheFocusCommand() async throws {
        let runner = FakeRunner([ok()])
        let activator = FakeActivator(running: true)
        try await controller(runner, activator).focus(agent("mini/t7", .done))
        #expect(runner.calls == [.init(executable: tool, arguments: ["do", "agent.focus", "--terminal", "mini/t7"])])
        #expect(activator.activated == 1)
        #expect(activator.launched == 0)
    }

    @Test func parsesErrors() {
        let error = CommandResult(exitCode: 1, stdout: #"{ "error": "no agent t9" }"#, stderr: "")
        #expect(HerdrAppController.failure(in: error) == .herdr("no agent t9"))
        let nested = CommandResult(exitCode: 1, stdout: #"{"error":{"message":"window closed"}}"#, stderr: "")
        #expect(HerdrAppController.failure(in: nested) == .herdr("window closed"))
        let plain = CommandResult(exitCode: 2, stdout: "", stderr: "boom\n")
        #expect(HerdrAppController.failure(in: plain) == .commandFailed("boom"))
        let silent = CommandResult(exitCode: 3, stdout: "", stderr: "")
        #expect(HerdrAppController.failure(in: silent) == .commandFailed("exit code 3"))
        #expect(HerdrAppController.failure(in: CommandResult(exitCode: 0, stdout: "{}", stderr: "")) == nil)
        #expect(
            HerdrAppController.failure(in: CommandResult(exitCode: 0, stdout: #"{"error":null}"#, stderr: "")) == nil)
    }

    @Test func surfacesHerdrErrorWithoutRetryWhenRunning() async {
        let runner = FakeRunner([
            .success(CommandResult(exitCode: 1, stdout: #"{"error":"unknown terminal"}"#, stderr: ""))
        ])
        let activator = FakeActivator(running: true)
        await #expect(throws: FocusError.herdr("unknown terminal")) {
            try await controller(runner, activator).focus(agent("t1", .working))
        }
        #expect(runner.calls.count == 1)
        #expect(activator.activated == 0)
    }

    @Test func launchesHerdrAndRetriesUntilTheWindowIsUp() async throws {
        let notReady = Result<CommandResult, CommandError>.success(
            CommandResult(exitCode: 1, stdout: #"{"error":"no window"}"#, stderr: ""))
        let runner = FakeRunner([notReady, .failure(.timedOut), ok()])
        let activator = FakeActivator(running: false)
        try await controller(runner, activator).focus(agent("t1", .working))
        #expect(activator.launched == 1)
        #expect(runner.calls.count == 3)
        #expect(activator.activated == 1)
    }

    @Test func missingToolIsReported() async {
        let controller = HerdrAppController(
            locator: HerdrAppLocator(fileSystem: FakeFileSystem(), home: "/Users/me", appBundles: []),
            runner: FakeRunner([]), activator: FakeActivator(running: true), override: { nil }, sleep: { _ in })
        await #expect(throws: FocusError.notInstalled) { try await controller.focus(agent("t1", .working)) }
    }
}
