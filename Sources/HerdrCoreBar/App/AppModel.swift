import AppKit
import Foundation
import HerdrCoreKit
import OSLog
import Observation

enum SettingsTab: String, Hashable, CaseIterable {
    case general, notifications, connection, updates, about
}

/// A transient message at the top of the popover.
struct Banner: Identifiable, Equatable {
    enum Style: Equatable {
        case error, info
    }

    var id = UUID()
    var message: String
    var style: Style
}

/// Composition root and the actions views call.
@Observable
final class AppModel {
    let preferences: Preferences
    let store: TerminalStore
    let notifications: NotificationService
    let updater: UpdaterService
    let loginItem: LoginItemService
    let isPreview: Bool

    private(set) var banner: Banner?
    private(set) var openingAddress: String?
    private(set) var isHerdrInstalled = true
    var settingsTab: SettingsTab = .general

    /// Closes the popover window; set by the popover.
    @ObservationIgnored var closePopover: (() -> Void)?

    @ObservationIgnored private let focuser: any TerminalFocusing
    @ObservationIgnored private let locator: HerdrAppLocator
    @ObservationIgnored private var policy = NotificationPolicy()
    @ObservationIgnored private var delivered: [String: AgentAlert] = [:]
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private var preferencesTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.olohmann.herdr-core-bar", category: "app")

    static let notificationDelay: Duration = .milliseconds(1500)

    init(
        preferences: Preferences, backend: any CoreBackend, focuser: (any TerminalFocusing)? = nil,
        notifications: NotificationService = NotificationService(), updater: UpdaterService = UpdaterService(),
        loginItem: LoginItemService = LoginItemService(), locator: HerdrAppLocator = HerdrAppLocator(),
        isPreview: Bool = false
    ) {
        self.preferences = preferences
        self.notifications = notifications
        self.updater = updater
        self.loginItem = loginItem
        self.locator = locator
        self.isPreview = isPreview
        store = TerminalStore(backend: backend, socketURL: SocketLocator.resolve(override: preferences.socketOverride))
        self.focuser =
            focuser
            ?? HerdrAppController(
                locator: locator,
                override: { [preferences] in
                    preferences.herdrAppOverride
                })
    }

    static func live() -> AppModel {
        AppModel(preferences: Preferences(), backend: LiveCoreBackend())
    }

    static func preview() -> AppModel {
        let defaults = UserDefaults(suiteName: "\(AppBundle.identifier).preview") ?? .standard
        let core = PreviewCore()
        return AppModel(
            preferences: Preferences(defaults: defaults), backend: core, focuser: PreviewFocuser(),
            notifications: NotificationService(isAvailable: false), updater: UpdaterService(enabled: false),
            loginItem: LoginItemService(isAvailable: false), isPreview: true)
    }

    // MARK: - Lifecycle

    func start() {
        store.onStateChange = { [weak self] previous, next in self?.stateChanged(from: previous, to: next) }
        notifications.playsSoundInForeground = { [preferences] in preferences.notificationSound }
        notifications.onAction = { [weak self] action in self?.handle(action) }
        notifications.activate()
        refreshInstallation()
        store.start()
        preferencesTask = Task { [weak self, preferences] in
            let paths = Observations { preferences.socketOverride }
            for await _ in paths {
                guard let self else { return }
                self.applySocketOverride()
            }
        }
    }

    func stop() {
        preferencesTask?.cancel()
        store.stop()
    }

    func reconnect() {
        refreshInstallation()
        store.restart(socket: SocketLocator.resolve(override: preferences.socketOverride))
    }

    private func applySocketOverride() {
        let socket = SocketLocator.resolve(override: preferences.socketOverride)
        guard socket != store.socketURL else { return }
        log.info("Socket changed to \(socket.path(percentEncoded: false), privacy: .public)")
        policy = NotificationPolicy()
        store.restart(socket: socket)
    }

    func popoverDidAppear() {
        refreshInstallation()
        Task {
            await store.refreshMachines()
            await notifications.refreshAuthorization()
        }
    }

    func refreshInstallation() {
        guard !isPreview else { return }
        isHerdrInstalled = HerdrInstallation().isInstalled(
            herdrApp: locator.locate(override: preferences.herdrAppOverride),
            herdrAppBundle: WorkspaceHerdrActivator().appURL)
    }

    // MARK: - Derived

    var sections: TerminalSections {
        TerminalSections(store.state.terminals.values, options: preferences.sectionOptions)
    }

    var summary: StatusSummary {
        StatusSummary(store.state.terminals.values, options: preferences.sectionOptions)
    }

    var unreadTerminals: [Terminal] {
        store.state.sorted.filter {
            $0.attention == .doneUnread && TerminalSections.isShown($0, options: preferences.sectionOptions)
        }
    }

