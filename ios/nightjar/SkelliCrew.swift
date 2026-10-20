import Foundation

/// Her crew. When the operator toggles Agents on
/// (her menu: "Agents — her crew"), an ask with
/// a plan's shape is no longer answered by one
/// pass of one mind: it is worked by a crew of
/// roles over everything she can reach.
///
/// The roles are states of one bench, not copies
/// of it — a device holds one set of weights, so
/// the Planner, the Critic and the Scribe are
/// Qwen (or Apple's model, per her mind mode)
/// wearing different briefs in turn, while the
/// Hands are her own organs, worked through the
/// same private hands her direct intents use.
/// What cooperates is the briefs and the shared
/// board: every step's outcome is written where
/// the next role can read it.
///
/// A run registers on the ProcessBoard like any
/// house process, reports its steps as it goes,
/// and obeys the hush: Vanish stops it between
/// steps, silently, like everything else.
enum SkelliCrew {
    static var enabled: Bool {
        UserDefaults.standard.bool(
            forKey: "skelli.agents")
    }

    /// Ask a bench, in the house's order: the
    /// mind mode's chosen bench first, the
    /// other as the fallback. Nil when no
    /// bench can speak at all.
    static func benchAsk(instructions: String,
                         prompt: String)
        async -> String? {
        let mode = UserDefaults.standard
            .string(forKey: "skelli.mindMode")
            ?? "council"
        #if canImport(MLXLLM)
        if mode != "apple",
           #available(iOS 17.0, *),
           SkelliWeights.canSpeak {
            if let text = await SkelliWeights.ask(
                instructions: instructions,
                prompt: prompt) {
                return text
            }
        }
        #endif
        #if canImport(FoundationModels)
        if mode != "weights",
           #available(iOS 26.0, *),
           SkelliModelBox.available {
            if let text = await SkelliModelBox.run(
                instructions: instructions,
                prompt: prompt) {
                return text
            }
        }
        #endif
        return nil
    }

    private static let plannerBrief = """
        You are the Planner in Skelli's crew, \
        aboard nightjar-hack, a network field \
        instrument. Break the operator's ask \
        into steps the house can actually work, \
        one per line, each line beginning \
        "STEP: ". Steps available: "sweep"; \
        "self scan" (read the phone's own \
        exposure); "audit" (the Bonjour audit); \
        "go dark" (EMCON on); "sitrep" (the \
        house's situation report); "look up \
        <topic>" (the app's manual); \
        "hash <text>"; "fingerprint <text>". \
        At most five steps. Order them as the \
        work wants. Nothing else: no prose, no \
        numbering — only STEP lines.
        """

    private static let criticBrief = """
        You are the Critic in Skelli's crew. \
        Given the operator's ask and the board \
        of what was worked and found, answer in \
        ONE terse line: either "SOUND" when the \
        board honestly covers the ask, or the \
        single most important gap, beginning \
        "GAP: ". Never invent results.
        """

    private static let scribeBrief = """
        You are the Scribe in Skelli's crew, and \
        you are Skelli's one voice to the \
        operator. From the ask and the board, \
        write her answer: terse, exact, plain. \
        Report only what the board holds; where \
        a step was set in motion rather than \
        finished, say so. No process talk, no \
        mention of roles, no lists unless the \
        facts demand one. A few sentences at \
        most.
        """

