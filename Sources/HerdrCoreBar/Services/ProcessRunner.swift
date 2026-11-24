import Foundation
import Synchronization

nonisolated struct CommandResult: Sendable, Hashable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

nonisolated enum CommandError: Error, Sendable, Hashable {
    case launchFailed(String)
    case timedOut
}

/// Runs a program and collects its output; injectable for tests.
nonisolated protocol CommandRunning: Sendable {
    func run(_ executable: URL, arguments: [String], timeout: Duration) async throws(CommandError) -> CommandResult
}

/// Runs commands with `Process`, terminating them after the timeout.
nonisolated struct ProcessRunner: CommandRunning {
    func run(_ executable: URL, arguments: [String], timeout: Duration) async throws(CommandError) -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let collected = OutputCollector()
        stdout.fileHandleForReading.readabilityHandler = { handle in collected.append(handle.availableData, err: false)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in collected.append(handle.availableData, err: true) }

        let timedOut = Atomic<Bool>(false)
        let status: Int32
        do {
            status = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Int32, any Error>) in
                process.terminationHandler = { finished in continuation.resume(returning: finished.terminationStatus) }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                    return
                }
                let pid = process.processIdentifier
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout.timeInterval) {
                    guard process.isRunning, process.processIdentifier == pid else { return }
                    timedOut.store(true, ordering: .sequentiallyConsistent)
                    process.terminate()
                }
            }
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw .launchFailed(error.localizedDescription)
        }
        // Output may still be in flight; a child that inherited the pipes could keep them open, so wait only briefly.
        for _ in 0..<50 where !collected.reachedEnd {
            try? await Task.sleep(for: .milliseconds(10))
        }
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        if timedOut.load(ordering: .sequentiallyConsistent) { throw .timedOut }
        let (out, err) = collected.strings
        return CommandResult(exitCode: status, stdout: out, stderr: err)
    }
}

private nonisolated final class OutputCollector: Sendable {
    private struct Buffers {
        var out = Data()
        var err = Data()
        var outEnded = false
        var errEnded = false
    }

    private let buffers = Mutex(Buffers())

    /// Empty data means end of file, as `readabilityHandler` reports it.
    func append(_ data: Data, err: Bool) {
        buffers.withLock { buffers in
            switch (err, data.isEmpty) {
            case (true, true): buffers.errEnded = true
            case (false, true): buffers.outEnded = true
            case (true, false): buffers.err.append(data)
            case (false, false): buffers.out.append(data)
            }
        }
    }

    var reachedEnd: Bool { buffers.withLock { $0.outEnded && $0.errEnded } }

    var strings: (String, String) {
        buffers.withLock { (String(decoding: $0.out, as: UTF8.self), String(decoding: $0.err, as: UTF8.self)) }
    }
}
