import Foundation

/// A status word reported by a program (`state=...` in OSC 7501). Unknown words survive a round trip.
public enum StatusWord: Sendable, Hashable, Codable, CustomStringConvertible {
    case idle
    case working
    case done
    case blocked
    case error
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "idle": self = .idle
        case "working": self = .working
        case "done": self = .done
        case "blocked": self = .blocked
        case "error": self = .error
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .idle: "idle"
        case .working: "working"
        case .done: "done"
        case .blocked: "blocked"
        case .error: "error"
        case .unknown(let word): word
        }
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Why a blocked program waits.
public enum BlockedKind: Sendable, Hashable, Codable, CustomStringConvertible {
    case permission
    case question
    case auth
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "permission": self = .permission
        case "question": self = .question
        case "auth": self = .auth
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .permission: "permission"
        case .question: "question"
        case .auth: "auth"
        case .unknown(let kind): kind
        }
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Whether a terminal's program still runs (`state` of a terminal).
public enum TerminalLifecycle: Sendable, Hashable, Codable {
    case live
    case finished
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "live": self = .live
        case "finished": self = .finished
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .live: "live"
        case .finished: "finished"
        case .unknown(let state): state
        }
    }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// What a program reported about itself.
public struct TerminalStatus: Sendable, Hashable, Codable {
    public var state: StatusWord
    public var app: String?
    public var kind: BlockedKind?
    public var progress: Int?
    public var msg: String?
    public var title: String?

    public init(
        state: StatusWord, app: String? = nil, kind: BlockedKind? = nil, progress: Int? = nil,
        msg: String? = nil, title: String? = nil
    ) {
        self.state = state
        self.app = app
        self.kind = kind
        self.progress = progress
        self.msg = msg
        self.title = title
    }
}

/// The process currently in the terminal's foreground.
public struct Foreground: Sendable, Hashable, Codable {
    public var argv: [String]
    public var cwd: String
    public var name: String
    public var pid: Int

    public init(argv: [String] = [], cwd: String = "", name: String = "", pid: Int = 0) {
        self.argv = argv
        self.cwd = cwd
        self.name = name
        self.pid = pid
    }

    private enum CodingKeys: String, CodingKey {
        case argv, cwd, name, pid
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        argv = try c.decodeIfPresent([String].self, forKey: .argv) ?? []
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        pid = try c.decodeIfPresent(Int.self, forKey: .pid) ?? 0
    }
}

/// A terminal as herdr-core describes it. Only `address` is required when decoding; everything else defaults.
public struct Terminal: Sendable, Hashable, Codable, Identifiable {
    public var address: String
    public var labels: [String: String]
    public var argv: [String]
    public var cwd: String
    public var lifecycle: TerminalLifecycle
    public var createdMs: Int
    public var screen: String
    public var cols: Int
    public var rows: Int
    public var name: String?
    public var title: String
    public var status: TerminalStatus?
    public var statusMs: Int?
    public var turn: Int
    public var reported: Bool
    public var records: [String: TerminalStatus]
    public var parent: String?
    public var template: String?
    public var foreground: Foreground?
    public var exitCode: Int?
    public var finishedMs: Int?
    public var reason: String?
    public var signal: Int?
    public var keep: Bool
    public var notify: Bool
    public var pid: Int?
    public var identity: String
    /// Set locally after a `lost` event until `restarted` (or a fresh snapshot); not part of the wire format.
    public var isLost: Bool = false

    public var id: String { address }

    public init(
        address: String, labels: [String: String] = [:], argv: [String] = [], cwd: String = "",
        lifecycle: TerminalLifecycle = .live, createdMs: Int = 0, screen: String = "", cols: Int = 0, rows: Int = 0,
        name: String? = nil, title: String = "", status: TerminalStatus? = nil, statusMs: Int? = nil, turn: Int = 0,
        reported: Bool = false, records: [String: TerminalStatus] = [:], parent: String? = nil,
        template: String? = nil, foreground: Foreground? = nil, exitCode: Int? = nil, finishedMs: Int? = nil,
        reason: String? = nil, signal: Int? = nil, keep: Bool = false, notify: Bool = false, pid: Int? = nil,
        identity: String = ""
    ) {
        self.address = address
        self.labels = labels
        self.argv = argv
        self.cwd = cwd
        self.lifecycle = lifecycle
        self.createdMs = createdMs
        self.screen = screen
        self.cols = cols
        self.rows = rows
        self.name = name
        self.title = title
        self.status = status
        self.statusMs = statusMs
        self.turn = turn
        self.reported = reported
        self.records = records
        self.parent = parent
        self.template = template
        self.foreground = foreground
        self.exitCode = exitCode
        self.finishedMs = finishedMs
        self.reason = reason
        self.signal = signal
        self.keep = keep
        self.notify = notify
        self.pid = pid
        self.identity = identity
    }

