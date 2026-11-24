import AppKit
import HerdrCoreKit
import SwiftUI

struct ConnectionSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var socketDraft = ""
    @State private var herdrAppDraft = ""
    @State private var list: TerminalList?
    @State private var listError: String?

    private var detectedSocket: String { SocketLocator.resolve().path(percentEncoded: false) }
    private var detectedHerdrApp: String? {
        HerdrAppLocator().locate()?.path(percentEncoded: false)
    }

    var body: some View {
        let preferences = model.preferences
        Form {
            Section {
                LabeledContent("Detected") {
                    PathText(detectedSocket, check: SocketPathCheck(path: detectedSocket) == .socket)
                }
                LabeledContent("Override") {
                    HStack {
                        TextField("Auto", text: $socketDraft, prompt: Text("Auto-detect"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .onSubmit(applySocket)
                        Button("Browse…", action: browseSocket)
                    }
                }
                if socketDraftCheck != nil || isSocketDirty || preferences.socketOverride != nil {
                    HStack {
                        if let check = socketDraftCheck {
                            Label(
                                check.message,
                                systemImage: check == .socket
                                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(check == .socket ? Theme.done : Theme.blocked)
                            .font(.caption)
                        }
                        Spacer()
                        if preferences.socketOverride != nil {
                            Button("Use Auto-Detect") {
                                socketDraft = ""
                                applySocket()
                            }
                        }
                        if isSocketDirty {
                            Button("Apply", action: applySocket)
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                }
            } header: {
                Text("herdr-core socket")
            } footer: {
                Text("Leave empty to find the socket the way `hc` does (HC_SOCKET, XDG directories, ~/.local/state).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Detected") {
                    if let detectedHerdrApp {
                        PathText(detectedHerdrApp, check: true)
                    } else {
                        Text("Not found").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Override") {
                    HStack {
                        TextField("Auto", text: $herdrAppDraft, prompt: Text("Auto-detect"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .onSubmit(applyHerdrApp)
                        Button("Browse…", action: browseHerdrApp)
                    }
                }
                if let valid = HerdrAppLocator().validateOverride(herdrAppDraft) {
                    Label(
                        valid ? "Executable found." : "Not an executable file; auto-detect is used instead.",
                        systemImage: valid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(valid ? Theme.done : Theme.blocked)
                    .font(.caption)
                }
            } header: {
                Text("herdr-app")
            } footer: {
                Text("Used to show a terminal in Herdr (`herdr-app do agent.focus`).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Core") {
                coreInfo
            }
        }
        .formStyle(.grouped)
        .onAppear {
            socketDraft = preferences.socketPath
            herdrAppDraft = preferences.herdrAppPath
        }
        .onChange(of: herdrAppDraft) { applyHerdrApp() }
        .task(id: model.store.connection) { await loadList() }
    }

    @ViewBuilder
    private var coreInfo: some View {
        switch model.store.connection {
        case .live(let core):
            LabeledContent("Name", value: core.name)
            LabeledContent("Version", value: core.version)
            LabeledContent("Protocol generation", value: "\(core.generation)")
            LabeledContent("Terminals", value: list.map { "\($0.terminals.count)" } ?? "…")
            LabeledContent("Machines") {
                if let machines = list?.machines, !machines.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        ForEach(machines) { machine in
                            HStack(spacing: 4) {
                                Text(machine.name)
                                Text(machine.state).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text(list == nil ? "…" : "This Mac only").foregroundStyle(.secondary)
                }
            }
            if let listError {
                Text(listError).font(.caption).foregroundStyle(Theme.error)
            }
            HStack {
                Spacer()
                Button("Reconnect", action: model.reconnect)
            }
        case .connecting:
            LabeledContent("Status", value: "Connecting…")
        case .offline(let info):
            LabeledContent("Status") {
                Text(info.title).foregroundStyle(Theme.error)
            }
            Text(info.detail).font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Retry Now", action: model.reconnect)
            }
        }
    }

    private var isSocketDirty: Bool {
        socketDraft.trimmingCharacters(in: .whitespaces) != model.preferences.socketPath
    }

    private var socketDraftCheck: SocketPathCheck? {
        let trimmed = socketDraft.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : SocketPathCheck(path: trimmed)
    }

    private func applySocket() {
        model.preferences.socketPath = socketDraft.trimmingCharacters(in: .whitespaces)
    }

    private func applyHerdrApp() {
        model.preferences.herdrAppPath = herdrAppDraft.trimmingCharacters(in: .whitespaces)
        model.refreshInstallation()
    }

    private func loadList() async {
        guard model.store.connection.isLive else {
            list = nil
            return
        }
        do {
            list = try await model.store.commands.fetchTerminalList()
            listError = nil
        } catch {
            listError = error.description
        }
    }

    private func browseSocket() {
        let panel = NSOpenPanel()
        panel.title = "Choose the herdr-core socket"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        let current = socketDraft.isEmpty ? detectedSocket : (socketDraft as NSString).expandingTildeInPath
        panel.directoryURL = URL(filePath: (current as NSString).deletingLastPathComponent)
        if panel.runModal() == .OK, let url = panel.url {
            socketDraft = url.path(percentEncoded: false)
            applySocket()
        }
    }

    private func browseHerdrApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose the herdr-app executable"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin")
        if panel.runModal() == .OK, let url = panel.url {
            herdrAppDraft = url.path(percentEncoded: false)
        }
    }
}

/// A path, abbreviated with `~`, selectable, with an optional check mark.
struct PathText: View {
    let path: String
    let check: Bool?

    init(_ path: String, check: Bool? = nil) {
        self.path = path
        self.check = check
    }

    var body: some View {
        HStack(spacing: 4) {
            Text((path as NSString).abbreviatingWithTildeInPath)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(path)
            if let check {
                Image(systemName: check ? "checkmark.circle.fill" : "questionmark.circle")
                    .foregroundStyle(check ? Theme.done : .secondary)
                    .help(check ? "Found" : "Not found")
            }
        }
    }
}
