import Foundation

/// Finds the herdr-core control socket the way `hc` does.
///
/// Order: an explicit override, then `HC_SOCKET`, then `$XDG_RUNTIME_DIR/herdr-core/<session>.sock`, then
/// `${XDG_STATE_HOME:-~/.local/state}/herdr-core/<session>/<session>.sock`, where the session is `HC_SESSION` or
/// `default`. An override or `HC_SOCKET` is used as is (with `~` expanded); among the implicit locations the first
/// existing one wins, else the first. GUI apps get no shell environment, so the state directory usually applies.
public enum SocketLocator {
    public static let defaultSession = "default"

    public static func resolve(
        override: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL {
        if let override = nonEmpty(override) {
            return URL(filePath: expandTilde(override, home: home))
        }
        if let socket = nonEmpty(environment["HC_SOCKET"]) {
            return URL(filePath: expandTilde(socket, home: home))
        }
        let candidates = candidates(environment: environment, home: home)
        return candidates.first { fileExists($0.path(percentEncoded: false)) } ?? candidates[0]
    }

    /// Implicit locations in priority order. `resolve` prefers the first one that exists, so a GUI app whose
    /// environment differs from the shell that started the core still finds it.
    public static func candidates(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let session = nonEmpty(environment["HC_SESSION"]) ?? defaultSession
        var result: [URL] = []
        if let runtime = nonEmpty(environment["XDG_RUNTIME_DIR"]) {
            result.append(
                URL(filePath: expandTilde(runtime, home: home)).appending(components: "herdr-core", "\(session).sock"))
        }
        let defaultState = home.appending(components: ".local", "state")
        let states = [
            nonEmpty(environment["XDG_STATE_HOME"]).map { URL(filePath: expandTilde($0, home: home)) }, defaultState,
        ]
        for state in states.compactMap(\.self) {
            let url = state.appending(components: "herdr-core", session, "\(session).sock")
            if !result.contains(url) { result.append(url) }
        }
        return result
    }

    static func expandTilde(_ path: String, home: URL) -> String {
        let homePath = home.path(percentEncoded: false)
        if path == "~" { return homePath }
        guard path.hasPrefix("~/") else { return path }
        let base = homePath.hasSuffix("/") ? String(homePath.dropLast()) : homePath
        return base + path.dropFirst()
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
    }
}
