import Foundation
import HerdrCoreKit

/// Invented but realistic terminals for `--preview` and screenshots.
nonisolated enum PreviewData {
    static let hello = HelloResult(
        core: CoreInfo(id: "c0ffee42", name: "default"), version: "0.1.22", generation: 1,
        methods: ["hello", "events.subscribe", "terminal.list", "terminal.label"])

    static let machines = [
        MachineView(
            id: "studio-mini", name: "studio-mini", host: "studio-mini.local", version: "0.1.22", state: "connected")
    ]

    static func terminals(now: Date = Date()) -> [Terminal] {
        let nowMs = Int(now.timeIntervalSince1970 * 1000)
        func ago(_ seconds: Int) -> Int { nowMs - seconds * 1000 }

        func agent(
            _ address: String, app: String, state: StatusWord, where place: String, title: String,
            cwd: String, turn: Int = 1, seen: Int? = nil, kind: BlockedKind? = nil, msg: String? = nil,
            progress: Int? = nil, changed: Int
        ) -> Terminal {
            var labels = [Terminal.whereLabel: place]
            if let seen { labels[Terminal.seenLabel] = String(seen) }
            return Terminal(
                address: address, labels: labels, argv: [app], cwd: cwd, createdMs: ago(changed + 600), title: title,
                status: TerminalStatus(state: state, app: app, kind: kind, progress: progress, msg: msg),
                statusMs: ago(changed), turn: turn, reported: true,
                foreground: Foreground(argv: [app], cwd: cwd, name: app, pid: 4000 + turn))
        }

        return [
            agent(
                "t2", app: "claude", state: .blocked, where: "atlas-api / auth-refactor",
                title: "Refresh-token rotation", cwd: "/Users/sam/code/atlas-api", turn: 6, kind: .permission,
                msg: "Run npm install jose?", changed: 40),
            agent(
                "t4", app: "copilot", state: .done, where: "garden-web / landing",
                title: "Hero section with seasonal palette - GitHub Copilot", cwd: "/Users/sam/code/garden-web",
                turn: 9, seen: 8, msg: "Updated 4 files, all checks pass", changed: 180),
            agent(
                "t5", app: "codex", state: .working, where: "atlas-api / tests", title: "Flaky integration tests",
                cwd: "/Users/sam/code/atlas-api", turn: 3, msg: "Running test suite", progress: 64, changed: 95),
            agent(
                "t7", app: "pi", state: .working, where: "notes / weekly", title: "Summarize sprint retro",
                cwd: "/Users/sam/notes", turn: 2, msg: "Reading 12 documents", changed: 300),
            agent(
                "t8", app: "copilot", state: .idle, where: "garden-web / docs", title: "Component docs",
                cwd: "/Users/sam/code/garden-web/docs", changed: 3_600),
            agent(
                "t9", app: "claude", state: .done, where: "atlas-api / auth-refactor", title: "Session middleware",
                cwd: "/Users/sam/code/atlas-api", turn: 4, seen: 4, msg: "Merged into feature branch",
                changed: 5_400),
            Terminal(
                address: "t10", labels: [Terminal.whereLabel: "atlas-api / shell"], argv: ["/bin/zsh"],
                cwd: "/Users/sam/code/atlas-api", createdMs: ago(7_200), title: "",
                foreground: Foreground(argv: ["zsh"], cwd: "/Users/sam/code/atlas-api", name: "zsh", pid: 3999)),
            agent(
                "studio-mini/t3", app: "claude", state: .working, where: "render-farm / shaders",
                title: "Port bloom pass to Metal", cwd: "/Users/sam/render-farm", turn: 5, msg: "Compiling shaders",
                progress: 30, changed: 25),
            agent(
                "studio-mini/t6", app: "codex", state: .blocked, where: "render-farm / assets",
                title: "Texture atlas packer", cwd: "/Users/sam/render-farm/assets", turn: 2, kind: .question,
                msg: "Keep PNG or switch to KTX2?", changed: 600),
            agent(
                "studio-mini/t9", app: "pi", state: .done, where: "render-farm / ci", title: "Nightly build",
                cwd: "/Users/sam/render-farm", turn: 12, seen: 11, msg: "Build 1482 green", changed: 1_500),
        ]
    }

    static func state(now: Date = Date()) -> TerminalState {
        TerminalState(snapshot: Snapshot(seq: 100, terminals: terminals(now: now)))
    }

    static let emptyState = TerminalState(snapshot: Snapshot(seq: 1, terminals: []))
}
