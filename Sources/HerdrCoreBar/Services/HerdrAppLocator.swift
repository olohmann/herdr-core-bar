import Foundation

/// The file system calls the locator needs, so tests can fake them.
nonisolated protocol FileSystemProbing: Sendable {
    func isExecutableFile(atPath path: String) -> Bool
    func directoryExists(atPath path: String) -> Bool
    /// Every file path below `directory`, recursively.
    func filesRecursively(in directory: String) -> [String]
}

nonisolated struct LocalFileSystem: FileSystemProbing {
    func isExecutableFile(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    func directoryExists(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func filesRecursively(in directory: String) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: directory) else { return [] }
        var result: [String] = []
        while let relative = enumerator.nextObject() as? String {
            result.append((directory as NSString).appendingPathComponent(relative))
        }
        return result
    }
}

/// Finds the `herdr-app` command line tool that drives Herdr.app.
nonisolated struct HerdrAppLocator: Sendable {
    static let executableName = "herdr-app"
    static let bundleIdentifier = "dev.herdr.app"

    var fileSystem: any FileSystemProbing = LocalFileSystem()
    var home: String = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
    /// Herdr.app bundles to look inside, in order (e.g. `/Applications/Herdr.app`).
    var appBundles: [String] = ["/Applications/Herdr.app"]

    /// Fixed candidates in priority order; bundles are searched afterwards.
    func candidates(override: String?) -> [String] {
        var result: [String] = []
        if let override = override?.trimmingCharacters(in: .whitespaces), !override.isEmpty {
            result.append(expandTilde(override))
        }
        result += [
            (home as NSString).appendingPathComponent(".local/bin/\(Self.executableName)"),
            "/opt/homebrew/bin/\(Self.executableName)",
            "/usr/local/bin/\(Self.executableName)",
        ]
        return result
    }

    /// The first executable `herdr-app`: override, `~/.local/bin`, Homebrew, `/usr/local/bin`, then inside
    /// Herdr.app (`Contents/MacOS`, then anywhere below `Contents/Resources`).
    func locate(override: String? = nil) -> URL? {
        if let path = candidates(override: override).first(where: fileSystem.isExecutableFile(atPath:)) {
            return URL(filePath: path)
        }
        for bundle in appBundles {
            let macOS = "\(bundle)/Contents/MacOS/\(Self.executableName)"
            if fileSystem.isExecutableFile(atPath: macOS) { return URL(filePath: macOS) }
            let resources = "\(bundle)/Contents/Resources"
            guard fileSystem.directoryExists(atPath: resources) else { continue }
            let match = fileSystem.filesRecursively(in: resources)
                .filter { ($0 as NSString).lastPathComponent == Self.executableName }
                .sorted { $0.count < $1.count }
                .first(where: fileSystem.isExecutableFile(atPath:))
            if let match { return URL(filePath: match) }
        }
        return nil
    }

    /// Whether the override names an executable; nil when there is no override.
    func validateOverride(_ override: String) -> Bool? {
        let trimmed = override.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return fileSystem.isExecutableFile(atPath: expandTilde(trimmed))
    }

    private func expandTilde(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return (home as NSString).appendingPathComponent(String(path.dropFirst(path == "~" ? 1 : 2)))
    }
}