    private enum CodingKeys: String, CodingKey {
        case address, labels, argv, cwd
        case lifecycle = "state"
        case createdMs = "created_ms"
        case screen, cols, rows, name, title, status
        case statusMs = "status_ms"
        case turn, reported, records, parent, template, foreground
        case exitCode = "exit_code"
        case finishedMs = "finished_ms"
        case reason, signal, keep, notify, pid, identity
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address = try c.decode(String.self, forKey: .address)
        labels = try c.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        argv = try c.decodeIfPresent([String].self, forKey: .argv) ?? []
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        lifecycle = try c.decodeIfPresent(TerminalLifecycle.self, forKey: .lifecycle) ?? .live
        createdMs = try c.decodeIfPresent(Int.self, forKey: .createdMs) ?? 0
        screen = try c.decodeIfPresent(String.self, forKey: .screen) ?? ""
        cols = try c.decodeIfPresent(Int.self, forKey: .cols) ?? 0
        rows = try c.decodeIfPresent(Int.self, forKey: .rows) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        status = try c.decodeIfPresent(TerminalStatus.self, forKey: .status)
        statusMs = try c.decodeIfPresent(Int.self, forKey: .statusMs)
        turn = try c.decodeIfPresent(Int.self, forKey: .turn) ?? 0
        reported = try c.decodeIfPresent(Bool.self, forKey: .reported) ?? false
        records = try c.decodeIfPresent([String: TerminalStatus].self, forKey: .records) ?? [:]
        parent = try c.decodeIfPresent(String.self, forKey: .parent)
        template = try c.decodeIfPresent(String.self, forKey: .template)
        foreground = try c.decodeIfPresent(Foreground.self, forKey: .foreground)
        exitCode = try c.decodeIfPresent(Int.self, forKey: .exitCode)
        finishedMs = try c.decodeIfPresent(Int.self, forKey: .finishedMs)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        signal = try c.decodeIfPresent(Int.self, forKey: .signal)
        keep = try c.decodeIfPresent(Bool.self, forKey: .keep) ?? false
        notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? false
        pid = try c.decodeIfPresent(Int.self, forKey: .pid)
        identity = try c.decodeIfPresent(String.self, forKey: .identity) ?? ""
    }
}

/// A terminal address split into its machine (nil for this core) and the id on that machine.
/// `"192.168.10.94/t4"` has machine `"192.168.10.94"` and id `"t4"`.
public struct TerminalAddress: Sendable, Hashable, CustomStringConvertible {
    public var machine: String?
    public var id: String

    public init(machine: String?, id: String) {
        self.machine = machine
        self.id = id
    }

    public init(_ address: String) {
        if let slash = address.lastIndex(of: "/") {
            let machine = String(address[..<slash])
            self.machine = machine.isEmpty ? nil : machine
            id = String(address[address.index(after: slash)...])
        } else {
            machine = nil
            id = address
        }
    }

    public var isLocal: Bool { machine == nil }
    public var description: String { machine.map { "\($0)/\(id)" } ?? id }

    /// The numeric part of `t7`, for natural ordering.
    var number: Int? { Int(id.drop { !$0.isNumber }) }
}

public struct CoreInfo: Sendable, Hashable, Codable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct LoginSession: Sendable, Hashable, Codable {
    public var id: Int
    public var user: Int
    public var gui: Bool?

    public init(id: Int, user: Int, gui: Bool? = nil) {
        self.id = id
        self.user = user
        self.gui = gui
    }
}

