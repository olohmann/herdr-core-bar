import Foundation
import HerdrCoreKit
import Testing

@testable import HerdrCoreBar

@Suite struct NotificationContentTests {
    @Test func blockedAlertNamesTheAppAndReason() {
        let terminal = agent(
            "t3", .blocked, app: "claude", turn: 4, where: "atlas / auth", title: "Token rotation - Claude",
            kind: .permission, msg: "Run npm install?")
        let alert = AgentAlert(kind: .blocked(.permission, message: "Run npm install?"), terminal: terminal)
        let content = NotificationContent(alert: alert, sound: true)
        #expect(content.title == "Claude needs you")
        #expect(content.body == "Token rotation\nNeeds permission: Run npm install? · atlas / auth")
        #expect(content.threadIdentifier == "terminal:t3")
        #expect(content.categoryIdentifier == NotificationContent.blockedCategory)
        #expect(content.identifier == alert.id)
        #expect(content.address == "t3")
        #expect(content.turn == 4)
        #expect(content.playsSound)
    }

    @Test func doneAlertIncludesMessageAndRemoteMachine() {
        let terminal = agent(
            "mini/t9", .done, app: "codex", turn: 2, where: "farm / ci", title: "Nightly", msg: "Green")
        let content = NotificationContent(alert: AgentAlert(kind: .done, terminal: terminal), sound: false)
        #expect(content.title == "Codex finished")
        #expect(content.body == "Nightly\nGreen · mini · farm / ci")
        #expect(content.categoryIdentifier == NotificationContent.doneCategory)
        #expect(!content.playsSound)
    }

    @Test func fallsBackWhenDetailsAreMissing() {
        var terminal = agent("t1", .blocked, app: "", kind: nil)
        terminal.argv = []
        terminal.cwd = ""
        let content = NotificationContent(
            alert: AgentAlert(kind: .blocked(nil, message: nil), terminal: terminal), sound: true)
        #expect(content.title == "An agent needs you")
        #expect(content.body == "t1\nNeeds you")
    }
}

@Suite struct PreferencesTests {
    @Test func defaults() {
        let preferences = Preferences(defaults: makeDefaults())
        #expect(preferences.socketPath.isEmpty)
        #expect(preferences.herdrAppPath.isEmpty)
        #expect(preferences.agentsOnly)
        #expect(preferences.showRemote)
        #expect(preferences.showIdle)
        #expect(preferences.notifyBlocked)
        #expect(preferences.notifyDone)
        #expect(preferences.notificationSound)
        #expect(preferences.socketOverride == nil)
        #expect(preferences.notificationKinds == .all)
    }

    @Test func persistsChanges() {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.agentsOnly = false
        preferences.notifyDone = false
        preferences.socketPath = "  /tmp/core.sock "
        let reloaded = Preferences(defaults: defaults)
        #expect(!reloaded.agentsOnly)
        #expect(reloaded.notificationKinds == .blocked)
        #expect(reloaded.socketOverride == "/tmp/core.sock")
    }
}

@Suite struct LaunchOptionsTests {
    @Test func parsesSwitches() {
        #expect(LaunchOptions(arguments: ["app"]) == LaunchOptions())
        #expect(LaunchOptions(arguments: ["app", "--preview"]).preview)
        let render = LaunchOptions(arguments: ["app", "--render-preview", "/shots"])
        #expect(render.renderDirectory?.path(percentEncoded: false) == "/shots/")
    }
}
