import Foundation

/// One fact change about one terminal (`event` notification).
public struct CoreEvent: Sendable, Hashable, Decodable {
    public var seq: Int
    /// The terminal's address, `t3` or `machine/t4`.
    public var terminal: String
    public var kind: EventKind

    public init(seq: Int, terminal: String, kind: EventKind) {
        self.seq = seq
        self.terminal = terminal
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case seq, terminal, type, data
    }

    private struct StatusData: Decodable {
        var status: TerminalStatus?
        var reported: Bool?
    }

    private struct TurnData: Decodable {
        var turn: Int
        var state: StatusWord?
    }

    private struct TitleData: Decodable {
        var title: String
    }

    private struct LabelsData: Decodable {
        var labels: [String: String]
    }

    private struct FinishedData: Decodable {
        var exitCode: Int?
        var finishedMs: Int?
        var reason: String?
        var signal: Int?

        private enum CodingKeys: String, CodingKey {
            case exitCode = "exit_code"
            case finishedMs = "finished_ms"
            case reason, signal
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seq = try c.decode(Int.self, forKey: .seq)
        terminal = try c.decode(String.self, forKey: .terminal)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "created":
            var created = try c.decode(Terminal.self, forKey: .data)
            created.address = terminal
            kind = .created(created)
        case "status":
            let data = try c.decode(StatusData.self, forKey: .data)
            kind = .status(data.status, reported: data.reported ?? (data.status != nil))
        case "turn":
            let data = try c.decode(TurnData.self, forKey: .data)
            kind = .turn(data.turn, state: data.state)
        case "title":
            kind = .title(try c.decode(TitleData.self, forKey: .data).title)
        case "labels":
            kind = .labels(try c.decode(LabelsData.self, forKey: .data).labels)
        case "foreground":
            let foreground = try c.decodeIfPresent(Foreground.self, forKey: .data)
            kind = .foreground(foreground == Foreground() ? nil : foreground)
        case "finished":
            let data = try c.decodeIfPresent(FinishedData.self, forKey: .data)
            kind = .finished(
                exitCode: data?.exitCode, reason: data?.reason, finishedMs: data?.finishedMs, signal: data?.signal)
        case "removed": kind = .removed
        case "lost": kind = .lost
        case "restarted": kind = .restarted
        default: kind = .other(type: type)
        }
    }
}

public enum EventKind: Sendable, Hashable {
    case created(Terminal)
    /// A new status (nil when cleared); the event carries no timestamp, so reducers stamp the receive time.
    case status(TerminalStatus?, reported: Bool)
    case turn(Int, state: StatusWord?)
    case title(String)
    /// The complete label set, replacing the previous one.
    case labels([String: String])
    case foreground(Foreground?)
    case finished(exitCode: Int?, reason: String?, finishedMs: Int?, signal: Int?)
    case removed
    case lost
    case restarted
    /// A type this client does not interpret (`keep`, `size`, `doc`, future ones).
    case other(type: String)
}

/// What arrives on a subscription after the snapshot.
public enum CoreNotification: Sendable, Hashable {
    case event(CoreEvent)
    case heartbeat(seq: Int)
    /// The subscriber fell behind. With a snapshot, replace all state with it; without, resubscribe.
    case missed(Snapshot?)

    /// Decodes a raw notification; nil for methods this client does not know.
    public init?(_ notification: JSONRPCNotification) throws(CoreError) {
        switch notification.method {
        case "event":
            guard let event = try notification.params(as: CoreEvent.self) else {
                throw .invalidResponse("event without params")
            }
            self = .event(event)
        case "heartbeat":
            self = .heartbeat(seq: (try? notification.params(as: HeartbeatParams.self))??.seq ?? 0)
        case "missed":
            self = .missed((try? notification.params(as: Snapshot.self)) ?? nil)
        default:
            return nil
        }
    }

    private struct HeartbeatParams: Decodable {
        var seq: Int?
    }
}
