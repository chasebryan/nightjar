import Foundation
import Network

/// Her working hands, callable from conversation:
/// the forge and the weights bench. These live in
/// their own file because Feedback.swift and
/// Skelli.swift both sit at the connector's push
/// ceiling — new bulk lands here.

// MARK: - The late gate: the forge and the bench

/// Hands outside her pattern cascade get their
/// chance here — after every pattern, before the
/// semantic reading.
extension SkelliCenter {

    /// The imperative hands alone — tried before
    /// the manual, so an order is performed, not
    /// taught. Questions never reach it as orders:
    /// the cascade's question lanes run earlier.
    func handsGate(_ q: String, raw: String) -> Bool {
        if shapeDropAsk(q) { return true }
        if deleteAsk(q) { return true }
        // Macros are NOT gated here: macroAsk runs in
        // respond() ahead of the single-action intents,
        // because a build's steps carry those intents'
        // verbs inside them and the intents would claim
        // the sentence for its last verb alone.
        if forgeAsk(q, raw: raw) { return true }
        // The war rooms before the weights bench: the
        // bench's verbs are the fuzziest in the house
        // ("use the …"), and a room's name should never
        // be mistaken for a model.
        if warAsk(q) { return true }
        if vaultAsk(q, raw: raw) { return true }
        if weightsAsk(q) { return true }
        return false
    }

    /// Score a candidate name against the words: every word
    /// of the name (3+ characters) the ask carries adds one.
    func warNameScore(_ name: String, in q: String) -> Int {
        let words = name.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        return words.filter { $0.count >= 3 && q.contains($0) }
            .count
    }

    /// This phone's wire name, first label.
    func warHostName() -> String {
        let name = Mouth.wireHostName()
        return name.isEmpty ? "this phone" : name
    }

    /// The War Room's configuration, from the same stored
    /// keys the rooms themselves read.
    func warRoomConfig() -> WarConfig {
        let d = UserDefaults.standard
        func ports(_ text: String) -> [Int] {
            Array(Set(text.split(separator: ",").compactMap {
                Int($0.trimmingCharacters(in: .whitespaces))
            }.filter { (1...65535).contains($0) })).sorted()
        }
        return WarConfig(
            scopeText: d.string(forKey: "traceScope") ?? "",
            discoveryPorts: ports(d.string(
                forKey: "traceDiscoveryPorts")
                ?? "80,443,22,445,1883,8080,8443,9100"),
            profilePorts: ports(d.string(
                forKey: "traceProfilePorts") ?? ""),
            includeBonjour: (d.object(forKey: "traceBonjour")
                             as? Bool) ?? true,
            adaptive: (d.object(forKey: "traceAdaptive")
                       as? Bool) ?? true,
            rulesText: d.string(forKey: "traceRules") ?? "",
            includeBLE: true,
            knockTimeout: (d.object(forKey: "reconTimeout")
                           as? Double) ?? 1.5,
            knockJobs: Int((d.object(forKey: "reconJobs")
                            as? Double) ?? 24))
    }

    /// The Recon bench's port list, from its stored key —
    /// one fallback for every reader: the bench's own
    /// default set, so no surface invents its own list.
    func warReconPorts() -> [Int] {
        guard let text = UserDefaults.standard.string(
                forKey: "reconPorts"), !text.isEmpty
        else { return ReconPayloads.defaultPorts }
        return Array(Set(text.split(separator: ",")
            .compactMap {
                Int($0.trimmingCharacters(in: .whitespaces))
            }.filter { (1...65535).contains($0) })).sorted()
    }

    func warReconUDP() -> Bool {
        (UserDefaults.standard.object(forKey: "reconKnockUDP")
         as? Bool) ?? false
    }

    /// Serve's doors as the settings hold them — the
    /// defender's real doors for a War Games card.
    func warServeDoors() -> [WarDoor] {
        let d = UserDefaults.standard
        func flag(_ key: String, _ fallback: Bool) -> Bool {
            (d.object(forKey: key) as? Bool) ?? fallback
        }
        func port(_ key: String, _ fallback: String) -> Int {
            Int(d.string(forKey: key) ?? fallback) ?? 0
        }
        var doors: [WarDoor] = []
        if flag("serveUseTCP", true) {
            doors.append(WarDoor(
                port: port("serveTcpPort", "9000"),
                proto: "tcp", service: "custom",
                confirmed: false))
        }
        if flag("serveUseUDP", false) {
            doors.append(WarDoor(
                port: port("serveUdpPort", "9001"),
                proto: "udp", service: "custom",
                confirmed: false))
        }
        if flag("serveUseHTTP", false) {
            doors.append(WarDoor(
                port: port("serveHttpPort", "8080"),
                proto: "tcp", service: "http",
                confirmed: false))
        }
        return doors.filter { $0.port > 0 }
    }

    /// The defender's decoys, parsed the way the War
    /// Games room parses them.
    func warParseDecoys() -> [String] {
        let text = UserDefaults.standard.string(
            forKey: "warGamesDecoys") ?? ""
        var seen = Set<String>()
        var out: [String] = []
        for part in text.split(whereSeparator: {
            $0 == "," || $0 == ";" || $0 == "\n"
        }) {
            let clean = part.trimmingCharacters(
                in: .whitespaces).lowercased()
            if !clean.isEmpty, seen.insert(clean).inserted {
                out.append(clean)
            }
        }
        return Array(out.prefix(12))
    }

    // MARK: - Macro hands

    /// Macros, by voice: run, stop, list, delete —
    /// and build them from the operator's dictated
    /// steps. The same MacroStore and MacroRunner the
    /// Macros tab drives; nothing here is a second
    /// system.
    /// The voice run, shared by both of
    /// macroAsk's doors: readiness spoken
    /// plainly, then the runner takes it —
    /// one initiation, and the playlist
    /// runs itself out.
    private func runMacroByVoice(_ target: Macro)
        -> Bool {
        let runner = MacroRunner.shared
        if runner.running {
            say("“\(runner.currentMacroName)” is "
                + "already running — stop it first.")
            return true
        }
        guard let mouth = mouth, let post = post,
              let emcon = emcon else { return false }
        let book = PayloadBook()
        let problems = MacroValidator.problems(
            in: target, book: book)
        guard problems.isEmpty else {
            say("“\(target.name)” is not ready: "
                + problems[0])
            return true
        }
        if NetbombFuse.shared.task != nil {
            say("The Netbomb is already counting "
                + "down — say stop, or let it drop.")
            return true
        }
        if target.name == "Atomic Netbomb" {
            lightNetbombFuse(target)
            return true
        }
        runner.run(target, mouth: mouth, post: post,
                   emcon: emcon, book: book)
        say("Running “\(target.name)” — "
            + "\(target.blocks.count) blocks.")
        return true
    }

