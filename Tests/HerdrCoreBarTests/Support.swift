import Foundation
import HerdrCoreKit

@testable import HerdrCoreBar

func agent(
    _ address: String, _ state: StatusWord?, app: String = "copilot", turn: Int = 1, seen: Int? = nil,
    where place: String? = nil, title: String = "", kind: BlockedKind? = nil, msg: String? = nil,
    progress: Int? = nil, statusMs: Int? = nil, lifecycle: TerminalLifecycle = .live
) -> Terminal {
    var labels: [String: String] = [:]
    if let seen { labels[Terminal.seenLabel] = String(seen) }
    if let place { labels[Terminal.whereLabel] = place }
    return Terminal(
        address: address, labels: labels, argv: [app], cwd: "/work/project", lifecycle: lifecycle, title: title,
        status: state.map { TerminalStatus(state: $0, app: app, kind: kind, progress: progress, msg: msg) },
        statusMs: statusMs, turn: turn, reported: state != nil)
}

func shell(_ address: String, where place: String? = nil) -> Terminal {
    Terminal(
        address: address, labels: place.map { [Terminal.whereLabel: $0] } ?? [:], argv: ["/bin/zsh"],
        cwd: "/work/project")
}

func state(_ terminals: Terminal...) -> TerminalState {
    TerminalState(snapshot: Snapshot(seq: 1, terminals: terminals))
}

/// A fresh, isolated defaults domain.
func makeDefaults() -> UserDefaults {
    let name = "herdr-core-bar-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removePersistentDomain(forName: name)
    return defaults
}
