import HerdrCoreKit
import SwiftUI

/// "Needs you", then terminals by machine and space.
struct TerminalListView: View {
    let sections: TerminalSections
    let now: Date
    var selection: String?
    var openingAddress: String?
    var onHover: (String) -> Void = { _ in }
    var onOpen: (Terminal) -> Void = { _ in }

    private var showsMachineHeaders: Bool { sections.machines.contains { !$0.isLocal } }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !sections.attention.isEmpty {
                SectionHeader(
                    title: "Needs You", symbol: "bell.badge.fill", tint: Theme.blocked,
                    count: sections.attention.count)
                ForEach(sections.attention) { terminal in
                    row(terminal, context: .attention)
                }
            }
            ForEach(sections.machines) { machine in
                if showsMachineHeaders {
                    MachineHeader(machine: machine)
                        .padding(.top, 8)
                } else if !sections.attention.isEmpty {
                    Spacer().frame(height: 8)
                }
                ForEach(machine.spaces) { space in
                    SpaceHeader(name: space.name, count: space.terminals.count)
                    ForEach(space.terminals) { terminal in
                        row(terminal, context: .grouped)
                    }
                }
            }
        }
    }

    private func row(_ terminal: Terminal, context: TerminalRow.Context) -> some View {
        TerminalRowButton(
            terminal: terminal, context: context, now: now, isSelected: selection == terminal.address,
            isBusy: openingAddress == terminal.address, onHover: onHover, onOpen: onOpen
        )
        .id(terminal.address)
    }
}

/// A row with hover, click and context menu wired up.
private struct TerminalRowButton: View {
    let terminal: Terminal
    let context: TerminalRow.Context
    let now: Date
    let isSelected: Bool
    let isBusy: Bool
    let onHover: (String) -> Void
    let onOpen: (Terminal) -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        TerminalRow(terminal: terminal, context: context, now: now, isSelected: isSelected, isBusy: isBusy)
            .onHover { inside in if inside { onHover(terminal.address) } }
            .onTapGesture { onOpen(terminal) }
            .help(terminal.displayTitle)
            .contextMenu { menu }
            .accessibilityAction { onOpen(terminal) }
            .accessibilityAction(named: "Mark as Read") { Task { await model.markRead(terminal) } }
            .accessibilityAction(named: "Copy Address") { model.copyAddress(terminal) }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Open in Herdr", systemImage: "arrow.up.forward.app") { onOpen(terminal) }
        Button("Mark as Read", systemImage: "checkmark.circle") { Task { await model.markRead(terminal) } }
            .disabled(!terminal.isUnreadDone)
        Divider()
        Button("Copy Address", systemImage: "doc.on.doc") { model.copyAddress(terminal) }
        Button("Copy Working Directory", systemImage: "folder") { model.copyWorkingDirectory(terminal) }
            .disabled(terminal.workingDirectory.isEmpty)
        if terminal.machine == nil {
            Button("Reveal in Finder", systemImage: "finder") { model.revealWorkingDirectory(terminal) }
                .disabled(terminal.workingDirectory.isEmpty)
        }
    }
}

struct SectionHeader: View {
    let title: String
    let symbol: String
    var tint: Color = .secondary
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: count)
            Text(title)
            CountBadge(count: count, tint: tint)
            Spacer()
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(.isHeader)
    }
}

struct MachineHeader: View {
    let machine: TerminalSections.Machine

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: machine.isLocal ? "laptopcomputer" : "desktopcomputer")
                .foregroundStyle(.secondary)
                .overlay(alignment: .bottomTrailing) {
                    if !machine.isLocal {
                        Image(systemName: "network")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.working)
                            .background(Circle().fill(.background).padding(-1.5))
                            .offset(x: 4, y: 3)
                    }
                }
                .padding(.trailing, machine.isLocal ? 0 : 3)
            Text(machine.name ?? "This Mac")
            CountBadge(count: machine.count)
            Spacer()
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(machine.isLocal ? "This Mac" : "Remote machine \(machine.name ?? "")"), \(machine.count)"
        )
        .accessibilityAddTraits(.isHeader)
    }
}

struct SpaceHeader: View {
    let name: String
    let count: Int

    var body: some View {
        Text(name)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .accessibilityLabel("Space \(name), \(count)")
            .accessibilityAddTraits(.isHeader)
    }
}

struct CountBadge: View {
    let count: Int
    var tint: Color = .secondary

    var body: some View {
        Text(count, format: .number)
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(0.14)))
            .contentTransition(.numericText(value: Double(count)))
    }
}
