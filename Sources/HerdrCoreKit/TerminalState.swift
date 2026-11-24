import Foundation

/// All known terminals at an event sequence number. A pure reducer over snapshots and events.
public struct TerminalState: Sendable, Hashable {
    public private(set) var seq: Int
    public private(set) var terminals: [String: Terminal]

    public init(seq: Int = 0, terminals: [String: Terminal] = [:]) {
        self.seq = seq
        self.terminals = terminals
    }

    public init(snapshot: Snapshot) {
        self.init()
        apply(snapshot: snapshot)
    }

    /// Replaces everything with a snapshot (initial subscribe or `missed`).
    public mutating func apply(snapshot: Snapshot) {
        seq = snapshot.seq
        terminals = Dictionary(snapshot.terminals.map { ($0.address, $0) }, uniquingKeysWith: { _, last in last })
    }

    /// Applies one event. Returns false, changing nothing, when `event.seq` is not newer than `seq`.
    /// `now` (Unix milliseconds) stamps `statusMs`, which status events do not carry.
    @discardableResult
    public mutating func apply(_ event: CoreEvent, now: Int) -> Bool {
        guard event.seq > seq else { return false }
        seq = event.seq
        let address = event.terminal
        if case .created(var terminal) = event.kind {
            terminal.address = address
            terminals[address] = terminal
            return true
        }
        if case .removed = event.kind {
            terminals[address] = nil
            return true
        }
        guard var terminal = terminals[address] else { return true }
        switch event.kind {
        case .status(let status, let reported):
            terminal.status = status
            terminal.reported = reported
            terminal.statusMs = now
        case .turn(let turn, _):
            terminal.turn = turn
        case .title(let title):
            terminal.title = title
        case .labels(let labels):
            terminal.labels = labels
        case .foreground(let foreground):
            terminal.foreground = foreground
        case .finished(let exitCode, let reason, let finishedMs, let signal):
            terminal.lifecycle = .finished
            terminal.exitCode = exitCode
            terminal.reason = reason
            terminal.finishedMs = finishedMs
            terminal.signal = signal
        case .lost:
            terminal.isLost = true
        case .restarted:
            terminal.isLost = false
            terminal.lifecycle = .live
        case .created, .removed, .other:
            break
        }
        terminals[address] = terminal
        return true
    }

    public subscript(address: String) -> Terminal? { terminals[address] }

    public var isEmpty: Bool { terminals.isEmpty }

    /// Local terminals first, then by machine; within a machine by terminal number (`t2` before `t10`).
    public var sorted: [Terminal] { terminals.values.sorted(by: Terminal.addressOrder) }

    /// Most urgent first, ties broken by address order.
    public var sortedByAttention: [Terminal] {
        terminals.values.sorted { lhs, rhs in
            let (left, right) = (lhs.attention.urgency, rhs.attention.urgency)
            return left != right ? left > right : Terminal.addressOrder(lhs, rhs)
        }
    }
}

extension Terminal {
    static func addressOrder(_ lhs: Terminal, _ rhs: Terminal) -> Bool {
        let (left, right) = (TerminalAddress(lhs.address), TerminalAddress(rhs.address))
        if left.machine != right.machine {
            guard let leftMachine = left.machine else { return true }
            guard let rightMachine = right.machine else { return false }
            return leftMachine.localizedStandardCompare(rightMachine) == .orderedAscending
        }
        if let leftNumber = left.number, let rightNumber = right.number, leftNumber != rightNumber {
            return leftNumber < rightNumber
        }
        return left.id < right.id
    }
}
