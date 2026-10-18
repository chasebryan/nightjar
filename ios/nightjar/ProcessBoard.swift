import SwiftUI

/// The board: every process in the house, on one
/// register — what is running, under whose hand, for
/// how long, and how each finished thing landed. It
/// is how the operator knows from ANY screen that a
/// sweep is still out, that the trace came home, that
/// a macro stopped short — without walking to the
/// room where it began.
///
/// Processes register when they start and report
/// when they end. An announced ending speaks on the
/// system channel — a process toast and the finish
/// haptic — from wherever the operator happens to
/// be; quiet endings (a knock inside a macro, a fuzz
/// run) stay on the board for the eyes only, so the
/// house never narrates its own ingredients.
final class ProcessBoard: ObservableObject {
    static let shared = ProcessBoard()

    /// Wired at launch, like every organ's toast line.
    var toasts: ToastCenter?

    /// The hush: while the house is vanished, the
    /// board still files everything — it simply does
    /// not speak or buzz about any of it. Skelli sets
    /// it when she vanishes and lifts it when the
    /// operator next speaks to her.
    var muted = false

    enum Outcome {
        case done(String)
        case failed(String)
        case stopped
    }

    struct Entry: Identifiable {
        let id: UUID
        var key: String?
        let label: String
        let organ: String
        let started: Date
        var detail: String
        let announce: Bool
        var stop: (() -> Void)?
    }

    struct Finished: Identifiable {
        let id = UUID()
        let label: String
        let summary: String
        let failed: Bool
        let stopped: Bool
        let seconds: Double
        let at: Date
    }

    @Published private(set) var active: [Entry] = []
    @Published private(set) var recent: [Finished] = []

    // MARK: register

    @discardableResult
    func begin(label: String, organ: String,
               detail: String = "", announce: Bool = true,
               stop: (() -> Void)? = nil) -> UUID {
        let entry = Entry(id: UUID(), key: nil,
                          label: label, organ: organ,
                          started: Date(), detail: detail,
                          announce: announce, stop: stop)
        active.append(entry)
        if announce && !muted { Haptics.start() }
        return entry.id
    }

    /// For organs that cannot hold a token of their
    /// own: one live entry per key — a new beginning
    /// under a key quietly retires the old entry.
    @discardableResult
    func beginKeyed(_ key: String, label: String,
                    organ: String, detail: String = "",
                    announce: Bool = true,
                    stop: (() -> Void)? = nil) -> UUID {
        if let old = active.first(where: { $0.key == key }) {
            active.removeAll { $0.id == old.id }
        }
        let id = begin(label: label, organ: organ,
                       detail: detail, announce: announce,
                       stop: stop)
        if let index = active.firstIndex(
            where: { $0.id == id }) {
            active[index].key = key
        }
        return id
    }

    func update(_ id: UUID, detail: String) {
        guard let index = active.firstIndex(
            where: { $0.id == id }) else { return }
        active[index].detail = detail
    }

    // MARK: report

    func end(_ id: UUID, _ outcome: Outcome) {
        guard let index = active.firstIndex(
            where: { $0.id == id }) else { return }
        let entry = active.remove(at: index)
        file(entry, outcome, speak: entry.announce)
    }

    func endKeyed(_ key: String, _ outcome: Outcome) {
        guard let entry = active.first(
            where: { $0.key == key }) else { return }
        end(entry.id, outcome)
    }

    /// The backstop, for Vanish: anything still on
    /// the board after every organ has stood down is
    /// filed as stopped, silently — the vanish already
    /// spoke for itself.
    func endAllQuietly() {
        let leftovers = active
        active.removeAll()
        for entry in leftovers {
            file(entry, .stopped, speak: false)
        }
    }

    private func file(_ entry: Entry, _ outcome: Outcome,
                      speak: Bool) {
        let audible = speak && !muted
        let summary: String
        var failed = false
        var stopped = false
        switch outcome {
        case .done(let text): summary = text
        case .failed(let text):
            summary = text
            failed = true
        case .stopped:
            summary = "Stopped"
            stopped = true
        }
        recent.insert(Finished(
            label: entry.label, summary: summary,
            failed: failed, stopped: stopped,
            seconds: Date().timeIntervalSince(entry.started),
            at: Date()), at: 0)
        if recent.count > 12 {
            recent.removeLast(recent.count - 12)
        }
        guard audible else { return }
        switch outcome {
        case .done:
            toasts?.show("\(entry.label) — \(summary)",
                         kind: .process)
            Haptics.finish()
        case .failed:
            toasts?.show("\(entry.label) — \(summary)",
                         error: true)
            Haptics.error()
        case .stopped:
            toasts?.show("\(entry.label) stopped",
                         kind: .info)
            Haptics.pulse()
        }
    }
}

/// The strip that rides under the toasts on every
/// screen while anything runs: a breathing green
/// light, a count, the senior process's name. One
/// tap opens the board itself.
struct ProcessStripView: View {
    @ObservedObject var board: ProcessBoard
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 7) {
                Image(systemName: "record.circle")
                    .foregroundStyle(Color(red: 0.3,
                                           green: 0.95,
                                           blue: 0.4))
                    .symbolEffect(.pulse,
                                  options: .repeating)
                Text("\(board.active.count) running")
                    .font(.caption.weight(.semibold))
                if let first = board.active.first {
                    Text(first.label)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(
                Color(white: 0.16).opacity(0.95)))
            .shadow(radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
}

/// The board itself: what is running (with a stop
/// for anything stoppable) and what has lately
/// finished, and how it landed.
struct ProcessBoardView: View {
    @ObservedObject private var board = ProcessBoard.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !board.active.isEmpty {
                    Section("Running") {
                        ForEach(board.active) { entry in
                            VStack(alignment: .leading,
                                   spacing: 3) {
                                HStack {
                                    Text(entry.label)
                                        .font(.body
                                            .weight(.semibold))
                                    Spacer()
                                    Text(entry.started,
                                         style: .timer)
                                        .font(.callout
                                            .monospacedDigit())
                                        .foregroundStyle(
                                            .secondary)
                                }
                                Text(entry.organ)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !entry.detail.isEmpty {
                                    Text(entry.detail)
                                        .font(.caption)
                                }
                                if let stop = entry.stop {
                                    Button("Stop",
                                           role: .destructive) {
                                        stop()
                                    }
                                    .font(.callout
                                        .weight(.semibold))
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                if !board.recent.isEmpty {
                    Section("Finished") {
                        ForEach(board.recent) { item in
                            HStack(spacing: 10) {
                                Image(systemName: item.failed
                                      ? "xmark.octagon.fill"
                                      : item.stopped
                                      ? "hand.raised.fill"
                                      : "checkmark.seal.fill")
                                    .foregroundStyle(item.failed
                                        ? .red
                                        : item.stopped
                                        ? .secondary
                                        : .green)
                                VStack(alignment: .leading,
                                       spacing: 2) {
                                    Text(item.label)
                                        .font(.body
                                            .weight(.medium))
                                    Text(item.summary)
                                        .font(.caption)
                                        .foregroundStyle(
                                            .secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing,
                                       spacing: 2) {
                                    Text("\(Int(item.seconds))s")
                                        .font(.caption
                                            .monospacedDigit())
                                    Text(item.at,
                                         style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(
                                            .secondary)
                                }
                            }
                        }
                    }
                }
                if board.active.isEmpty && board.recent.isEmpty {
                    Text("Nothing is running, and nothing "
                         + "has finished lately — the "
                         + "house is quiet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("On the board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
