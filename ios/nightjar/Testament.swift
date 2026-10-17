import SwiftUI

/// Last Testament: a message under two locks, and the second
/// lock is a silence.
///
/// The first lock is work — an RSW time capsule, in the
/// Magic Box manner: sequential squarings, unhurried by any
/// hardware. The second lock is absence: the testament will
/// not even begin the grind until the dead hand has fallen
/// and stayed down for the author's chosen span. Both locks
/// must agree. A capsule alone can be ground by anyone
/// holding it, starting now — so the testament never lets
/// its capsule go. It stays in this phone's keeping, and the
/// phone refuses the grind until the hand has fallen.
///
/// What this is, stated plainly: a message you write for a
/// world in which you have stopped checking in. What it is
/// not: a legal will, or a vault against someone holding
/// this phone and its files — the same trust the whole
/// instrument already asks.
struct Testament: Codable, Identifiable {
    var id: String
    var created: Date
    /// The author's own label — plaintext, shown in the list.
    var hint: String
    /// The time capsule blob. Nil once opened: the lock has
    /// served, and the words stand in its place.
    var blob: String?
    var grindSeconds: Double
    /// Days the hand must lie fallen before the grind may run.
    var afterFallDays: Int
    var openedAt: Date?
    var openedText: String?
}

final class TestamentStore: ObservableObject {
    static let shared = TestamentStore()

    @Published private(set) var items: [Testament] = []

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory,
                                 in: .userDomainMask)[0]
            .appendingPathComponent("testaments.json")
    }

    init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode(
                  [Testament].self, from: data)
        else { items = []; return }
        items = decoded.sorted { $0.created > $1.created }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    func add(hint: String, blob: String, grindSeconds: Double,
             afterFallDays: Int) {
        items.insert(Testament(
            id: UUID().uuidString, created: Date(), hint: hint,
            blob: blob, grindSeconds: grindSeconds,
            afterFallDays: afterFallDays,
            openedAt: nil, openedText: nil), at: 0)
        save()
        Journal.log("testament", "sealed",
                    "a testament was sealed — \u{201C}\(hint)\u{201D} — "
                    + "grind \(Int(grindSeconds))s, opens "
                    + "\(afterFallDays)d after the hand falls")
    }

    func delete(_ testament: Testament) {
        items.removeAll { $0.id == testament.id }
        save()
        Journal.log("testament", "burned",
                    "a testament was destroyed unopened — "
                    + "\u{201C}\(testament.hint)\u{201D}")
    }

    func markOpened(_ testament: Testament, text: String) {
        guard let index = items.firstIndex(
            where: { $0.id == testament.id }) else { return }
        items[index].blob = nil
        items[index].openedAt = Date()
        items[index].openedText = text
        save()
        Journal.log("testament", "opened",
                    "a testament was opened — "
                    + "\u{201C}\(testament.hint)\u{201D} — both "
                    + "locks agreed")
    }
}

enum TestamentLocks {
    /// When the dead hand fell, if it has.
    static var handFellAt: Date? {
        let t = UserDefaults.standard.double(
            forKey: "deadHand.firedAt")
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static var handArmed: Bool {
        UserDefaults.standard.bool(forKey: "deadHand.on")
    }

    /// The absence lock's verdict for one testament, in words.
    static func absenceVerdict(for testament: Testament)
        -> (open: Bool, line: String) {
        guard handArmed || handFellAt != nil else {
            return (false, "the dead hand is not armed — this "
                    + "lock can never fall")
        }
        guard let fell = handFellAt else {
            return (false, "the hand still stands — the author "
                    + "is still checking in")
        }
        let opens = fell.addingTimeInterval(
            Double(testament.afterFallDays) * 86_400)
        let fellText = fell.formatted(date: .abbreviated,
                                      time: .omitted)
        if Date() >= opens {
            return (true, "the hand fell \(fellText) and has "
                    + "stayed down")
        }
        let opensText = opens.formatted(date: .abbreviated,
                                        time: .omitted)
        return (false, "the hand fell \(fellText) — the "
                + "testament waits until \(opensText)")
    }
}

/// The Knocktalk tab's testament card.
struct TestamentSectionView: View {
    @ObservedObject var store: TestamentStore
    @State private var draft = ""
    @State private var hint = ""
    @State private var grind: Double = 600
    @State private var afterFall: Int = 7
    @State private var busy = false
    @State private var status = ""
    @State private var progress: [String: Double] = [:]
    @State private var notes: [String: String] = [:]
    @State private var controls: [String: GrindControl] = [:]