    // MARK: - Actions

    func open(_ terminal: Terminal) async {
        guard openingAddress == nil else { return }
        openingAddress = terminal.address
        defer { openingAddress = nil }
        do {
            try await focuser.focus(terminal)
            dismissBanner()
            withdrawNotifications(for: terminal.address)
            closePopover?()
            if terminal.isUnreadDone { await markRead(terminal) }
        } catch {
            log.error("Open \(terminal.address, privacy: .public) failed: \(error.message, privacy: .public)")
            show(Banner(message: error.message, style: .error))
        }
    }

    #if DEBUG
        /// Waits for the first snapshot, then opens `address` and logs the outcome.
        func debugFocus(_ address: String) async {
            for _ in 0..<100 where !store.hasSnapshot {
                try? await Task.sleep(for: .milliseconds(100))
            }
            await open(address: address)
            log.info(
                "Debug focus \(address, privacy: .public): banner=\(self.banner?.message ?? "none", privacy: .public)")
        }
    #endif

    func open(address: String) async {
        guard let terminal = store.state[address] else {
            show(Banner(message: "That terminal is gone.", style: .info))
            return
        }
        await open(terminal)
    }

    func markRead(_ terminal: Terminal) async {
        withdrawNotifications(for: terminal.address)
        guard terminal.isUnreadDone else { return }
        do {
            try await store.commands.markRead(terminal)
            log.info("Marked \(terminal.address, privacy: .public) read at turn \(terminal.turn)")
        } catch {
            show(Banner(message: "Couldn't mark as read: \(error.description)", style: .error))
        }
    }

    func markAllRead() async {
        let terminals = unreadTerminals
        await withTaskGroup(of: Void.self) { group in
            for terminal in terminals {
                group.addTask { await self.markRead(terminal) }
            }
        }
    }

    func copyAddress(_ terminal: Terminal) { copy(terminal.address) }

    func copyWorkingDirectory(_ terminal: Terminal) { copy(terminal.workingDirectory) }

    func revealWorkingDirectory(_ terminal: Terminal) {
        guard terminal.machine == nil, !terminal.workingDirectory.isEmpty else { return }
        let url = URL(filePath: terminal.workingDirectory, directoryHint: .isDirectory)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openHerdr() {
        WorkspaceHerdrActivator().open()
    }

    func dismissBanner() {
        bannerTask?.cancel()
        banner = nil
    }

    func show(_ banner: Banner) {
        self.banner = banner
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, self?.banner?.id == banner.id else { return }
            self?.banner = nil
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Notifications

    private func handle(_ action: NotificationService.Action) {
        switch action {
        case .open(let address):
            Task { await open(address: address) }
        case .markRead(let address):
            guard let terminal = store.state[address] else { return }
            Task { await markRead(terminal) }
        }
    }

    private func stateChanged(from previous: TerminalState?, to next: TerminalState) {
        let counts = StatusSummary(next.terminals.values, options: preferences.sectionOptions)
        log.debug("State \(next.seq): \(counts.spokenDescription, privacy: .public)")
        let stale = delivered.values.filter { !NotificationPolicy.shouldDeliver($0, in: next) }
        if !stale.isEmpty {
            notifications.remove(identifiers: stale.map(\.id))
            for alert in stale { delivered[alert.id] = nil }
        }

        policy.enabled = preferences.notificationKinds
        guard !policy.enabled.isEmpty, notifications.isAvailable else { return }
        if next.terminals.values.contains(where: { $0.isLive && $0.isAgent }) {
            Task { await notifications.requestAuthorizationIfNeeded() }
        }
        for alert in policy.alerts(from: previous, to: next) {
            Task { [weak self] in
                try? await Task.sleep(for: Self.notificationDelay)
                await self?.deliver(alert)
            }
        }
    }

    private func deliver(_ alert: AgentAlert) async {
        guard NotificationPolicy.shouldDeliver(alert, in: store.state) else { return }
        switch alert.kind {
        case .blocked: guard preferences.notifyBlocked else { return }
        case .done: guard preferences.notifyDone else { return }
        }
        delivered[alert.id] = alert
        await notifications.post(NotificationContent(alert: alert, sound: preferences.notificationSound))
    }

    private func withdrawNotifications(for address: String) {
        let matching = delivered.values.filter { $0.address == address }
        notifications.remove(identifiers: matching.map(\.id))
        for alert in matching { delivered[alert.id] = nil }
    }
}

extension Terminal {
    /// The foreground process's directory when known, else the terminal's.
    var workingDirectory: String {
        if let cwd = foreground?.cwd, !cwd.isEmpty { return cwd }
        return cwd
    }
}
