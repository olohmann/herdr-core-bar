import Foundation

/// Whether anything of Herdr is on this Mac, to tell "not running" from "not installed".
nonisolated struct HerdrInstallation: Sendable {
    var fileSystem: any FileSystemProbing = LocalFileSystem()
    var home: String = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)

    func isInstalled(herdrApp: URL?, herdrAppBundle: URL?) -> Bool {
        if herdrApp != nil || herdrAppBundle != nil { return true }
        let tools = ["\(home)/.local/bin/hc", "/opt/homebrew/bin/hc", "/usr/local/bin/hc"]
        if tools.contains(where: fileSystem.isExecutableFile(atPath:)) { return true }
        let directories = [
            "/Applications/Herdr.app", "\(home)/Applications/Herdr.app", "\(home)/.local/share/herdr-core",
        ]
        return directories.contains(where: fileSystem.directoryExists(atPath:))
    }
}