    /// The whole run, async: the caller (her
    /// respond chain) has already claimed the
    /// ask, and the answer arrives by say()
    /// when the work lands — the way her sweep
    /// has always reported.
    static func run(center: SkelliCenter,
                    ask: String) {
        let boardID = ProcessBoard.shared.begin(
            label: "Skelli's crew", organ: "Skelli",
            detail: "planning")
        center.activity = "The crew is planning…"
        Task {
            // The Planner.
            guard let plan = await benchAsk(
                instructions: plannerBrief,
                prompt: ask) else {
                await MainActor.run {
                    ProcessBoard.shared.end(
                        boardID,
                        .failed("no bench awake"))
                    center.say("The crew needs a "
                        + "mind awake — Apple's "
                        + "model, or weights "
                        + "downloaded in my Weights "
                        + "sheet. Without one I "
                        + "work alone, as before.")
                }
                return
            }
            let steps = plan
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(
                    in: .whitespaces) }
                .filter { $0.uppercased()
                    .hasPrefix("STEP:") }
                .map { String($0.dropFirst(5))
                    .trimmingCharacters(
                        in: .whitespaces) }
                .filter { !$0.isEmpty }
                .prefix(5)
            var board: [String] = []
            if steps.isEmpty {
                let found = await MainActor.run {
                    center.crewHands("look up " + ask)
                }
                board.append("The planner named no "
                    + "steps; the ask went to the "
                    + "manual: "
                    + (found ?? "nothing found."))
            }
            // The Hands, in order, against the
            // shared board. The hush is checked
            // between steps: a vanished crew
            // files itself away and says nothing.
            for (index, step) in steps.enumerated() {
                if center.hushed { break }
                await MainActor.run {
                    ProcessBoard.shared.update(
                        boardID,
                        detail: "step \(index + 1) "
                            + "of \(steps.count): "
                            + step)
                    center.activity =
                        "Crew step \(index + 1): "
                        + step
                }
                let found: String?
                let lowered = step.lowercased()
                if lowered.hasPrefix("hash ")
                    || lowered
                        .hasPrefix("fingerprint ") {
                    found = center.cryptoAct(step)
                } else {
                    found = await MainActor.run {
                        center.crewHands(step)
                    }
                }
                board.append("\(step) → "
                    + (found ?? "nothing in the "
                       + "house answers to that "
                       + "step."))
            }
            if center.hushed {
                await MainActor.run {
                    ProcessBoard.shared.end(
                        boardID, .stopped)
                }
                return
            }
            // The Critic.
            let boardText = board
                .enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
            var criticLine = ""
            if let verdict = await benchAsk(
                instructions: criticBrief,
                prompt: "Ask: \(ask)\nBoard:\n"
                    + boardText) {
                criticLine = verdict
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines)
            }
            // The Scribe.
            let finalBoard = boardText
                + (criticLine.isEmpty
                   ? ""
                   : "\nCritic: \(criticLine)")
            let answer = await benchAsk(
                instructions: scribeBrief,
                prompt: "Ask: \(ask)\nBoard:\n"
                    + finalBoard)
            await MainActor.run {
                ProcessBoard.shared.end(
                    boardID,
                    .done("\(board.count) step(s)"))
                center.activity = "Ready."
                if let answer, !answer
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines)
                    .isEmpty {
                    center.say(answer
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines))
                } else {
                    center.say("The crew worked "
                        + "\(board.count) step"
                        + (board.count == 1 ? "" : "s")
                        + ": "
                        + steps.joined(
                            separator: "; ")
                        + ".")
                }
            }
        }
    }
}

extension SkelliCenter {
    /// The crew's door in the respond chain:
    /// claims an ask only when the toggle is on
    /// and the ask calls for the crew itself —
    /// its name, or a plan's shape ("plan
    /// this", "step by step"). Chains joined
    /// by "then" were a trigger once; they
    /// swallowed every ordinary multi-step
    /// sentence into a crew run, and plain
    /// questions ("figure out why…") went
    /// with them. Gone 2026-10-20: a chain
    /// of asks is hers to sequence, not the
    /// crew's to eat.
    func crewAsk(_ q: String, raw: String) -> Bool {
        guard SkelliCrew.enabled else { return false }
        let triggers = ["crew", "agents",
                        "swarm", "plan this",
                        "step by step"]
        guard triggers.contains(where: {
            q.contains($0)
        }) else { return false }
        SkelliCrew.run(center: self, ask: raw)
        return true
    }
}
