import Foundation
import Testing

@testable import HerdrCoreKit

@Suite("SocketLocator")
struct SocketLocatorTests {
    let home = URL(filePath: "/Users/sample")

    func resolve(_ environment: [String: String], override: String? = nil, existing: Set<String> = []) -> String {
        SocketLocator.resolve(override: override, environment: environment, home: home) { existing.contains($0) }
            .path(percentEncoded: false)
    }

    @Test func defaultsToStateDirectory() {
        #expect(resolve([:]) == "/Users/sample/.local/state/herdr-core/default/default.sock")
    }

    @Test func sessionAndStateHome() {
        #expect(
            resolve(["HC_SESSION": "work", "XDG_STATE_HOME": "/var/state"])
                == "/var/state/herdr-core/work/work.sock")
    }

    @Test func runtimeDirectoryWins() {
        #expect(
            resolve(["HC_SESSION": "probe", "XDG_RUNTIME_DIR": "/run/user/5", "XDG_STATE_HOME": "/var/state"])
                == "/run/user/5/herdr-core/probe.sock")
    }

    @Test func existingStateSocketBeatsMissingRuntimeSocket() {
        let environment = ["XDG_RUNTIME_DIR": "/run/user/5"]
        let state = "/Users/sample/.local/state/herdr-core/default/default.sock"
        #expect(resolve(environment, existing: [state]) == state)
        #expect(
            SocketLocator.candidates(environment: environment, home: home).map { $0.path(percentEncoded: false) }
                == ["/run/user/5/herdr-core/default.sock", state])
    }

    @Test func explicitSocketAndTilde() {
        #expect(
            resolve(["HC_SOCKET": "~/sockets/core.sock", "XDG_RUNTIME_DIR": "/run"])
                == "/Users/sample/sockets/core.sock")
        #expect(resolve(["HC_SOCKET": "/a.sock"], override: "~/b.sock") == "/Users/sample/b.sock")
        #expect(resolve(["XDG_STATE_HOME": "~/st"]) == "/Users/sample/st/herdr-core/default/default.sock")
    }

    @Test func emptyValuesAreIgnored() {
        #expect(
            resolve(["HC_SOCKET": "", "HC_SESSION": " ", "XDG_RUNTIME_DIR": ""], override: "")
                == "/Users/sample/.local/state/herdr-core/default/default.sock")
    }
}