/// The reply to `hello`.
public struct HelloResult: Sendable, Hashable, Codable {
    public var core: CoreInfo
    public var version: String
    public var generation: Int
    public var framed: Bool
    public var methods: [String]
    public var features: [String]
    public var loginSession: LoginSession?
    public var keepsRunningAfterLogout: Bool?
    public var logoutLingerUser: String?

    public init(
        core: CoreInfo, version: String, generation: Int = 1, framed: Bool = false, methods: [String] = [],
        features: [String] = [], loginSession: LoginSession? = nil, keepsRunningAfterLogout: Bool? = nil,
        logoutLingerUser: String? = nil
    ) {
        self.core = core
        self.version = version
        self.generation = generation
        self.framed = framed
        self.methods = methods
        self.features = features
        self.loginSession = loginSession
        self.keepsRunningAfterLogout = keepsRunningAfterLogout
        self.logoutLingerUser = logoutLingerUser
    }

    private enum CodingKeys: String, CodingKey {
        case core, version, generation, framed, methods, features
        case loginSession = "login_session"
        case keepsRunningAfterLogout = "keeps_running_after_logout"
        case logoutLingerUser = "logout_linger_user"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        core = try c.decode(CoreInfo.self, forKey: .core)
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        generation = try c.decode(Int.self, forKey: .generation)
        framed = try c.decodeIfPresent(Bool.self, forKey: .framed) ?? false
        methods = try c.decodeIfPresent([String].self, forKey: .methods) ?? []
        features = try c.decodeIfPresent([String].self, forKey: .features) ?? []
        loginSession = try c.decodeIfPresent(LoginSession.self, forKey: .loginSession)
        keepsRunningAfterLogout = try c.decodeIfPresent(Bool.self, forKey: .keepsRunningAfterLogout)
        logoutLingerUser = try c.decodeIfPresent(String.self, forKey: .logoutLingerUser)
    }
}

/// Another machine this core reaches (from `terminal.list`).
public struct MachineView: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var target: String
    public var host: String
    public var version: String
    public var state: String
    public var session: String?
    public var sinceMs: Int?
    public var temporary: Bool
    public var via: Bool
    public var why: String?

    public init(
        id: String, name: String, target: String = "", host: String = "", version: String = "",
        state: String = "", session: String? = nil, sinceMs: Int? = nil, temporary: Bool = false, via: Bool = false,
        why: String? = nil
    ) {
        self.id = id
        self.name = name
        self.target = target
        self.host = host
        self.version = version
        self.state = state
        self.session = session
        self.sinceMs = sinceMs
        self.temporary = temporary
        self.via = via
        self.why = why
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, target, host, version, state, session
        case sinceMs = "since_ms"
        case temporary, via, why
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? name
        target = try c.decodeIfPresent(String.self, forKey: .target) ?? ""
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        session = try c.decodeIfPresent(String.self, forKey: .session)
        sinceMs = try c.decodeIfPresent(Int.self, forKey: .sinceMs)
        temporary = try c.decodeIfPresent(Bool.self, forKey: .temporary) ?? false
        via = try c.decodeIfPresent(Bool.self, forKey: .via) ?? false
        why = try c.decodeIfPresent(String.self, forKey: .why)
    }
}

/// All matching terminals at `seq` (the `events.subscribe` result, also carried by `missed`).
public struct Snapshot: Sendable, Hashable, Codable {
    public var seq: Int
    public var terminals: [Terminal]

    public init(seq: Int, terminals: [Terminal]) {
        self.seq = seq
        self.terminals = terminals
    }
}

/// The `terminal.list` result.
public struct TerminalList: Sendable, Hashable, Codable {
    public var terminals: [Terminal]
    public var machines: [MachineView]
    public var hiddenFinished: Int

    public init(terminals: [Terminal], machines: [MachineView] = [], hiddenFinished: Int = 0) {
        self.terminals = terminals
        self.machines = machines
        self.hiddenFinished = hiddenFinished
    }

    private enum CodingKeys: String, CodingKey {
        case terminals, machines
        case hiddenFinished = "hidden_finished"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        terminals = try c.decodeIfPresent([Terminal].self, forKey: .terminals) ?? []
        machines = try c.decodeIfPresent([MachineView].self, forKey: .machines) ?? []
        hiddenFinished = try c.decodeIfPresent(Int.self, forKey: .hiddenFinished) ?? 0
    }
}