    var body: some View {
        Section(header: Text("Last Testament — two locks, one silence"),
                footer: Text("Seal a message under a time "
                    + "capsule, then lay the second lock over "
                    + "it: this phone will not grind until the "
                    + "dead hand has fallen and stayed down for "
                    + "your chosen span. Write for whoever holds "
                    + "this phone when you have stopped "
                    + "checking in. Not a legal will — a "
                    + "message with conditions.")) {
            if !TestamentLocks.handArmed {
                Label("Arm the dead hand in EMCON — without it, "
                      + "the absence lock can never fall.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }
            TextField("the testament — for whoever holds this "
                      + "phone", text: $draft, axis: .vertical)
                .lineLimit(2...5)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            TextField("a label for the list (plaintext)",
                      text: $hint)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            Picker("The grind", selection: $grind) {
                Text("a breath — 30 seconds (test it)")
                    .tag(30.0)
                Text("10 minutes of grinding").tag(600.0)
                Text("an hour of grinding").tag(3600.0)
                Text("6 hours of grinding").tag(21600.0)
            }
            Picker("After the hand falls", selection: $afterFall) {
                Text("immediately").tag(0)
                Text("7 days").tag(7)
                Text("30 days").tag(30)
                Text("90 days").tag(90)
            }
            Button {
                seal()
            } label: {
                Label(busy ? "Sealing…" : "Seal the testament",
                      systemImage: "lock.square.stack")
            }
            .disabled(draft.isEmpty || busy
                      || !TestamentLocks.handArmed)
            if !status.isEmpty {
                Text(status).font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(store.items) { testament in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(testament.hint.isEmpty
                             ? "a testament" : testament.hint)
                            .font(.callout.weight(.semibold))
                        Spacer()
                        Text(testament.created.formatted(
                            date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let text = testament.openedText {
                        Text(text).font(.callout)
                        Text("opened — both locks agreed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(TestamentLocks.absenceVerdict(
                            for: testament).line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let value = progress[testament.id] {
                            ProgressView(value: value)
                            Button("Stop grinding") {
                                controls[testament.id]?.cancelled
                                    = true
                            }
                            .font(.caption)
                        } else {
                            HStack {
                                Button("Attempt to open") {
                                    attempt(testament)
                                }
                                .font(.callout)
                                Spacer()
                                Button("Burn", role: .destructive) {
                                    store.delete(testament)
                                }
                                .font(.callout)
                            }
                        }
                        if let note = notes[testament.id] {
                            Text(note).font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func seal() {
        let text = draft
        let label = hint.trimmingCharacters(in: .whitespaces)
        let grindSeconds = grind
        let days = afterFall
        busy = true
        status = "Forging the lock…"
        DispatchQueue.global(qos: .userInitiated).async {
            let blob = TimeCapsule.seal(
                message: text, seconds: grindSeconds,
                suite: Knocktalk.suiteChaCha) { line in
                DispatchQueue.main.async { status = line }
            }
            DispatchQueue.main.async {
                busy = false
                status = ""
                if let blob {
                    store.add(hint: label, blob: blob,
                              grindSeconds: grindSeconds,
                              afterFallDays: days)
                    draft = ""
                    hint = ""
                } else {
                    status = "The sealing failed — try again."
                }
            }
        }
    }

    private func attempt(_ testament: Testament) {
        guard let blob = testament.blob else { return }
        let verdict = TestamentLocks.absenceVerdict(for: testament)
        guard verdict.open else {
            notes[testament.id] = "Refused: " + verdict.line + "."
            Journal.log("testament", "attempt",
                        "an opening was refused — \(verdict.line)")
            return
        }
        let control = GrindControl()
        controls[testament.id] = control
        progress[testament.id] = 0
        notes[testament.id] = "Both locks agree. Grinding — "
            + "the squarings are sequential; that is the lock "
            + "working."
        DispatchQueue.global(qos: .userInitiated).async {
            TimeCapsule.grind(
                blob: blob, control: control,
                progress: { value in
                    DispatchQueue.main.async {
                        progress[testament.id] = value
                    }
                },
                completion: { text in
                    DispatchQueue.main.async {
                        progress[testament.id] = nil
                        if control.cancelled {
                            notes[testament.id] = "Grind "
                                + "stopped. The testament "
                                + "keeps — the work restarts "
                                + "from the first squaring."
                        } else if let text {
                            store.markOpened(testament, text: text)
                            notes[testament.id] = nil
                        } else {
                            notes[testament.id] = "The grind "
                                + "finished and the testament "
                                + "would not open — its capsule "
                                + "is corrupt."
                        }
                    }
                })
        }
    }
}