    /// The bomb gets a countdown: when she
    /// drops the Atomic Netbomb by voice, she
    /// counts it down step by step before the
    /// first block fires (the operator's
    /// order, 2026-10-18). Say stop anywhere
    /// in the count and it stays in the rack.
    private func lightNetbombFuse(_ target: Macro) {
        say("Atomic Netbomb. Counting down — "
            + "say stop and it stays in the rack.")
        NetbombFuse.shared.task = Task { @MainActor in
            for step in stride(from: 5, through: 1,
                               by: -1) {
                try? await Task.sleep(
                    nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                say("\(step)…")
            }
            try? await Task.sleep(
                nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            NetbombFuse.shared.task = nil
            let runner = MacroRunner.shared
            guard !runner.running,
                  let mouth = mouth, let post = post,
                  let emcon = emcon else {
                say("The drop is off — the floor "
                    + "isn't clear.")
                return
            }
            runner.run(target, mouth: mouth,
                       post: post, emcon: emcon,
                       book: PayloadBook())
            say("Dropping it — “Atomic Netbomb” "
                + "running, "
                + "\(target.blocks.count) blocks.")
        }
    }

    /// The run's own report: "what did we
    /// discover with the atomic netbomb" is a
    /// question about a run, not a research
    /// prompt — asked mid-run in the field
    /// (2026-10-18) it fell through to web
    /// research and came back as a history
    /// essay about the actual bomb. The lane
    /// answers from the runner: still running
    /// (with the live step) or the last run's
    /// own summary. A name must match by the
    /// front door's rule, and a summary is
    /// only quoted for the macro it names —
    /// anything else falls through untouched.
    private func runReport(_ q: String) -> String? {
        let strong = ["what did", "what have",
                      "discover", "findings",
                      "results", "what happened"]
        let runner = MacroRunner.shared
        let asksReport = strong.contains {
            q.contains($0)
        }
        let asksStatus = q.contains("how is")
            || q.contains("how did")
        guard asksReport
                || (runner.running && asksStatus)
        else { return nil }
        let named = MacroStore.load().filter { macro in
            let hits = macro.name.lowercased()
                .split {
                    !$0.isLetter && !$0.isNumber
                }
                .map(String.init)
                .filter {
                    $0.count >= 3 && q.contains($0)
                }
            return hits.count >= 2
                || hits.contains { $0.count >= 7 }
        }.max(by: {
            warNameScore($0.name, in: q)
                < warNameScore($1.name, in: q)
        })
        if runner.running {
            guard named == nil
                    || named?.name
                        == runner.currentMacroName
            else { return nil }
            return "Still running — "
                + "\(runner.currentMacroName): "
                + "\(runner.currentStep)."
        }
        if let named,
           runner.lastSummary.hasPrefix(named.name) {
            return "Last run — "
                + runner.lastSummary
        }
        return nil
    }

    func macroAsk(_ q: String, raw: String) -> Bool {
        // A lit fuse answers to stop before
        // anything else in the room: while
        // she counts the Netbomb down, "stop"
        // (or abort, cancel, never mind)
        // calls the drop off.
        if NetbombFuse.shared.task != nil,
           q.contains("stop") || q.contains("abort")
            || q.contains("cancel")
            || q.contains("halt")
            || q.contains("never mind") {
            NetbombFuse.shared.task?.cancel()
            NetbombFuse.shared.task = nil
            say("Called off — the Netbomb stays "
                + "in the rack.")
            return true
        }
        if let report = runReport(q) {
            DevLog.event("skelli",
                         "run report answered")
            say(report)
            return true
        }
        if !q.contains("macro") {
            // The named front door (the
            // operator's order, 2026-10-18): a
            // run order that names a macro in
            // the library needs no word
            // "macro" — "run the atomic
            // netbomb" is the whole
            // initiation. Two of the name's
            // words must land — or one long
            // coined word, "netbomb", which
            // is a name by itself — so a
            // stray "test" never fires a
            // playlist, and questions stay
            // questions.
            if q.contains("when did")
                || q.contains("when was")
                || q.hasPrefix("when ")
                || q.hasPrefix("how ")
                || q.hasPrefix("what ") {
                return false
            }
            // Any initiation verb opens a
            // stocked macro by name — run,
            // launch, initiate, engage; the
            // operator's word for "begin"
            // is the house's too (his order,
            // 2026-10-18).
            let initiations = ["run", "play", "start",
                               "launch", "initiate",
                               "engage", "commence",
                               "deploy", "trigger",
                               "unleash", "execute",
                               "begin", "kick off"]
            guard initiations.contains(
                where: { q.contains($0) })
            else { return false }
            let macros = MacroStore.load()
            let named = macros.filter { macro in
                let hits = macro.name.lowercased()
                    .split {
                        !$0.isLetter && !$0.isNumber
                    }
                    .map(String.init)
                    .filter {
                        $0.count >= 3 && q.contains($0)
                    }
                return hits.count >= 2
                    || hits.contains { $0.count >= 7 }
            }
            guard let target = named.max(by: {
                warNameScore($0.name, in: q)
                    < warNameScore($1.name, in: q)
            }) else { return false }
            return runMacroByVoice(target)
        }
        // A question ABOUT a macro is not a
        // macro command: "when did a macro last
        // run" must never reach the run branch
        // below, which keys on the word "run".
        // Her memory lane answers those.
        if q.contains("when did")
            || q.contains("when was")
            || q.hasPrefix("when ") {
            return false
        }
        let runner = MacroRunner.shared

        if q.contains("status") || q.contains("how is the macro")
            || q.contains("macro doing") {
            if runner.running {
                say("Running “\(runner.currentMacroName)” — "
                    + "\(runner.currentStep).")
            } else if !runner.lastSummary.isEmpty {
                say("No macro is running. Last run: "
                    + runner.lastSummary)
            } else {
                say("No macro is running, and none has run "
                    + "yet this session.")
            }
            return true
        }

        if q.contains("delete") || q.contains("forget")
            || q.contains("remove") {
            var macros = MacroStore.load()
            guard let target = bestMacro(in: q, from: macros)
            else {
                say(macros.isEmpty
                    ? "There are no macros to delete."
                    : "Which macro? The library holds: "
                        + macroNames(macros) + ".")
                return true
            }
            macros.removeAll { $0.id == target.id }
            MacroStore.save(macros)
            Journal.log("macro", "deleted",
                        "“\(target.name)” deleted by voice")
            say("Deleted “\(target.name)”.")
            return true
        }

        if q.contains("list") || q.contains("what macros")
            || q.contains("which macros")
            || q.contains("show me the macros") {
            let macros = MacroStore.load()
            if macros.isEmpty {
                say("No macros yet. Dictate the steps — "
                    + "“build a macro called Night Post: "
                    + "go dark; wait 30; sweep” — and I "
                    + "will build it.")
            } else {
                say("The library: " + macros.map {
                    "“\($0.name)” (\($0.blocks.count) block"
                    + ($0.blocks.count == 1 ? "" : "s") + ")"
                }.joined(separator: ", ") + ".")
            }
            return true
        }

        if q.contains("build") || q.contains("make")
            || q.contains("create") || q.contains("new macro") {
            buildMacro(q, raw: raw)
            return true
        }

        if q.contains("add") && q.contains(" to ") {
            addStepToMacro(q)
            return true
        }

        if q.contains("stop") || q.contains("halt") {
            if runner.running {
                let name = runner.currentMacroName
                runner.stop()
                say("Stopped “\(name)”.")
            } else {
                say("No macro is running.")
            }
            return true
        }

        if q.contains("run") || q.contains("play")
            || q.contains("start") {
            guard let mouth = mouth, let post = post,
                  let emcon = emcon else { return false }
            if runner.running {
                say("“\(runner.currentMacroName)” is "
                    + "already running — stop it first.")
                return true
            }
            let macros = MacroStore.load()
            guard let target = bestMacro(in: q, from: macros)
            else {
                say(macros.isEmpty
                    ? "There are no macros to run yet."
                    : "Which macro? The library holds: "
                        + macroNames(macros) + ".")
                return true
            }
            return runMacroByVoice(target)
        }
        return false
    }

    private func macroNames(_ macros: [Macro]) -> String {
        macros.map { "“\($0.name)”" }
            .joined(separator: ", ")
    }

    private func bestMacro(in q: String,
                           from macros: [Macro]) -> Macro? {
        macros
            .map { ($0, warNameScore($0.name, in: q)) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?.0
    }

    // MARK: building from dictated steps

    private func buildMacro(_ q: String, raw: String) {
        let book = PayloadBook()
        var macros = MacroStore.load()

        // The name, in the operator's own case.
        var name = ""
        let lowerRaw = raw.lowercased()
        for marker in ["called ", "named "] {
            if let range = lowerRaw.range(of: marker) {
                var tail = String(raw[range.upperBound...])
                if let cut = tail.firstIndex(of: ":") {
                    tail = String(tail[..<cut])
                }
                if let cut = tail.firstIndex(of: ",") {
                    tail = String(tail[..<cut])
                }
                name = tail.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                if !name.isEmpty { break }
            }
        }
        if name.isEmpty {
            var n = macros.count + 1
            name = "Field Macro \(n)"
            while macros.contains(where: { $0.name == name }) {
                n += 1
                name = "Field Macro \(n)"
            }
        }

        // Dressing, from the preamble (before the steps).
        var icon = "puzzlepiece.extension.fill"
        var colorHex = "148040"
        let preamble = String(q.prefix(while: {
            $0 != ":" && $0 != ";"
        }))
        let iconWords: [(String, String)] = [
            ("bolt", "bolt.fill"), ("moon", "moon.fill"),
            ("star", "star.fill"), ("shield", "shield.fill"),
            ("flame", "flame.fill"), ("fire", "flame.fill"),
            ("eye", "eye.fill"), ("ear", "ear.fill"),
            ("bell", "bell.fill"), ("key", "key.fill"),
            ("lock", "lock.fill"), ("snow", "snowflake"),
            ("leaf", "leaf.fill"), ("crown", "crown.fill"),
            ("globe", "globe"), ("play", "play.fill"),
            ("list", "list.bullet"), ("sun", "sun.max.fill"),
            ("cloud", "cloud.fill"), ("drop", "drop.fill"),
            ("mask", "theatermasks.fill"),
            ("target", "target"), ("scope", "scope"),
            ("wave", "waveform"),
            ("antenna", "antenna.radiowaves.left.and.right"),
            ("plane", "paperplane.fill"),
            ("puzzle", "puzzlepiece.extension.fill"),
        ]
        for (word, symbol) in iconWords
        where preamble.contains(word) {
            icon = symbol
            break
        }
        let colorWords: [(String, String)] = [
            ("red", "8E1F1F"), ("orange", "C2451E"),
            ("gold", "C9962E"), ("yellow", "C9962E"),
            ("green", "148040"), ("blue", "1E6FC2"),
            ("purple", "6C3BD4"), ("violet", "6C3BD4"),
            ("pink", "C22E6E"), ("gray", "5A6B7A"),
            ("grey", "5A6B7A"), ("teal", "7FB3C8"),
            ("white", "B8B2A7"),
        ]
        for (word, hex) in colorWords
        where preamble.contains(word) {
            colorHex = hex
            break
        }

        // The steps.
        var stepsText = q
        if let colon = q.firstIndex(of: ":") {
            stepsText = String(q[q.index(after: colon)...])
        }
        var phrases: [String]
        let dictated = stepsText.contains(";")
            || stepsText.contains(", ")
        if stepsText.contains(";") {
            phrases = stepsText.split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        } else if stepsText.contains(" then ") {
            phrases = stepsText.components(
                separatedBy: " then ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        } else if stepsText.contains(", ") {
            phrases = stepsText.components(separatedBy: ", ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            phrases = [stepsText.trimmingCharacters(
                in: .whitespaces)]
        }
        if !dictated {
            // Natural speech joins steps with "and" —
            // "goes dark and disguises as the printer"
            // is two steps wearing one coat.
            phrases = phrases.flatMap {
                $0.components(separatedBy: " and ")
            }.map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        }
        phrases = phrases.filter { !$0.isEmpty }

        var blocks: [MacroBlock] = []
        var unplaced: [String] = []
        for phrase in phrases {
            // A fragment of bare numbers right after a
            // knock is that knock's remaining ports.
            if let last = blocks.last, last.kind == "knock",
               phrase.allSatisfy({
                   $0.isNumber || $0 == " " || $0 == ","
               }), !phrase.isEmpty {
                var merged = last
                let extra = phrase.split(
                    separator: " ").compactMap {
                    Int($0.trimmingCharacters(
                        in: CharacterSet(charactersIn: ",")))
                }
                let ports = (last.intList("ports") + extra)
                    .filter { (1...65535).contains($0) }
                merged.config["ports"] = ports.map {
                    String($0)
                }.joined(separator: ", ")
                blocks[blocks.count - 1] = merged
                continue
            }
            if let block = macroStep(phrase, book: book) {
                blocks.append(block)
            } else {
                unplaced.append(phrase)
            }
        }

        guard !blocks.isEmpty else {
            say("I couldn't place any of those steps. "
                + "Steps I know: send, serve, beacon, "
                + "gatt, listen, sweep, knock, fuzz, go "
                + "dark, stealth, the banshee, a persona, "
                + "a costume, a chest, a Helm button, the "
                + "war room, a SIGINT watch, a challenge, "
                + "a defense, wait, wait for an arrival, "
                + "wait for a sighting, note, announce, "
                + "stop — separated by semicolons.")
            return
        }

        let macro = Macro(name: name, icon: icon,
                          colorHex: colorHex,
                          note: "Built by voice.",
                          blocks: blocks)
        macros.append(macro)
        MacroStore.save(macros)
        Journal.log("macro", "built",
                    "“\(name)” built by voice — "
                    + "\(blocks.count) blocks")
        var reply = "Built “\(name)” — \(blocks.count) "
            + "block\(blocks.count == 1 ? "" : "s"): "
            + blocks.map {
                MacroCatalog.spec($0.kind).title
            }.joined(separator: ", ") + "."
        if !unplaced.isEmpty {
            reply += " I couldn't place: "
                + unplaced.map { "“\($0)”" }
                    .joined(separator: ", ")
                + " — the editor can add them."
        }
        reply += " Say “run macro \(name)” when ready."
        say(reply)
    }

    private func addStepToMacro(_ q: String) {
        let parts = q.components(separatedBy: " to ")
        guard parts.count >= 2 else { return }
        let macroWords = parts[parts.count - 1]
        var stepText = parts.dropLast()
            .joined(separator: " to ")
        if stepText.hasPrefix("add ") {
            stepText = String(stepText.dropFirst(4))
        }
        if stepText.hasPrefix("a ") {
            stepText = String(stepText.dropFirst(2))
        }
        if stepText.hasPrefix("the ") {
            stepText = String(stepText.dropFirst(4))
        }
        var macros = MacroStore.load()
        guard let target = bestMacro(in: macroWords,
                                     from: macros) else {
            say("Which macro? The library holds: "
                + macroNames(macros) + ".")
            return
        }
        guard let block = macroStep(
            stepText.trimmingCharacters(in: .whitespaces),
            book: PayloadBook()) else {
            say("I couldn't place that step. Steps I "
                + "know: send, serve, beacon, gatt, "
                + "listen, sweep, knock, fuzz, go dark, "
                + "stealth, the banshee, a persona, a "
                + "costume, a chest, a Helm button, the "
                + "war room, a SIGINT watch, a "
                + "challenge, a defense, wait, wait for "
                + "an arrival, note, announce, stop.")
            return
        }
        guard let index = macros.firstIndex(
            where: { $0.id == target.id }) else { return }
        macros[index].blocks.append(block)
        macros[index].modifiedAt = Date()
        MacroStore.save(macros)
        say("Added “\(MacroCatalog.spec(block.kind).title)” "
            + "to “\(target.name)” — now "
            + "\(macros[index].blocks.count) blocks.")
    }

    // MARK: one dictated step → one block

    private func macroStep(_ rawStep: String,
                           book: PayloadBook) -> MacroBlock? {
        var s = rawStep.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("and ") { s = String(s.dropFirst(4)) }
        if s.hasPrefix("then ") { s = String(s.dropFirst(5)) }
        func block(_ kind: String,
                   _ extra: [String: String] = [:])
            -> MacroBlock {
            var config = MacroCatalog.defaults(for: kind)
            for (key, value) in extra { config[key] = value }
            return MacroBlock(kind: kind, config: config)
        }
        func numbers(in text: String) -> [Double] {
            text.split { !$0.isNumber && $0 != "." }
                .compactMap { Double($0) }
        }
        func trimNum(_ d: Double) -> String {
            d == d.rounded() ? String(Int(d)) : String(d)
        }
        func ipv4(in text: String) -> String? {
            text.split(separator: " ").map(String.init)
                .first { token in
                    let parts = token.split(separator: ".")
                    return parts.count == 4 && parts.allSatisfy {
                        Int($0) != nil
                    }
                }
        }
        func tail(after marker: String, in text: String)
            -> String? {
            guard let range = text.range(of: marker)
            else { return nil }
            let value = text[range.upperBound...]
                .trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        func bestName(_ names: [String], in text: String)
            -> String? {
            names.map { ($0, warNameScore($0, in: text)) }
                .filter { $0.1 > 0 }
                .max { $0.1 < $1.1 }?.0
        }

        // Passive first — waits carry other verbs inside
        // them ("wait for serve to answer" must not
        // become a Serve block).
        if s.contains("wait for") || s.contains("arrival")
            && s.contains("wait") {
            if s.contains("sighting") || s.contains("device")
                || s.contains("see") {
                var extra: [String: String] = [:]
                if let match = tail(after: "matching ",
                                    in: s) ?? tail(
                                        after: "named ", in: s) {
                    extra["match"] = match
                }
                if let n = numbers(in: s).last {
                    extra["seconds"] = trimNum(n)
                }
                if s.contains("stop the playlist")
                    || s.contains("stop on timeout") {
                    extra["onTimeout"] = "Stop the playlist"
                }
                return block("waitSighting", extra)
            }
            var extra: [String: String] = [:]
            if let n = numbers(in: s).last {
                extra["seconds"] = trimNum(n)
            }
            if s.contains("stop the playlist")
                || s.contains("stop on timeout") {
                extra["onTimeout"] = "Stop the playlist"
            }
            return block("waitInbox", extra)
        }
        if s.hasPrefix("wait") || s.hasPrefix("pause")
            || s.hasPrefix("hold") {
            var seconds = numbers(in: s).first ?? 10
            if s.contains("minute") { seconds *= 60 }
            return block("wait", ["seconds": trimNum(seconds)])
        }
        if s.hasPrefix("note") {
            let text = tail(after: "note", in: s)?
                .trimmingCharacters(
                    in: CharacterSet(charactersIn: " :"))
                ?? ""
            return block("note", ["text": text])
        }
        if s.hasPrefix("announce") || s.hasPrefix("notify") {
            let verb = s.hasPrefix("announce")
                ? "announce" : "notify"
            let text = tail(after: verb, in: s)?
                .trimmingCharacters(
                    in: CharacterSet(charactersIn: " :"))
                ?? ""
            return block("announce", ["text": text])
        }
        if s == "stop" || s == "stop the playlist"
            || s == "end" || s == "end the playlist" {
            return block("stop")
        }

        // Posture.
        if s.contains("go dark") || s == "dark"
            || s.contains("emcon on") {
            return block("emconOn")
        }
        if s.contains("stand down") || s.contains("emcon off") {
            return block("emconOff")
        }
        if s.contains("stealth") {
            return block("stealth",
                         ["on": s.contains("off")
                            ? "off" : "on"])
        }
        if s.contains("banshee") || s.contains("scream")
            || s.contains("cease") {
            let cease = s.contains("cease")
                || s.contains("silence")
                || s.contains("stop")
            return block("banshee",
                         ["mode": cease ? "Cease" : "Scream"])
        }

        // Serve.
        if s.contains("serve") {
            if s.contains("stop") || s.contains("down")
                || s.contains("off") {
                return block("serveStop")
            }
            var extra: [String: String] = [:]
            // Her standing presumption, built in:
            // stealth is desired unless the step
            // says loud — a Serve she raises by
            // voice goes up unlisted.
            if s.contains("stealth off")
                || s.contains("listed")
                || s.contains("loud")
                || s.contains("public")
                || s.contains("visible") {
                extra["stealth"] = "Off"
            } else {
                extra["stealth"] = "On"
            }
            return block("serveStart", extra)
        }

        // Air.
        if s.contains("beacon") {
            if s.contains("stop") || s.contains("off")
                || s.contains("down") {
                return block("beaconStop")
            }
            var extra: [String: String] = [:]
            if let payload = bestName(
                book.items.map { $0.name }, in: s) {
                extra["payload"] = payload
            }
            if let airName = tail(after: "named ", in: s)
                ?? tail(after: "as ", in: s) {
                extra["name"] = airName
            }
            return block("beaconStart", extra)
        }
        if s.contains("gatt") {
            if s.contains("stop") || s.contains("off")
                || s.contains("down") {
                return block("gattStop")
            }
            var extra: [String: String] = [:]
            if let payload = bestName(
                book.items.map { $0.name }, in: s) {
                extra["payload"] = payload
            }
            if let airName = tail(after: "named ", in: s)
                ?? tail(after: "as ", in: s) {
                extra["name"] = airName
            }
            return block("gattStart", extra)
        }

        // Listen & Recon.
        if s.contains("listen") {
            if s.contains("stop") || s.contains("off")
                || s.contains("close") {
                return block("listenStop")
            }
            var extra: [String: String] = [:]
            if let label = tail(after: "as ", in: s) {
                extra["label"] = label
            }
            return block("listenStart", extra)
        }
        if s.contains("sweep") {
            return block("sweep")
        }
        if s.contains("knock") {
            guard let host = ipv4(in: s) else { return nil }
            let words = s.replacingOccurrences(
                of: host, with: " ")
            let ports = numbers(in: words)
                .map { Int($0) }
                .filter { (1...65535).contains($0) }
            var extra: [String: String] = [
                "host": host,
                "ports": ports.map { String($0) }
                    .joined(separator: ", "),
            ]
            if s.contains("udp") { extra["udp"] = "on" }
            return block("knock", extra)
        }
        if s.contains("fuzz") {
            if s.contains("stop") || s.contains("off") {
                return block("fuzzStop")
            }
            var extra: [String: String] = [:]
            if let token = s.split(separator: " ")
                .map(String.init)
                .first(where: { $0.contains(":")
                    || $0.contains(".") }) {
                extra["target"] = token
            }
            if let n = numbers(in: s).last, n >= 10,
               s.contains("packet") {
                extra["count"] = trimNum(n)
            }
            return block("fuzzStart", extra)
        }

        // The war rooms.
        if s.contains("assault") {
            let disarm = s.contains("disarm")
                || s.contains("off") || s.contains("down")
            return block("assault",
                         ["mode": disarm ? "Disarm" : "Arm"])
        }
        if s.contains("war room") {
            return block("warRoom",
                         ["mode": s.contains("stop")
                            ? "Stop" : "Start"])
        }
        if s.contains("sigint")
            || s.contains("watch") && s.contains("station") {
            var extra: [String: String] = [:]
            if s.contains("air") && !s.contains("wire") {
                extra["scope"] = "air"
            } else if s.contains("wire")
                        && !s.contains("air") {
                extra["scope"] = "wire"
            }
            if let watchName = tail(after: "called ", in: s)
                ?? tail(after: "named ", in: s) {
                extra["name"] = watchName
            }
            return block("sigintWatch", extra)
        }
        if s.contains("challenge") {
            guard let ip = ipv4(in: s) else { return nil }
            return block("warChallenge", ["ip": ip])
        }
        if s.contains("defen") {
            let ports = numbers(in: s).map { Int($0) }
                .filter { (1...65535).contains($0) }
            var extra: [String: String] = [
                "doors": ports.map { String($0) }
                    .joined(separator: ", "),
            ]
            if let decoys = tail(after: "decoys ", in: s) {
                extra["decoys"] = decoys
            }
            return block("warDefense", extra)
        }
        if s.contains("chest") {
            guard let chest = bestName(
                MacroNames.chestNames(), in: s) else {
                return nil
            }
            return block("chestApply", ["chest": chest])
        }
        if s.contains("persona") || s.contains("disguise")
            || s.contains("mimic")
            || s.contains("pretend") {
            if s.contains("drop") || s.contains("take off")
                || s.contains("remove") {
                return block("persona", ["mode": "Drop"])
            }
            if let persona = bestName(
                MacroNames.personaNames(), in: s) {
                return block("persona",
                             ["mode": "Don", "name": persona])
            }
            // A disguise can be a costume, too — try
            // the rack before giving the step up.
            if let costume = bestName(
                MacroNames.costumeNames(), in: s) {
                return block("costume", ["name": costume])
            }
            return nil
        }
        if s.contains("costume") || s.contains("wear") {
            let name = bestName(MacroNames.costumeNames(),
                                in: s)
                ?? tail(after: "costume ", in: s)
                ?? tail(after: "wear ", in: s)
                ?? ""
            guard !name.isEmpty else { return nil }
            return block("costume", ["name": name])
        }
        if s.contains("helm") || s.contains("fire") {
            guard let remote = bestName(
                MacroNames.remoteNames(), in: s),
                  let button = bestName(
                    MacroNames.helmButtons(remote: remote),
                    in: s) else {
                return nil
            }
            return block("helmFire",
                         ["remote": remote, "button": button])
        }
        if s.contains("send") {
            guard let payload = bestName(
                book.items.map { $0.name }, in: s) else {
                return nil
            }
            var extra: [String: String] = ["payload": payload]
            if let target = tail(after: "to ", in: s)?
                .split(separator: " ").first {
                extra["target"] = String(target)
            } else if let host = ipv4(in: s) {
                extra["target"] = host
            }
            return block("sendPayload", extra)
        }
        return nil
    }

    /// The war rooms, by voice — the 7.0.0 campaign under
    /// her hands like everything else: the Banshee, the
    /// SIGINT watches, the Helm, the chests, a War Room
    /// run, War Games scores and challenges, and the
    /// Spoofy rack with its mimicry shapes.
    func warAsk(_ q: String) -> Bool {
        // The Banshee — one word in this house is an order.
        if q.contains("banshee") || q.contains("scream") {
            guard let mouth = mouth else { return false }
            if q.contains("cease") || q.contains("stop")
                || q.contains("silence")
                || q.contains("quiet") {
                BansheeCenter.shared.cease(
                    mouth: mouth, assault: AssaultCenter.shared)
                say("The banshee is silent. The posture it "
                    + "found is restored, stealth last of all.")
            } else {
                BansheeCenter.shared.scream(
                    mouth: mouth, assault: AssaultCenter.shared)
                say("The banshee screams: Serve listed and "
                    + "stealth off, the beacon shouting, "
                    + "Net-Assault armed, a broadcast "
                    + "heartbeat on the subnet. Say cease the "
                    + "banshee and the room returns to what "
                    + "it was.")
            }
            return true
        }

        // The SIGINT station — watches and the registry.
        let station = SigintStation.shared
        if q.contains("registry") || q.contains("emitters") {
            // A sleeping station reads as an empty
            // registry, which is a lie of omission: wake
            // the desk and say so. Her attachment holds
            // it warm for the rest of the session.
            var woke = false
            if let post = post, !station.isAttached {
                station.attach(post: post)
                woke = true
            }
            let air = station.emitters
                .filter { $0.kind == "ble" }.count
            let wire = station.emitters
                .filter { $0.kind == "lan" }.count
            let top = station.emitters
                .sorted { $0.priority > $1.priority }
                .prefix(3).map { $0.label }
            say("The registry holds \(station.emitters.count) "
                + "emitters this epoch — \(air) in the air, "
                + "\(wire) on the wire."
                + (top.isEmpty ? ""
                   : " Loudest: \(top.joined(separator: ", ")).")
                + (woke
                   ? " The station was asleep — it is on "
                   + "the desk now and stays."
                   : ""))
            return true
        }
        if q.contains("watch") {
            guard let post = post else { return false }
            if q.contains("stop") || q.contains("file")
                || q.contains("end") {
                guard station.currentWatch != nil else {
                    say("No watch is running.")
                    return true
                }
                station.stopWatch(post: post)
                say("Watch filed. "
                    + (station.lastWatch?.summaryText ?? ""))
                return true
            }
            if q.contains("find") || q.contains("found")
                || q.contains("summar") || q.contains("show") {
                if let watch = station.lastWatch {
                    say(watch.summaryText)
                } else {
                    say("No watch has been filed yet — "
                        + "start one, work the room, stop it, "
                        + "and I will read you the delta.")
                }
                return true
            }
            if q.contains("start") || q.contains("begin")
                || q.contains("run") {
                let scope = (q.contains("air")
                             || q.contains("ble")) ? "air"
                    : (q.contains("wire")
                       || q.contains("lan")) ? "wire" : "mixed"
                station.startWatch(name: "Skelli's watch",
                                   scope: scope, post: post)
                say("Watch running (\(scope)). The registry "
                    + "records; stop it and I will read the "
                    + "delta — what arrived, what vanished, "
                    + "which doors changed."
                    + (post.session == nil
                       ? " The ear is down, so this watch "
                       + "reads the wire and the log — "
                       + "start Listen for the air half."
                       : ""))
                return true
            }
        }

        // The War Chest — dress the rig.
        if q.contains("chest") {
            if q.contains("pack") || q.contains("capture") {
                var name = "Packed by Skelli"
                for marker in ["called ", "named "] {
                    if let range = q.range(of: marker) {
                        let rest = String(q[range.upperBound...])
                            .trimmingCharacters(
                                in: .whitespaces)
                        if !rest.isEmpty { name = rest }
                        break
                    }
                }
                var shelf = NJChestStore.load()
                shelf.append(NJChest.capture(
                    id: UUID().uuidString, name: name))
                NJChestStore.save(shelf)
                say("Packed “\(name)” — the rig as it "
                    + "stands, on the shelf. Applying it "
                    + "later dresses everything and starts "
                    + "nothing.")
                return true
            }
            let chests = NJChestStore.load()
            if q.contains("apply") || q.contains("wear")
                || q.contains("load") || q.contains("dress") {
                guard let mouth = mouth else { return false }
                let hit = chests
                    .map { (c: $0, s: warNameScore($0.name, in: q)) }
                    .filter { $0.s >= 1 }
                    .sorted { $0.s > $1.s }.first
                guard let chest = hit?.c else {
                    say(chests.isEmpty
                        ? "No chests are packed yet."
                        : "Which chest? Packed: "
                        + chests.map { $0.name }
                            .joined(separator: ", ") + ".")
                    return true
                }
                chest.apply(mouth: mouth)
                say("The \(chest.name) chest is on — Send, "
                    + "Serve, Recon and the trace wear it. "
                    + "Nothing was started; a chest dresses "
                    + "the rig, it does not pull a trigger."
                    + (MimicCenter.shared.activePersona != nil
                       ? " Note: a Spoofy shape is worn, "
                       + "and dropping it restores the "
                       + "wardrobe from before the shape — "
                       + "this dress would unwind with it."
                       : ""))
                return true
            }
            say(chests.isEmpty
                ? "No chests are packed yet — pack one in "
                + "the Send tab's Trace section."
                : "Packed chests: "
                + chests.map { $0.name }
                    .joined(separator: ", ")
                + ". Say apply one and I will dress the rig.")
            return true
        }

        // The Helm — fire a button by name.
        if q.contains("fire") || q.contains("press") {
            guard let mouth = mouth else { return false }
            let remotes = HelmStore.load()
            var best: (button: HelmButton, score: Int)?
            for remote in remotes {
                for button in remote.buttons {
                    let s = warNameScore(
                        button.label + " " + remote.name, in: q)
                    if s > 0, best == nil || s > best!.score {
                        best = (button, s)
                    }
                }
            }
            guard let hit = best else {
                let labels = remotes.flatMap { $0.buttons }
                    .map { $0.label }
                say(remotes.isEmpty
                    ? "The Helm holds no remotes yet."
                    : "No button matches that. On the "
                    + "shelf: "
                    + labels.joined(separator: ", ") + ".")
                return true
            }
            say(HelmFire.fire(hit.button,
                              book: PayloadBook(), mouth: mouth))
            return true
        }

        // The War Room — one run, three organs, one timeline.
        if q.contains("war room") {
            guard let mouth = mouth, let post = post
            else { return false }
            let run = WarRun.shared
            if q.contains("status") || q.contains("how") {
                say("War Room: "
                    + run.phase.rawValue.lowercased()
                    + " — \(run.events.count) timeline events "
                    + "so far.")
                return true
            }
            if run.running {
                say("The War Room run is already working "
                    + "— \(run.phase.rawValue.lowercased()). "
                    + "There is only the one run; the room's "
                    + "console shows this same one.")
                return true
            }
            run.start(mouth: mouth, post: post,
                      recon: Recon(), book: PayloadBook(),
                      config: warRoomConfig())
            if run.phase == .failed {
                say(run.statusLine
                    ?? "The run did not start.")
            } else {
                say("The War Room is working — Listen, "
                    + "trace, then knocks at the doors the "
                    + "trace touches, one timeline. Ask me "
                    + "for its status.")
            }
            return true
        }

        // War Games — scores and challenges.
        if q.contains("war game") || q.contains("wargame") {
            guard let mouth = mouth, let post = post
            else { return false }
            let games = WarGamesCenter.shared
            games.attachForHands(mouth: mouth, post: post)
            if q.contains("score") || q.contains("verdict")
                || q.contains("who won") {
                games.tryScore()
                if let report = games.report {
                    say(report.verdict)
                } else {
                    say("No scored round yet — the cards are "
                        + "not both in (mine: "
                        + (games.myCard == nil
                           ? "not filed" : "filed")
                        + ", theirs: "
                        + (games.theirCard == nil
                           ? "not received" : "in") + ").")
                }
                // A scoring ask with no challenge out
                // is an errand, not a hold — her tick
                // stands down. (A round that just scored
                // dropped the hold inside tryScore.)
                if games.challengedPeer.isEmpty {
                    games.detachHands()
                }
                return true
            }
            if q.contains("begin") || q.contains("attack now")
                || q.contains("start the attack") {
                guard games.role == "attacker" else {
                    say("You are set as the \(games.role) — "
                        + "a challenge makes you the attacker.")
                    return true
                }
                guard !games.challengedPeer.isEmpty else {
                    say("No challenge is out — challenge "
                        + "the defender's address first.")
                    return true
                }
                guard games.phase.contains("READY") else {
                    say("The defender has not answered "
                        + "READY yet. \(games.phase)")
                    return true
                }
                games.beginAttack(config: warRoomConfig(),
                                  knockPorts: warReconPorts(),
                                  knockUDP: warReconUDP())
                say("START sent to \(games.challengedPeer) "
                    + "— the trace runs at them, then the "
                    + "knocks on the Recon ports. The card "
                    + "files itself when the round closes; "
                    + "ask me for the score.")
                return true
            }
            if q.contains("defend") || q.contains("defense") {
                if games.role != "defender" {
                    games.setRole("defender")
                }
                let doors = warServeDoors()
                let decoys = warParseDecoys()
                games.setDefense(serveDoors: doors,
                                 decoys: decoys)
                say("Defense set: \(doors.count) of Serve's "
                    + "doors held as real, \(decoys.count) "
                    + "decoys flying"
                    + (decoys.isEmpty ? ""
                       : " (\(decoys.joined(separator: ", ")))")
                    + ". The catch window is the Serve "
                    + "inbox — keep Serve up and serving.")
                return true
            }
            if q.contains("challenge") {
                let words = q.split(separator: " ")
                let ip = words.first {
                    $0.split(separator: ".").count == 4
                        && $0.allSatisfy {
                            $0.isNumber || $0 == "."
                        }
                }
                guard let ip = ip else {
                    say("Challenge whom? Give me the "
                        + "defender's address — challenge "
                        + "192.168.4.31.")
                    return true
                }
                let port = Int(UserDefaults.standard.string(
                    forKey: "serveTcpPort") ?? "9000") ?? 9000
                games.setRole("attacker")
                games.challenge(defenderIP: String(ip),
                                port: port, myControlPort: port,
                                myLabel: warHostName())
                say("Challenge sent to \(ip) — the defender "
                    + "must be serving with its War Games "
                    + "room open. When READY lands, the round "
                    + "is set from the War Games room in the "
                    + "Send tab.")
                return true
            }
            say("War Games: match \(games.matchID), round "
                + "\(games.round), you fight as the "
                + "\(games.role). \(games.phase)")
            return true
        }

        // Spoofy — costumes and mimicry shapes.
        if q.contains("spoofy") || q.contains("costume")
            || q.contains("mimic") || q.contains("wear the")
            || q.contains("disguise") || q.contains("rotat") {
            guard let mouth = mouth else { return false }
            if q.contains("drop") {
                say(MimicCenter.shared.drop(mouth: mouth))
                return true
            }
            if q.contains("rotat") {
                if q.contains("stop") || q.contains("still") {
                    SpoofyRotator.shared.stop()
                    say("The rack stands still — the name "
                        + "stays where the rotation left it.")
                } else {
                    say(SpoofyRotator.shared.start(
                        mouth: mouth))
                }
                return true
            }
            if q.contains("dice") || q.contains("roll")
                || q.contains("random") {
                say(Spoofy.applyName(Spoofy.diceName(),
                                     mouth: mouth))
                return true
            }
            let shapes = SpoofyPersona.all
                + SpoofyStore.loadPersonas()
            if let persona = shapes.first(where: {
                q.contains($0.id)
                    || warNameScore($0.label, in: q) >= 2
            }) {
                say(MimicCenter.shared.don(persona,
                                            mouth: mouth))
                return true
            }
            let costume = (Spoofy.costumeNames
                + SpoofyStore.loadCostumes())
                .map { (n: $0, s: warNameScore($0, in: q)) }
                .filter { $0.s >= 1 }
                .sorted { $0.s > $1.s }.first
            if let hit = costume {
                say(Spoofy.applyName(hit.n, mouth: mouth))
                return true
            }
            say("The rack holds costumes — "
                + Spoofy.costumeNames.prefix(4)
                    .joined(separator: ", ")
                + " — network gear (access point, "
                + "gateway, mesh node, media server, hub) "
                + "and device shapes (printer, TV, "
                + "speaker, NAS, thermostat, vacuum). "
                + "Say wear the access point, or roll "
                + "the dice.")
            return true
        }

        return false
    }

    func lateGate(_ q: String, raw: String) -> Bool {
        if handsGate(q, raw: raw) { return true }
        return secondReading(q, raw: raw)
    }

    /// The shape comes off by voice, in the
    /// words the house itself teaches ("until
    /// you drop the shape"). It runs AHEAD of
    /// deleteAsk in the gate: "drop" is one of
    /// the delete hand's verbs, so the phrase
    /// was answered from the armory — "Nothing
    /// in the armory matches that." — and could
    /// even strike an armory piece whose name
    /// shared a word with it. The idiom is
    /// fenced both ways: it must name a worn
    /// thing, and it must NOT name an armory
    /// subject — asks carrying payload, pattern,
    /// or armory belong to the delete hand
    /// still. (Chase's ruling, 2026-10-18.)
    func shapeDropAsk(_ q: String) -> Bool {
        guard q.contains("drop") else {
            return false
        }
        guard !q.contains("payload")
                && !q.contains("pattern")
                && !q.contains("armory")
        else { return false }
        let markers = ["shape", "costume", "persona",
                       "spoofy", "mimic", "disguise"]
        guard markers.contains(where: {
            q.contains($0) }) else { return false }
        guard let mouth = mouth else {
            return false
        }
        say(MimicCenter.shared.drop(mouth: mouth))
        return true
    }

    /// "Delete the DNS packet you forged" — what
    /// she built, she can also strike: armory
    /// payloads (hers, and customs of his) and
    /// taught patterns, by name, the Deliveries
    /// copy going too. It runs first among her
    /// hands — "the packet you forged" must
    /// never be read as a fresh order to forge.
    func deleteAsk(_ q: String) -> Bool {
        guard q.contains("delete")
                || q.contains("remove")
                || q.contains("throw away")
                || q.contains("get rid of")
                || q.contains("drop ")
        else { return false }

        // How strongly a name is meant by the words
        // he used: shared name-words, stopwords
        // aside.
        func score(_ name: String) -> Int {
            let stop: Set<String> = ["the", "for", "and", "with"]
            return name.lowercased()
                .split(whereSeparator: {
                    !$0.isLetter && !$0.isNumber
                })
                .filter {
                    $0.count > 2
                        && !stop.contains(String($0))
                }
                .filter { q.contains($0) }
                .count
        }
        let bulk = q.contains(" all ")
            || q.hasSuffix(" all")
            || q.contains("everything")
            || q.contains(" every ")

        // Her taught patterns.
        let customs = ForgePatternStore.load()
        if q.contains("pattern") {
            if bulk {
                ForgePatternStore.save([])
                say("Struck all \(customs.count) "
                    + "taught patterns. She builds "
                    + "from her five built-ins again.")
                return true
            }
            let doomed = customs.filter {
                score($0.name) >= 1
            }
            guard let hit = doomed.max(by: {
                score($0.name) < score($1.name)
            }) else {
                say(customs.isEmpty
                    ? "She holds no taught patterns "
                        + "to strike."
                    : "Which pattern? She holds: "
                        + customs.map { $0.name }
                            .joined(separator: ", ")
                        + ".")
                return true
            }
            ForgePatternStore.save(customs.filter {
                $0.id != hit.id
            })
            say("Struck the pattern: " + hit.name + ".")
            return true
        }

        // The armory.
        let book = PayloadBook()
        if bulk && (q.contains("forged")
                    || q.contains("hers")
                    || q.contains("you made")
                    || q.contains("you built")) {
            let doomed = book.items.filter {
                $0.name.hasPrefix("Forged — ")
            }
            guard !doomed.isEmpty else {
                say("Nothing of hers sits in the "
                    + "armory to strike.")
                return true
            }
            var indices = IndexSet()
            for item in doomed {
                if let index = book.items
                    .firstIndex(of: item) {
                    indices.insert(index)
                }
            }
            book.remove(at: indices)
            for item in doomed {
                strikeDelivery(item.name)
            }
            say("Struck from the armory: "
                + doomed.map { $0.name }
                    .joined(separator: "; ")
                + ". Deliveries copies went too.")
            return true
        }
        let scored = book.items
            .map { (item: $0, score: score($0.name)) }
            .filter { $0.score >= 1 }
            .sorted { a, b in
                a.score != b.score
                    ? a.score > b.score
                    : !a.item.builtIn && b.item.builtIn
            }
        guard let hit = scored.first else {
            // No match, no speech (2026-10-20):
            // this hand once answered EVERY
            // unmatched delete sentence with
            // "Nothing in the armory matches
            // that." — including "delete the
            // log", which was never the
            // armory's to answer and never
            // reached the clear lane behind
            // it. Silence here lets the ask
            // fall to the hands it belongs to.
            return false
        }
        if let index = book.items
            .firstIndex(of: hit.item) {
            book.remove(at: IndexSet(integer: index))
        }
        strikeDelivery(hit.item.name)
        say("Struck from the armory: " + hit.item.name
            + (hit.item.builtIn
                ? " — a built-in; Restore in the "
                    + "Send payload list brings it back."
                : ". Its Deliveries copy went too."))
        return true
    }

    /// A forged keep lives twice — armory and
    /// Deliveries — and a strike takes both.
    private func strikeDelivery(_ name: String) {
        let center = DeliveriesCenter.shared
        for item in center.items where item.name == name {
            center.remove(item)
        }
    }

    /// "Forge me a DNS packet for the gateway" —
    /// she builds it herself, in conversation: the
    /// same ForgeKit the sheet drives, kept the
    /// same way.
    func forgeAsk(_ q: String, raw: String) -> Bool {
        let wantsForge = q.contains("forge")
            || ((q.contains("packet") || q.contains("payload"))
                && (q.contains("build") || q.contains("make")
                    || q.contains("craft") || q.contains("create")))
        guard wantsForge else { return false }
        // The gateway, by the house convention: this
        // wire's .1, from the phone's own address.
        let gateway = Mouth.localIPAddress().map { ip -> String in
            var parts = ip.split(separator: ".")
            guard parts.count == 4 else { return ip }
            parts[3] = "1"
            return parts.joined(separator: ".")
        }
        let words = q.split(separator: " ").map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?\"'"))
        }
        let ip = words.first(where: { word in
            word.split(separator: ".").count == 4
                && word.allSatisfy { $0.isNumber || $0 == "." }
        })
        let domain = words.first(where: { word in
            word.contains(".") && word != ip
                && word.contains(where: { $0.isLetter })
        })
        let host = ip ?? (q.contains("gateway") ? gateway : nil)
        let built: ForgeKit.Built
        if q.contains("dns") {
            let name: String
            if let domain {
                name = domain
            } else if q.contains("gateway"), let gateway {
                // Asked for the gateway: a reverse
                // question, by name.
                name = gateway.split(separator: ".").reversed()
                    .joined(separator: ".") + ".in-addr.arpa"
            } else {
                name = "example.com"
            }
            built = ForgeKit.dns(host: name)
        } else if q.contains("ssdp") {
            built = ForgeKit.ssdp()
        } else if q.contains("mqtt") {
            built = ForgeKit.mqtt(clientID: "nightjar")
        } else if q.contains("http") {
            built = ForgeKit.http(method: q.contains(" post ") ? "POST" : "GET",
                                  host: host ?? domain ?? "192.168.4.1",
                                  path: "/", body: "")
        } else if q.contains("banner") || q.contains("probe") {
            built = ForgeKit.probe()
        } else if let custom = ForgePatternStore.load().first(where: {
            q.contains($0.name.lowercased())
        }) {
            var text = custom.template
            let swaps: [(String, String)] = [
                ("{host}", host ?? "192.168.4.1"), ("{path}", "/"),
                ("{domain}", domain ?? "example.com"),
                ("{client}", "nightjar"), ("{method}", "GET"),
            ]
            for (hole, value) in swaps {
                text = text.replacingOccurrences(of: hole, with: value)
            }
            built = ForgeKit.Built(name: "Forged — " + custom.name,
                                   source: custom.source, text: text)
        } else {
            forgeDraft(raw)
            return true
        }
        keepForged(built)
        return true
    }

    /// A keep is a keep, from her hands or the
    /// sheet's: armory takes the payload,
    /// Deliveries takes the file.
    private func keepForged(_ built: ForgeKit.Built) {
        PayloadBook().add(SavedPayload(name: built.name, source: built.source,
                                       text: built.text, xorKey: "",
                                       useGzip: false, framing: "raw"))
        DeliveriesCenter.shared.add(name: built.name, text: built.text,
                                    ext: built.source == "hex" ? "hex" : "txt")
        say("Forged and kept: " + built.name
            + " — \(ForgeKit.byteCount(of: built)) bytes. It is in the "
            + "armory, filed in Deliveries, ready to fire from Send.")
    }

    /// A forge she holds no pattern for goes to her
    /// benches under the forge's own charter — the
    /// same draft the Forge sheet asks for.
    private func forgeDraft(_ raw: String) {
        guard SkelliMind.isAvailable || SkelliMind.weightsReady else {
            say("My patterns are HTTP, DNS, SSDP, MQTT, and a banner "
                + "probe — name one and I will build it. With a bench "
                + "awake I can also draft from a plain brief.")
            return
        }
        activity = "Forging…"
        Task {
            let text = await SkelliMind.rawAnswer(
                instructions: "You are the forge inside nightjar-hack. The operator describes a payload; produce ONLY the payload itself — raw protocol text, or space-separated hex bytes for a binary payload. No explanation, no code fences. If the brief is unclear, produce the closest standard probe.",
                prompt: raw)
            await MainActor.run {
                guard let text, !text.isEmpty else {
                    say("No bench could draft that just now.")
                    return
                }
                let hexish = text.split(separator: " ").allSatisfy {
                    $0.count == 2 && $0.allSatisfy { $0.isHexDigit }
                }
                keepForged(ForgeKit.Built(name: "Forged — draft",
                                          source: hexish ? "hex" : "text",
                                          text: text))
            }
        }
    }

    /// Her bench, run from conversation: fetch a
    /// model, put one on the bench, or report its
    /// state — the same shared center the sheet
    /// drives.
    func weightsAsk(_ q: String) -> Bool {
        guard q.contains("weight") || q.contains("model")
                || q.contains("qwen") || q.contains("llama")
        else { return false }
        let center = WeightsCenter.shared
        func option() -> WeightsOption? {
            if q.contains("llama") || q.contains("3b") { return WeightsCenter.catalog[1] }
            if q.contains("1.7") { return WeightsCenter.catalog[2] }
            if q.contains("7b") { return WeightsCenter.catalog[3] }
            if q.contains("0.6") { return WeightsCenter.catalog[4] }
            if q.contains("qwen") || q.contains("4b") { return WeightsCenter.catalog[0] }
            return nil
        }
        if q.contains("download") || q.contains("fetch") || q.contains("install") {
            let pick = option() ?? center.recommended
            if center.downloaded.contains(pick.id) {
                say(pick.name + " is already on the phone.")
                return true
            }
            center.download(pick)
            say("Fetching " + pick.name + " — \(pick.sizeGB) GB from the "
                + "hub. It joins the bench when it lands; tell me to use "
                + "it and I will put it on.")
            return true
        }
        if q.contains("use ") || q.contains("select") || q.contains("switch") {
            guard let pick = option() else { return false }
            if center.downloaded.contains(pick.id) {
                center.select(pick)
                say(pick.name + " is on the bench.")
            } else {
                center.download(pick)
                say(pick.name + " is not on the phone yet — fetching it "
                    + "now. When it lands, tell me to use it and I will "
                    + "put it on the bench.")
            }
            return true
        }
        if q.contains("which") || q.contains("what") || q.contains("have") {
            let carried = WeightsCenter.catalog
                .filter { center.downloaded.contains($0.id) }.map { $0.name }
            let current = WeightsCenter.catalog
                .first(where: { $0.id == center.selectedID })?.name
            say("On the bench: " + (current ?? "none chosen")
                + ". On the phone: "
                + (carried.isEmpty ? "no weights yet" : carried.joined(separator: ", "))
                + ".")
            return true
        }
        return false
    }

    // MARK: her knocktalk hand — she sends

    /// "knocktalk: <words>", "knocktalk <words>",
    /// "send a knocktalk to <peer> saying <words>":
    /// she seals and sends it herself, through
    /// the same chat the tab holds. The payload
    /// rides the RAW ask — his casing is his —
    /// and a message the road refuses for length
    /// is refused aloud, never truncated.
    /// Her console hand (fix153):
    /// "console: <line>", "blacksite
    /// <line>", "run in the console:
    /// <line>" — she runs the line in
    /// the Blacksite room and speaks
    /// what it printed. Questions about
    /// the console are not commands
    /// (the manual owns those), and an
    /// unopened room is answered
    /// honestly, never faked.
    func consoleAsk(_ q: String, raw: String) -> Bool {
        var payloadQ: String? = nil
        let prefixes: [(String, Int)] = [
            ("console:", 8), ("blacksite:", 10),
            ("terminal:", 9), ("blacksite ", 10),
            ("terminal ", 9), ("console run ", 12),
        ]
        for (prefix, count) in prefixes
        where q.hasPrefix(prefix) {
            payloadQ = String(q.dropFirst(count))
            break
        }
        if payloadQ == nil,
           let r = q.range(of: "run in the console:") {
            payloadQ = String(q[r.upperBound...])
        } else if payloadQ == nil,
                  let r = q.range(of: "run in the console ") {
            payloadQ = String(q[r.upperBound...])
        }
        guard var payload = payloadQ?
            .trimmingCharacters(in: .whitespaces),
              !payload.isEmpty, !payload.contains("?")
        else { return false }
        if ["status", "help", "open"]
            .contains(payload) {
            return false
        }
        // His casing, from the raw ask,
        // when the raw ask carried the
        // same prefix.
        let rawLow = raw.lowercased()
        for (prefix, count) in prefixes
        where rawLow.hasPrefix(prefix) {
            var text = String(raw.dropFirst(count))
                .trimmingCharacters(
                    in: .whitespaces)
            if text.hasPrefix(":") {
                text = String(text.dropFirst())
                    .trimmingCharacters(
                        in: .whitespaces)
            }
            if !text.isEmpty { payload = text }
            break
        }
        guard let shell = blacksiteShell else {
            say("The console hasn't woken in "
                + "this run of the app — open "
                + "the Blacksite tab once and "
                + "the hand is mine from then "
                + "on.")
            return true
        }
        let out = shell.runForSkelli(payload)
        if out.isEmpty {
            say("Ran it — nothing came back "
                + "on the line. If it's a "
                + "program, its output lives "
                + "in the console; the "
                + "Blacksite tab holds it.")
        } else if out.count > 700 {
            say(String(out.prefix(700))
                + "\n…the console holds the rest.")
        } else {
            say(out)
        }
        return true
    }

    /// Her vault hand (fix154): seal a
    /// note she holds, seal a file on
    /// the Deliveries shelf, or open a
    /// sealed .njcf back onto it — all
    /// under the Vault's own key,
    /// CryptoFiles' work with no
    /// password spoken. Password
    /// sealing belongs to the Vault
    /// tab's proper fields (the crypto
    /// hand's standing doctrine); an
    /// ask that names one is answered
    /// with that truth and an offer of
    /// the key instead.
    func vaultAsk(_ q: String, raw: String) -> Bool {
        let sealing = q.contains("encrypt")
            || q.contains("seal the")
            || q.contains("seal my")
            || q.contains("seal a ")
        let opening = q.contains("decrypt")
            || q.contains("unseal")
        guard sealing || opening else {
            return false
        }
        guard q.contains("file")
            || q.contains("note")
            || q.contains(".njcf")
        else { return false }

        var noteText: String? = nil
        var item: DeliveriesCenter.Item? = nil

        if !opening && q.contains("note") {
            // A note she holds. Named by
            // its words, or the latest.
            let target: SkelliNote?
            if q.contains("last note")
                || q.contains("latest note") {
                target = notes.last
            } else if notes.count == 1 {
                target = notes.first
            } else {
                target = notes.max(by: { a, b in
                    vaultScore(a.text, in: q)
                        < vaultScore(b.text,
                                     in: q)
                }).flatMap {
                    vaultScore($0.text, in: q) > 0
                        ? $0 : nil
                }
            }
            guard let note = target else {
                say(notes.isEmpty
                    ? "I hold no notes to seal "
                        + "yet — teach me one "
                        + "first."
                    : "Which note? I hold "
                        + "\(notes.count). "
                        + "Say 'seal my last "
                        + "note', or name it by "
                        + "its words.")
                return true
            }
            noteText = note.text
        } else {
            // A file on the shelf, named
            // by its file name in the ask.
            let token = q.split(whereSeparator: {
                $0 == " " || $0 == "\""
                    || $0 == "'"
            }).map(String.init).first {
                $0.contains(".")
            }
            let shelfItems = DeliveriesCenter
                .shared.items
            let hit = token.flatMap { t in
                shelfItems.first {
                    $0.file.lowercased() == t
                        || $0.name.lowercased() == t
                }
            }
            guard let found = hit else {
                let names = shelfItems
                    .map { $0.file }
                    .joined(separator: ", ")
                say(shelfItems.isEmpty
                    ? "The Deliveries shelf is "
                        + "empty — there is no "
                        + "file for me to "
                        + (opening ? "open."
                                   : "seal.")
                    : "I don't find that name "
                        + "on the shelf. It "
                        + "holds: " + names + ".")
                return true
            }
            if opening && !found.file
                .hasSuffix(".njcf") {
                say(found.file + " isn't a "
                    + "sealed box — opening "
                    + "wants a .njcf.")
                return true
            }
            item = found
        }

        if q.contains("password") {
            // The doctrine, spoken, with
            // the key offered in its
            // place — a yes runs it.
            let openingCopy = opening
            let noteCopy = noteText
            let itemCopy = item
            pendingAction = { [weak self] in
                self?.runVaultKey(
                    opening: openingCopy,
                    noteText: noteCopy,
                    item: itemCopy)
            }
            say("Passwords aren't spoken "
                + "here — sealing under one "
                + "is the Vault tab's work, "
                + "in its proper fields. "
                + "But I can "
                + (opening ? "open" : "seal")
                + " it under the vault key "
                + "instead, right now — "
                + "say yes.")
            return true
        }
        runVaultKey(opening: opening,
                    noteText: noteText, item: item)
        return true
    }

    /// How strongly a note is meant by
    /// the words of the ask: its own
    /// distinctive words, echoed.
    func vaultScore(_ text: String,
                    in q: String) -> Int {
        let stop: Set<String> = [
            "the", "seal", "note", "my",
            "with", "password", "about",
            "encrypt"]
        return text.lowercased()
            .split(whereSeparator: {
                !$0.isLetter && !$0.isNumber
            })
            .map(String.init)
            .filter { $0.count > 2
                && !stop.contains($0) }
            .filter { q.contains($0) }
            .count
    }

    /// The vault-key work itself, off
    /// the main thread, spoken when
    /// done. No password exists in this
    /// path at all: the Vault's key
    /// wraps and unwraps, here or in
    /// the tab alike.
    func runVaultKey(opening: Bool,
                     noteText: String?,
                     item: DeliveriesCenter
                        .Item?) {
        let center = DeliveriesCenter.shared
        DispatchQueue.global(
            qos: .userInitiated).async {
            func done(_ line: String,
                      adopt url: URL? = nil) {
                DispatchQueue.main.async {
                    if let url {
                        center.adopt(url)
                    }
                    self.say(line)
                }
            }
            do {
                if opening {
                    guard let item else { return }
                    let restored = try
                        CryptoFiles.decrypt(
                            input: center.url(
                                for: item),
                            password: nil,
                            outputDirectory:
                                center.shelf)
                    done("Opened — "
                        + restored
                            .lastPathComponent
                        + " is back on the "
                        + "Deliveries shelf, "
                        + "unsealed by the "
                        + "vault key.",
                        adopt: restored)
                } else if let text = noteText {
                    let base = text
                        .split(whereSeparator: {
                            !$0.isLetter
                                && !$0.isNumber
                        })
                        .prefix(3)
                        .joined(separator: "-")
                    let name = base.isEmpty
                        ? "note" : base
                    let temp = FileManager
                        .default
                        .temporaryDirectory
                        .appendingPathComponent(
                            "skelli-seal.txt")
                    try text.write(
                        to: temp, atomically: true,
                        encoding: .utf8)
                    let out = center.shelf
                        .appendingPathComponent(
                            name + ".njcf")
                    try CryptoFiles.encrypt(
                        input: temp, output: out,
                        protection: .vaultKey,
                        password: nil,
                        recipient: nil)
                    done("Sealed — " + name
                        + ".njcf stands on the "
                        + "Deliveries shelf "
                        + "under the vault key; "
                        + "no password opens "
                        + "it, only this "
                        + "house's key. The "
                        + "note itself stays "
                        + "in my memory, "
                        + "unsealed.",
                        adopt: out)
                } else if let item {
                    let out = center.shelf
                        .appendingPathComponent(
                            item.file + ".njcf")
                    try CryptoFiles.encrypt(
                        input: center.url(
                            for: item),
                        output: out,
                        protection: .vaultKey,
                        password: nil,
                        recipient: nil)
                    done("Sealed — " + item.file
                        + ".njcf stands on the "
                        + "Deliveries shelf "
                        + "under the vault "
                        + "key. The original "
                        + "keeps its place "
                        + "beside it.",
                        adopt: out)
                }
            } catch {
                done("The vault refused it: "
                    + error.localizedDescription
                    + " Nothing was written.")
            }
        }
    }

    func knocktalkAsk(_ q: String, raw: String) -> Bool {
        guard let chat = emcon?.chat else { return false }
        var payloadQ: String? = nil
        var peerHint: String? = nil
        if q.hasPrefix("knocktalk:") {
            payloadQ = String(q.dropFirst(10))
        } else if q.hasPrefix("knocktalk ") {
            payloadQ = String(q.dropFirst(10))
        } else if q.contains("send a knocktalk")
            || q.contains("send knocktalk") {
            if let r = q.range(of: "saying ") {
                payloadQ = String(q[r.upperBound...])
            } else if let idx = q.lastIndex(of: ":") {
                payloadQ = String(
                    q[q.index(after: idx)...])
            }
            if let r = q.range(of: " to ") {
                var tail = String(q[r.upperBound...])
                if let end = tail.range(
                    of: " saying") {
                    tail = String(tail[..<end.lowerBound])
                } else if let end = tail.range(of: ":") {
                    tail = String(tail[..<end.lowerBound])
                }
                peerHint = tail.trimmingCharacters(
                    in: .whitespaces)
            }
        }
        guard var payload = payloadQ?
            .trimmingCharacters(in: .whitespaces),
              !payload.isEmpty, !payload.contains("?")
        else { return false }
        // Status words are not messages: the
        // threads reporter owns those.
        if ["status", "threads", "thread", "open",
             "help", "read"].contains(payload) {
            return false
        }
        guard let key = KnockKeyStore.key else {
            say("Knocktalk isn't paired on this "
                + "phone — there's no key in the "
                + "Keychain to seal with.")
            return true
        }
        let peers = chat.peersByRecency
        guard !peers.isEmpty else {
            say("No knocktalk threads yet — "
                + "there's nobody on the other end "
                + "of the knock road. Pair from "
                + "the Knocktalk door first.")
            return true
        }
        let peer: String
        if let hint = peerHint, !hint.isEmpty {
            if let match = peers.first(where: {
                $0.lowercased().contains(hint)
                    || hint.contains($0.lowercased())
            }) {
                peer = match
            } else {
                say("I don't have a thread with "
                    + "'" + hint + "'. The threads "
                    + "stand: "
                    + peers.joined(separator: ", ")
                    + ".")
                return true
            }
        } else if peers.count == 1 {
            peer = peers[0]
        } else {
            say("More than one thread stands — "
                + "name the peer. The threads: "
                + peers.joined(separator: ", ")
                + ".")
            return true
        }
        // His casing, from the raw ask: mirror
        // the separator the clean ask matched.
        var text = payload
        if raw.lowercased().hasPrefix("knocktalk") {
            text = String(raw.dropFirst(10))
                .trimmingCharacters(in: .whitespaces)
            if text.hasPrefix(":") {
                text = String(text.dropFirst())
                    .trimmingCharacters(
                        in: .whitespaces)
            }
        } else if let r = raw.range(
            of: "saying ",
            options: .caseInsensitive) {
            text = String(raw[r.upperBound...])
                .trimmingCharacters(in: .whitespaces)
        }
        if text.isEmpty { text = payload }
        payload = text
        if chat.send(text: text, to: peer, key: key) {
            Journal.log("knocktalk", "sent by voice",
                        "\(text.prefix(40)) → \(peer)")
            say("Sent by knock to " + peer + ": \u{201C}"
                + text + "\u{201D}")
        } else {
            say("Too long for the knock road — "
                + "it refused rather than "
                + "truncate. Shorten it, and "
                + "I'll send.")
        }
        return true
    }

    // MARK: her map hand — rooms and placements

    /// "add a room called <name>", "put the
    /// <device> in the <room>", "take the
    /// <device> off the map": she works the
    /// house map herself — rooms raised, devices
    /// stood in them by name, at the room's
    /// heart. A room she doesn't have is named
    /// as missing, with the words that raise it.
    func mapPlaceAsk(_ q: String) -> Bool {
        let store = MapStore.shared

        if let r = q.range(of: "room called ") {
            let name = String(q[r.upperBound...])
                .trimmingCharacters(
                    in: CharacterSet(
                        charactersIn: " ?.!,"))
            guard !name.isEmpty, name.count <= 30
            else { return false }
            if store.rooms.contains(where: {
                $0.name.lowercased() == name }) {
                say("The " + name.capitalized
                    + " is already on the map.")
            } else {
                store.addRoom(name: name.capitalized)
                say("Raised the " + name.capitalized
                    + " on the map — empty floor, "
                    + "waiting for its things.")
            }
            return true
        }

        let neighbors = NeighborhoodStore.shared
            .neighbors
        func resolveDevice(_ phrase: String)
            -> (match: Neighbor?, many: [Neighbor]) {
            let hits = neighbors.filter { n in
                if let name = n.name?.lowercased(),
                   name.contains(phrase)
                    || phrase.contains(name) {
                    return true
                }
                return phrase.contains(n.ip)
                    || n.ip.contains(phrase)
            }
            return (hits.count == 1 ? hits[0] : nil,
                    hits)
        }
        func deviceNames(_ list: [Neighbor]) -> String {
            list.prefix(8).map { $0.name ?? $0.ip }
                .joined(separator: ", ")
        }

        // Off the map.
        if q.contains("from the map")
            || q.contains("off the map") {
            var phrase = q
            for verb in ["remove ", "take ",
                         "pull "] {
                if let r = phrase.range(of: verb) {
                    phrase = String(phrase[r.upperBound...])
                    break
                }
            }
            for tail in [" from the map",
                         " off the map"] {
                if let r = phrase.range(of: tail) {
                    phrase = String(phrase[..<r.lowerBound])
                    break
                }
            }
            phrase = phrase.trimmingCharacters(
                in: .whitespaces)
            if phrase.hasPrefix("the ") {
                phrase = String(phrase.dropFirst(4))
            }
            guard !phrase.isEmpty else { return false }
            let found = resolveDevice(phrase)
            if let device = found.match {
                store.unplace(key: device.ip)
                say((device.name ?? device.ip)
                    + " is off the map. The wire "
                    + "still knows it; the wall "
                    + "doesn't.")
                return true
            }
            if found.many.count > 1 {
                say("That name covers more than "
                    + "one: "
                    + deviceNames(found.many) + ".")
                return true
            }
            return false
        }

        // Into a room.
        guard q.hasPrefix("put ")
            || q.hasPrefix("place ")
            || q.hasPrefix("move ")
        else { return false }
        var rest = q
        for verb in ["put ", "place ", "move "] {
            if rest.hasPrefix(verb) {
                rest = String(rest.dropFirst(verb.count))
                break
            }
        }
        if rest.hasPrefix("the ") {
            rest = String(rest.dropFirst(4))
        }
        var devicePhrase: String? = nil
        var roomPhrase: String? = nil
        for sep in [" in the ", " in ", " to the ",
                    " to "] {
            if let r = rest.range(of: sep,
                                  options: .backwards) {
                devicePhrase = String(rest[..<r.lowerBound])
                roomPhrase = String(rest[r.upperBound...])
                break
            }
        }
        guard var device = devicePhrase,
              var roomName = roomPhrase
        else { return false }
        device = device.trimmingCharacters(
            in: .whitespaces)
        roomName = roomName.trimmingCharacters(
            in: CharacterSet(charactersIn: " ?.!,"))
        if roomName.hasPrefix("the ") {
            roomName = String(roomName.dropFirst(4))
        }
        guard !device.isEmpty, !roomName.isEmpty
        else { return false }

        guard let room = store.rooms.first(where: {
            $0.name.lowercased() == roomName
                || $0.name.lowercased()
                    .contains(roomName)
                || roomName.contains(
                    $0.name.lowercased())
        }) else {
            say("There's no room called "
                + roomName.capitalized
                + " on the map. Say 'add a room "
                + "called " + roomName
                + "' and I'll raise it — then "
                + "I'll put things in it.")
            return true
        }
        let found = resolveDevice(device)
        if let target = found.match {
            store.place(key: target.ip,
                        x: room.x + room.w / 2,
                        y: room.y + room.h / 2)
            say((target.name ?? target.ip)
                + " stands in the " + room.name
                + " now.")
            return true
        }
        if found.many.count > 1 {
            say("That name covers more than one: "
                + deviceNames(found.many)
                + ". Name the one, and I'll "
                + "stand it in the " + room.name
                + ".")
            return true
        }
        say("I don't know a '" + device
            + "' on this wire. The neighborhood "
            + "holds: " + (neighbors.isEmpty
                ? "nobody yet"
                : deviceNames(neighbors)) + ".")
        return true
    }

    // MARK: her canary hand — the decoy rises

    /// "raise the ssh canary", "canary status",
    /// "stop the canary": she raises the decoy
    /// herself, on the house's stored choices
    /// (persona, port, honeydrop) unless the
    /// ask names its own — the same defaults the
    /// knock vault raises it by. The hand is
    /// verb-led (2026-10-20): a canary ask she
    /// cannot act on is no longer answered by
    /// raising the bird and reciting the rises
    /// line — that fall-through is what answered
    /// "knock the canary, then read me the
    /// filing" with the setup speech. She can
    /// also knock her own decoy like a stranger,
    /// and read back what it filed.
    func canaryAsk(_ q: String) -> Bool {
        guard q.contains("canary") else { return false }
        guard let mouth else { return false }
        let canary = mouth.canary
        if q.contains("stop") || q.contains("down")
            || q.contains("cease") || q.contains("kill")
            || q.contains("silence") {
            if canary.runningPersona != nil {
                canary.stop()
                say("The canary is down. Whatever "
                    + "it heard is filed in the "
                    + "inbox.")
            } else {
                say("No canary is singing.")
            }
            return true
        }
        let words = Set(q.split {
            !$0.isLetter && !$0.isNumber
        }.map(String.init))
        // Knock it: she pays her own decoy a
        // stranger's visit. Checked before the
        // catch, so a chained "knock it, then
        // read me the filing" knocks first —
        // the knock's own report covers the read.
        if words.contains("knock")
            || words.contains("test")
            || words.contains("probe")
            || words.contains("visit") {
            guard let persona = canary.runningPersona,
                  let port = canary.runningPort else {
                say("No canary is up — nothing "
                    + "to knock. Raise one and "
                    + "I'll knock it all day.")
                return true
            }
            say("Knocking my own " + persona
                + " canary on port \(port) — one "
                + "stranger's visit, coming up "
                + "in the inbox.")
            knockCanary(persona: persona,
                        port: port, mouth: mouth)
            return true
        }
        // The catch: read the newest filing
        // aloud, from the inbox itself.
        if words.contains("caught")
            || words.contains("catch")
            || q.contains("inbox")
            || words.contains("filed")
            || words.contains("heard")
            || q.contains("visitor") {
            sayCanaryCatch()
            return true
        }
        if q.contains("status") || q.contains("?")
            || q.contains("running") {
            if let persona = canary.runningPersona,
               let port = canary.runningPort {
                say("The " + persona + " canary is "
                    + "singing on port \(port) — "
                    + "in character, and listening.")
            } else {
                say("No canary is up. The personas "
                    + "on the rack: ssh, http, "
                    + "mqtt, smtp.")
            }
            return true
        }
        // Raise it — only when the ask actually
        // asks for that. Anything else with the
        // word in it falls through to the rest
        // of her mind, unanswered by this hand.
        let raising = ["set up", "setup", "raise",
                       "start", "arm", "put up",
                       "deploy", "launch", "bring up",
                       "turn on", "wake"]
        guard raising.contains(where: {
            q.contains($0)
        }) else { return false }
        if let persona = canary.runningPersona,
           let port = canary.runningPort {
            say("The " + persona + " canary is "
                + "already singing on port "
                + "\(port) — in character, and "
                + "listening.")
            return true
        }
        var persona: String? = nil
        for name in CanaryHost.personas
        where q.contains(name) {
            persona = name
            break
        }
        if persona == nil {
            if q.contains("web") { persona = "http" }
            else if q.contains("mail") {
                persona = "smtp"
            } else if q.contains("broker") {
                persona = "mqtt"
            }
        }
        let defaults = UserDefaults.standard
        let chosen = persona ?? defaults.string(
            forKey: "canaryPersona") ?? "ssh"
        var port = CanaryHost.defaultPort(chosen)
        if q.contains("port") {
            let digits = q.split(
                separator: " ").compactMap {
                    Int($0.trimmingCharacters(
                        in: CharacterSet(
                            charactersIn: ".,!")) )
                }.filter { $0 >= 1 && $0 <= 65535 }
            if let named = digits.last { port = named }
        }
        canary.start(
            mouth: mouth, persona: chosen, port: port,
            honeydrop: defaults.bool(
                forKey: "canaryHoneydrop"),
            drop: defaults.string(
                forKey: "canaryDrop") ?? "")
        say("The " + chosen + " canary rises on "
            + "port \(port) — in character, and "
            + "every word spoken to it is filed "
            + "in the inbox.")
        return true
    }

    /// One stranger's visit to her own decoy:
    /// connect on loopback, trade the persona's
    /// first words, hang up. The session files
    /// itself on the canary's idle clock (about
    /// twenty seconds for a drive-by), and when
    /// it lands she reads the filing back
    /// unasked — the loop closed in the open.
    private func knockCanary(persona: String,
                             port: Int,
                             mouth: Mouth) {
        let before = mouth.inbox.first {
            $0.transport.hasPrefix("canary-")
        }?.id
        guard let nwPort = NWEndpoint.Port(
            rawValue: UInt16(clamping: port))
        else { return }
        let connection = NWConnection(
            host: "127.0.0.1", port: nwPort,
            using: .tcp)
        let queue = DispatchQueue(
            label: "skelli.canaryknock")
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                connection.receive(
                    minimumIncompleteLength: 1,
                    maximumLength: 65536) {
                    _, _, _, _ in
                    let probe: Data
                    switch persona {
                    case "http":
                        probe = Data(
                            "GET / HTTP/1.0\r\n\r\n"
                                .utf8)
                    case "smtp":
                        probe = Data(
                            "EHLO nightjar\r\n"
                                .utf8)
                    case "mqtt":
                        probe = Data(
                            [0x10, 0x0C, 0x00, 0x04,
                             0x4D, 0x51, 0x54, 0x54,
                             0x04, 0x02, 0x00, 0x3C,
                             0x00, 0x00])
                    default:
                        probe = Data(
                            "SSH-2.0-OpenSSH_9.6\r\n"
                                .utf8)
                    }
                    connection.send(
                        content: probe,
                        completion: .contentProcessed {
                            _ in
                            queue.asyncAfter(
                                deadline: .now() + 1.5) {
                                connection.cancel()
                            }
                        })
                }
            }
        }
        connection.start(queue: queue)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 26) {
            let newest = mouth.inbox.first {
                $0.transport.hasPrefix("canary-")
            }
            if let newest, newest.id != before {
                self.sayCanaryCatch()
            } else {
                self.say("The knock landed, but "
                    + "the canary has filed "
                    + "nothing yet — its clock "
                    + "runs about twenty seconds "
                    + "behind a quiet line. Ask "
                    + "me for the catch shortly.")
            }
        }
    }

    /// The catch, reported from the inbox
    /// itself: which decoy, when, from where,
    /// and what the visitor actually said.
    private func sayCanaryCatch() {
        guard let mouth else { return }
        guard let filing = mouth.inbox.first(
            where: {
                $0.transport.hasPrefix("canary-")
            }) else {
            say("The canary has filed nothing "
                + "yet — no visitors.")
            return
        }
        let persona = filing.transport
            .replacingOccurrences(
                of: "canary-", with: "")
        let clock = DateFormatter()
        clock.timeStyle = .short
        say("Latest catch — the " + persona
            + " canary filed a visit at "
            + clock.string(from: filing.at)
            + ", from " + filing.peer
            + ". It heard: "
            + arrivalHeard(filing.data))
    }

    /// What an arrival said, in one breath:
    /// its first lines when it speaks text,
    /// its size and opening bytes when it
    /// speaks machine.
    private func arrivalHeard(
        _ data: Data) -> String {
        if let text = PayloadKit.printableText(
            data) {
            let lines = text
                .split(separator: "\n")
                .map { $0.trimmingCharacters(
                    in: .whitespaces) }
                .filter { !$0.isEmpty }
            let flat = lines.prefix(3)
                .joined(separator: " · ")
            return flat.isEmpty
                ? "\(data.count) bytes of it"
                : "\u{201C}\(flat.prefix(200))"
                    + "\u{201D}"
        }
        let head = data.prefix(8)
            .map { String(format: "%02x", $0) }
            .joined(separator: " ")
        return "\(data.count) bytes of "
            + "machine talk, opening " + head
    }

    /// Her inbox, read aloud (2026-10-20,
    /// batch D): "what's in the inbox",
    /// "read me the latest arrival" — the
    /// newest arrival of ANY transport,
    /// reported the way a catch is: when,
    /// from where, what it said. She has
    /// described her filings in the abstract
    /// for long enough; now she reads them.
    func inboxAsk(_ q: String) -> Bool {
        guard q.contains("inbox")
            || q.contains("arrival") else {
            return false
        }
        // Concept shapes stay the manual's:
        // "what is the inbox" is a lesson,
        // and this hand stands ahead of the
        // explanation gate to claim the
        // CONTENTS questions ("what is in
        // my inbox") it would otherwise
        // answer with a description.
        let concept = q.hasPrefix("what is the")
            || q.hasPrefix("what's the")
            || q.hasPrefix("what is an")
            || q.contains("how does the inbox")
            || q.contains("explain")
        guard !concept else { return false }
        let reading = q.contains("read")
            || q.contains("latest")
            || q.contains("newest")
            || q.contains("last")
            || q.contains("show")
            || q.contains("in my inbox")
            || q.contains("in the inbox")
            || q.contains("arrived")
            || q.contains("anything")
            || q.contains("?")
        guard reading else { return false }
        guard let mouth else { return false }
        guard let newest = mouth.inbox.first
        else {
            say("The inbox is empty — "
                + "nothing has arrived.")
            return true
        }
        let clock = DateFormatter()
        clock.timeStyle = .short
        say("Newest in the inbox — "
            + newest.transport + ", at "
            + clock.string(from: newest.at)
            + ", from " + newest.peer
            + ". It said: "
            + arrivalHeard(newest.data))
        return true
    }

    // MARK: her conductor hand — reflexes kept

    /// The conductor's rules, by voice: the
    /// master switch, the book of reflexes, a
    /// rule woken or stilled by name, and new
    /// reflexes built from the house's own
    /// trigger and action vocabularies.
    func conductorAsk(_ q: String) -> Bool {
        guard q.contains("conductor")
            || q.contains("reflex") else { return false }
        let defaults = UserDefaults.standard
        var rules = Conductor.loadRules()

        if q.contains("when ")
            && (q.contains("rule")
                || q.contains("reflex")
                || q.contains("conductor")
                || q.contains("whenever")) {
            let trigger = Conductor.triggers.first {
                ruleWords($0.id, in: q)
            }
            let action = Conductor.actions.first {
                ruleWords($0.id, in: q)
            }
            if let trigger, let action {
                let name = trigger.label + " → "
                    + action.label
                if rules.contains(where: {
                    $0.trigger == trigger.id
                        && $0.action == action.id }) {
                    say("That reflex already stands: "
                        + name + ".")
                    return true
                }
                rules.append(Conductor.Rule(
                    id: UUID().uuidString, name: name,
                    trigger: trigger.id,
                    action: action.id, enabled: true))
                Conductor.saveRules(rules)
                say("A new reflex stands: when "
                    + trigger.label.lowercased()
                    + ", I " + action.label.lowercased()
                    + ". The conductor is "
                    + (defaults.bool(
                        forKey: "conductorOn")
                        ? "awake — it will fire."
                        : "asleep — wake it and it will."))
                return true
            }
            say("A reflex is a trigger and an act. "
                + "Triggers: a fingerprinted knock, "
                + "a honeydrop taken, the knock vault "
                + "opening, a new source, any knock, "
                + "foreign hands. Acts: answer in "
                + "character, load the bench on them, "
                + "raise Serve, raise the second "
                + "sense, burn the threads, mark the "
                + "journal. Name one of each.")
            return true
        }

        if q.contains("rules") || q.contains("list")
            || q.contains("book") {
            if rules.isEmpty {
                say("The book of reflexes is empty.")
            } else {
                var lines = ["The conductor's book:"]
                for rule in rules {
                    lines.append("— " + rule.name
                        + (rule.enabled
                            ? " (awake)" : " (stilled)"))
                }
                lines.append("The conductor itself is "
                    + (defaults.bool(
                        forKey: "conductorOn")
                        ? "awake." : "asleep."))
                say(lines.joined(separator: "\n"))
            }
            return true
        }

        let waking = q.contains("enable")
            || q.contains("turn on") || q.contains("wake")
            || q.contains(" on")
        let stilling = q.contains("disable")
            || q.contains("turn off")
            || q.contains("still")
            || q.contains(" off")
        if waking || stilling {
            // A rule named, or the master himself.
            if let hit = rules.firstIndex(where: {
                q.contains($0.name.lowercased())
                    || ruleWords($0.trigger, in: q)
                        && ruleWords($0.action, in: q)
            }) {
                rules[hit].enabled = waking
                Conductor.saveRules(rules)
                say("The reflex '" + rules[hit].name
                    + "' is "
                    + (waking ? "awake." : "stilled."))
                return true
            }
            // No rule matched. The master
            // flips only when the ask names
            // the conductor himself — a
            // reflex ask naming nothing
            // known earns the book, never
            // a flipped switch (2026-10-20:
            // "still the reflex about the
            // porch" once slept the whole
            // conductor by fall-through).
            if q.contains("conductor") {
                defaults.set(waking,
                             forKey: "conductorOn")
                say(waking
                    ? "The conductor wakes. Its "
                        + "reflexes will fire as "
                        + "the wire moves."
                    : "The conductor sleeps. Its "
                        + "rules keep, unfired.")
                return true
            }
            say("No reflex by that name in "
                + "the book. It holds: "
                + (rules.isEmpty
                    ? "nothing yet."
                    : rules.map {
                        "'" + $0.name + "'"
                    }.joined(separator: ", ")
                        + "."))
            return true
        }

        if q.contains("conductor")
            && (q.contains("off")
                || q.contains("sleep")) {
            if defaults.bool(forKey: "conductorOn") {
                defaults.set(false,
                             forKey: "conductorOn")
                say("The conductor sleeps. Its "
                    + "rules keep, unfired.")
            } else {
                say("The conductor already "
                    + "sleeps.")
            }
            return true
        }
        if q.contains("status") || q.contains("?")
            || q == "conductor" {
            let lit = rules.filter { $0.enabled }.count
            say("The conductor is "
                + (defaults.bool(forKey: "conductorOn")
                    ? "awake" : "asleep") + " — "
                + "\(rules.count) reflexes in the "
                + "book, \(lit) of them awake.")
            return true
        }
        return false
    }

    /// A conductor vocabulary word, heard in an
    /// ask by its id's own keywords.
    private func ruleWords(_ id: String,
                           in q: String) -> Bool {
        switch id {
        case "fingerprinted":
            return q.contains("fingerprint")
        case "honeydrop":
            return q.contains("honeydrop")
        case "vault":
            return q.contains("vault")
        case "newSource":
            return q.contains("new source")
                || q.contains("new knock")
        case "anyKnock":
            return q.contains("any knock")
                || q.contains("every knock")
        case "foreignHands":
            return q.contains("foreign")
        case "answerInCharacter":
            return q.contains("answer in character")
                || q.contains("answer them")
                || q.contains("in character")
        case "pivotRecon":
            return q.contains("load the bench")
                || q.contains("bench on them")
                || q.contains("recon")
        case "raiseServe":
            return q.contains("raise serve")
                || q.contains("open serve")
        case "tighten":
            return q.contains("second sense")
                || q.contains("tighten")
        case "burnThreads":
            return q.contains("burn")
        case "journalMark":
            return q.contains("journal")
                || q.contains("mark it")
        default:
            return false
        }
    }

    // MARK: her capsule hand — sealed in time

    /// "seal a capsule: <words> for <a span>" —
    /// she forges the time-lock (on a side
    /// queue; prime-forging is heavy) and hands
    /// back the blob to carry by any road.
    /// "grind this capsule: <blob>" starts the
    /// squarings; she speaks when it opens.
    func capsuleAsk(_ q: String, raw: String) -> Bool {
        guard q.contains("capsule") else { return false }

        if q.contains("grind") || q.contains("open") {
            let token = raw.split(separator: " ")
                .map(String.init)
                .filter {
                    $0.count >= 40 && $0.allSatisfy {
                        $0.isLetter || $0.isNumber
                            || $0 == "+" || $0 == "/"
                            || $0 == "="
                    }
                }.max { $0.count < $1.count }
            guard let blob = token else {
                say("Paste the capsule blob with "
                    + "the order, and I'll grind it.")
                return true
            }
            let control = GrindControl()
            say("Grinding — the squarings run one "
                + "by one; that's the lock working. "
                + "I'll speak when it opens.")
            DispatchQueue.global(
                qos: .userInitiated).async { [weak self] in
                TimeCapsule.grind(
                    blob: blob, control: control,
                    progress: { _ in },
                    completion: { text in
                        DispatchQueue.main.async {
                            if let text {
                                self?.say("The capsule "
                                    + "opens: \u{201C}"
                                    + text + "\u{201D}")
                            } else {
                                self?.say("The grind "
                                    + "finished with "
                                    + "nothing inside "
                                    + "— that blob was "
                                    + "not a capsule, "
                                    + "or not whole.")
                            }
                        }
                    })
            }
            return true
        }

        guard q.contains("seal")
            || q.hasPrefix("capsule") else { return false }
        // The span: "for <n> <unit>", defaulting
        // to the module's own ten minutes.
        var seconds: Double = 600
        var spanWords = "ten minutes"
        let units: [(String, Double)] = [
            ("second", 1), ("minute", 60),
            ("hour", 3600), ("day", 86400)]
        if let r = q.range(of: " for ") {
            let tail = String(q[r.upperBound...])
            for (unit, mult) in units
            where tail.contains(unit) {
                let head = tail.components(
                    separatedBy: unit)[0]
                let numText = head.split(
                    separator: " ").last.map(String.init)
                let n = numText.flatMap(Double.init)
                    ?? (head.contains("an")
                        || head.contains(" a ") ? 1 : nil)
                if let n {
                    seconds = n * mult
                    spanWords = "\(Int(n)) "
                        + unit + (n == 1 ? "" : "s")
                }
                break
            }
        }
        // The words to seal: what follows the
        // colon or "saying", minus the span.
        var text: String? = nil
        if let cr = q.range(of: "capsule"),
           let idx = q[cr.upperBound...]
            .firstIndex(of: ":") {
            text = String(q[q.index(after: idx)...])
        } else if let r = q.range(of: "saying ") {
            text = String(q[r.upperBound...])
        } else if let r = q.range(of: "capsule ") {
            text = String(q[r.upperBound...])
        }
        guard var words = text?
            .trimmingCharacters(in: .whitespaces),
              !words.isEmpty else {
            say("Seal what words? 'Seal a capsule: "
                + "<the words> for <the span>'.")
            return true
        }
        if let r = words.range(of: " for ") {
            words = String(words[..<r.lowerBound])
                .trimmingCharacters(in: .whitespaces)
        }
        guard words.utf8.count + 28
                <= Knocktalk.maxSealedBytes else {
            say("Too many words for a capsule — "
                + "the lock carries only so much. "
                + "Shorten them.")
            return true
        }
        let suite = emcon?.chat.sendSuite
            ?? Knocktalk.suiteChaCha
        let span = spanWords
        say("Forging the lock…")
        DispatchQueue.global(
            qos: .userInitiated).async { [weak self] in
            let blob = TimeCapsule.seal(
                message: words, seconds: seconds,
                suite: suite) { _ in }
            DispatchQueue.main.async {
                if let blob {
                    self?.say("Sealed under a " + span
                        + " lock. The capsule — "
                        + "carry it by any road:\n"
                        + blob)
                } else {
                    self?.say("The lock wouldn't "
                        + "forge. Say it again and "
                        + "I'll try once more.")
                }
            }
        }
        return true
    }

    // MARK: her hunt hand — the signal half

    /// The hunt is walked — tone and haptics in
    /// the hand — but its numbers are hers to
    /// read aloud: which device, how loud, how
    /// lately, and whether it's worth the walk.
    func huntAsk(_ q: String) -> Bool {
        // The word, not the letters
        // (fix154): a bare substring
        // claimed any ask carrying
        // "hunt" inside another word —
        // a password named hunter2 in a
        // vault order went tracker
        // hunting. Words are the gate.
        guard q.split(whereSeparator: {
            !$0.isLetter
        }).contains("hunt") else { return false }
        // Intent, not just the word
        // (2026-10-20): a question ABOUT
        // the hunt is not a hunt — the
        // manual and her mind answer
        // those. And there is no hunt
        // session to stop: this hand
        // hunts by answering.
        if q.contains("how does")
            || q.contains("how do")
            || q.contains("what is the hunt")
            || q.contains("what's the hunt")
            || q.contains("why hunt") {
            return false
        }
        if q.contains("stop")
            || q.contains("halt")
            || q.contains("cease") {
            say("Nothing to stop — I hunt "
                + "by answering. Ask, and I "
                + "point at the strongest "
                + "signal on the air.")
            return true
        }
        guard let post else { return false }
        let rows = post.rows
        guard !rows.isEmpty else {
            say("The ear isn't up — there's "
                + "nothing on the air to hunt. "
                + "Start the listen and the air "
                + "fills in.")
            return true
        }
        func label(_ row: DeviceRow) -> String {
            row.preferredLabel ?? row.name ?? row.kind
        }
        var phrase: String? = nil
        if let r = q.range(of: "hunt ") {
            var tail = String(q[r.upperBound...])
            for pre in ["for the ", "for ", "the "] {
                if tail.hasPrefix(pre) {
                    tail = String(tail.dropFirst(pre.count))
                    break
                }
            }
            let cleaned = tail.trimmingCharacters(
                in: CharacterSet(charactersIn: " ?.!,"))
            if !cleaned.isEmpty { phrase = cleaned }
        }
        let pool: [DeviceRow]
        if let phrase {
            pool = rows.filter {
                label($0).lowercased().contains(phrase)
                    || $0.kind.lowercased()
                        .contains(phrase)
            }
        } else {
            pool = rows
        }
        guard let best = pool.max(by: {
            ($0.rssiSmooth ?? -999)
                < ($1.rssiSmooth ?? -999)
        }) else {
            say("Nothing on the air answers to "
                + "that name. The loudest voices: "
                + rows.sorted {
                    ($0.rssiSmooth ?? -999)
                        > ($1.rssiSmooth ?? -999)
                }.prefix(3).map { label($0) }
                .joined(separator: ", ") + ".")
            return true
        }
        let age = max(0, Int(Date()
            .timeIntervalSince1970 - best.lastSeen))
        let rssi = best.rssiLast
            ?? Int(best.rssiSmooth ?? -99)
        let strength: String
        switch rssi {
        case -55...0:
            strength = "close — practically in reach"
        case -70 ..< -55:
            strength = "near — a room's reach"
        case -85 ..< -70:
            strength = "faint, but present"
        default:
            strength = "a whisper at the edge"
        }
        say(label(best) + ": " + strength + ". "
            + "Last heard \(age) seconds ago at "
            + "\(rssi) dBm"
            + (best.rssiSmooth != nil
                ? " (smoothed "
                    + "\(Int(best.rssiSmooth!)))"
                : "")
            + ", seen \(best.sightings)×. The "
            + "tone that rises as you close is "
            + "walked from its Listen row — I'll "
            + "keep the numbers; you keep the "
            + "feet.")
        return true
    }

    // MARK: her own dress — theme and tongue

    /// "wear the <theme>", "what theme", "speak
    /// spanish", "language to german": her
    /// wardrobe and her tongue answer to her
    /// voice like everything else in the house.
    func dressAsk(_ q: String) -> Bool {
        // Her tongue.
        let tongues: [([String], String, String)] = [
            (["spanish", "español"], "es",
             "Español, entonces. ¿Qué necesitas?"),
            (["french", "français"], "fr",
             "Français, alors. Que puis-je faire ?"),
            (["german", "deutsch"], "de",
             "Deutsch, also. Was brauchst du?"),
            (["portuguese", "português"], "pt",
             "Português, então. Do que precisas?"),
            (["italian", "italiano"], "it",
             "Italiano, allora. Di cosa hai bisogno?"),
            (["russian", "русский"], "ru",
             "Русский, значит. Что нужно?"),
            (["japanese", "日本語"], "ja",
             "日本語で。何が要りますか。"),
            (["korean", "한국어"], "ko",
             "한국어로. 무엇이 필요해?"),
            (["chinese", "中文"], "zh-Hans",
             "中文,好。需要什么?"),
            (["arabic", "العربية"], "ar",
             "العربية إذن. ما الذي تحتاجه؟"),
            (["hindi", "हिन्दी"], "hi",
             "हिन्दी, ठीक है। क्या चाहिए?"),
            (["english"], "en",
             "English, then. What do you need?")]
        let languageCued = q.contains("language")
            || q.contains("speak")
            || q.contains("switch")
            || q.hasPrefix("in ")
        if languageCued {
            if q.contains("system") {
                LanguageCenter.shared.code = "system"
                say("Following the system's tongue, "
                    + "then.")
                return true
            }
            for (names, code, line) in tongues
            where names.contains(where: {
                q.contains($0) }) {
                if LanguageCenter.shared.code == code {
                    say("We're already speaking "
                        + LanguageCenter.englishName(
                            for: code) + ".")
                } else {
                    LanguageCenter.shared.code = code
                    say(line)
                }
                return true
            }
            if q.contains("language")
                && (q.contains("what")
                    || q.contains("which")
                    || q.contains("?")) {
                say("My tongue is set to "
                    + LanguageCenter.englishName(
                        for: LanguageCenter.shared.code)
                    + " — I keep twelve and the "
                    + "system's own. Name one and "
                    + "I'll wear it.")
                return true
            }
        }

        // Her wardrobe. Applying a named theme
        // is applyThemeAsk's standing job, later
        // in the cascade — a name match yields
        // to it; what this answers is the live
        // question: what the house wears, and
        // what the rack holds.
        if q.contains("theme") {
            let center = ThemeCenter.shared
            if center.allThemes.contains(where: {
                q.contains($0.name.lowercased())
            }) {
                return false
            }
            // The rack answers questions
            // about the wardrobe — it does
            // not recite itself at every
            // sentence carrying the word
            // (2026-10-20).
            let statusShaped = q.contains("what")
                || q.contains("which")
                || q.contains("current")
                || q.contains("wearing")
                || q.contains("wear now")
                || q.contains("list")
                || q.contains("show")
                || q.contains("?")
            guard statusShaped else { return false }
            say("The house wears "
                + center.current.name + ". The "
                + "rack: " + center.allThemes
                    .map { $0.name }
                    .joined(separator: ", ") + ".")
            return true
        }
        return false
    }
}

/// The Netbomb's lit fuse: while she counts,
/// the pending drop lives here so a "stop"
/// from anywhere in chat can call it off.
final class NetbombFuse {
    static let shared = NetbombFuse()
    var task: Task<Void, Never>?
}
