import Foundation

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
    func macroAsk(_ q: String, raw: String) -> Bool {
        guard q.contains("macro") else { return false }
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
            let book = PayloadBook()
            let problems = MacroValidator.problems(
                in: target, book: book)
            guard problems.isEmpty else {
                say("“\(target.name)” is not ready: "
                    + problems[0])
                return true
            }
            runner.run(target, mouth: mouth, post: post,
                       emcon: emcon, book: book)
            say("Running “\(target.name)” — "
                + "\(target.blocks.count) blocks.")
            return true
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
            let hers = book.items
                .filter { $0.name.hasPrefix("Forged — ") }
                .map { $0.name }
            say("Nothing in the armory matches that."
                + (hers.isEmpty
                    ? ""
                    : " Hers on the shelf: "
                        + hers.joined(separator: "; ")
                        + "."))
            return true
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
}

