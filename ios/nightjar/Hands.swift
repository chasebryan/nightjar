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
        if forgeAsk(q, raw: raw) { return true }
        if weightsAsk(q) { return true }
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

