import Foundation

/// Command line switches.
struct LaunchOptions: Equatable {
    /// `--preview`: synthetic data instead of the real core.
    var preview = false
    /// `--render-preview <dir>`: write screenshots and exit without showing UI.
    var renderDirectory: URL?
    /// Debug builds: `--debug-focus <address>` opens that terminal once connected, for end-to-end checks.
    var debugFocusAddress: String?

    init(preview: Bool = false, renderDirectory: URL? = nil) {
        self.preview = preview
        self.renderDirectory = renderDirectory
    }

    init(arguments: [String]) {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--preview":
                preview = true
            case "--render-preview":
                if let path = iterator.next() {
                    renderDirectory = URL(
                        filePath: (path as NSString).expandingTildeInPath, directoryHint: .isDirectory)
                }
            case "--debug-focus":
                debugFocusAddress = iterator.next()
            default:
                continue
            }
        }
    }
}
