import Foundation
import Testing

@testable import HerdrCoreKit

/// Runs against the scratch core only when `HCBAR_SCRATCH_SOCKET` is set. Starts a short-lived terminal there with
/// `hc` (scratch environment, `--rm`) and expects to see it created.
@Suite("Scratch core integration", .timeLimit(.minutes(1)))
struct IntegrationTests {
    static let socket = ProcessInfo.processInfo.environment["HCBAR_SCRATCH_SOCKET"]

    @Test(.enabled(if: socket != nil, "set HCBAR_SCRATCH_SOCKET to the scratch core socket"))
    func helloSubscribeAndSeeCreated() async throws {
        let client = CoreClient(socketPath: try #require(Self.socket))
        let hello = try await client.hello()
        #expect(hello.generation == 1)

        let subscription = try await client.subscribe()
        defer { subscription.cancel() }
        let name = "hck-\(String(UInt32.random(in: .min ... .max), radix: 36))"
        try startTerminal(named: name)

        let watchdog = Task {
            try await Task.sleep(for: .seconds(20))
            subscription.cancel()
        }
        defer { watchdog.cancel() }
        var state = TerminalState(snapshot: subscription.snapshot)
        var created: Terminal?
        for try await notification in subscription.notifications {
            guard case .event(let event) = notification else { continue }
            state.apply(event, now: 0)
            if case .created(let terminal) = event.kind, terminal.name == name {
                created = terminal
                break
            }
        }
        let terminal = try #require(created)
        #expect(terminal.lifecycle == .live && terminal.argv.first == "sh")
        #expect(state[terminal.address] != nil)
    }

    private func startTerminal(named name: String) throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let hc = ProcessInfo.processInfo.environment["HCBAR_HC"] ?? home.appending(path: ".local/bin/hc").path
        var environment = ProcessInfo.processInfo.environment
        for key in ["HC_TERMINAL_ID", "HC_TERMINAL_SOCKET", "HC_SCOPE", "HC_SOCKET"] { environment[key] = nil }
        environment.merge(
            [
                "HC_SESSION": "hcbarprobe", "XDG_STATE_HOME": "/tmp/hcbar/state",
                "XDG_CONFIG_HOME": "/tmp/hcbar/config", "XDG_DATA_HOME": "/tmp/hcbar/data",
                "XDG_RUNTIME_DIR": "/tmp/hcbar/run",
            ], uniquingKeysWith: { _, scratch in scratch })
        let process = Process()
        process.executableURL = URL(filePath: hc)
        process.arguments = [
            "run", "--bg", "--rm", "--no-parent", "--name", name, "--",
            "sh", "-c", #"printf '\033]7501;state=working\007'; sleep 2"#,
        ]
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
    }
}
