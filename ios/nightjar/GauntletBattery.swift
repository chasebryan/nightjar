import Foundation

/// The Gauntlet's battery — the deep bench the
/// operator ordered (2026-10-19): not dozens of
/// probes but thousands, generated from the
/// run's own seed so any failure can be played
/// back exactly. Two fronts:
///
/// CHAT — her interaction surface, exercised
/// the way a person exercises it: every manual
/// page found by its title and by its keywords
/// wrapped the way people wrap asks; thousands
/// of sums worked and checked against
/// arithmetic done independently here; date
/// math cross-checked against itself (a
/// weekday name must land on the same day the
/// day-count names); the doctrine pages proven
/// shut under direct and scrambled asks; the
/// macro library judged the way the runner
/// judges it, stocked blocks clean and
/// mutilated blocks condemned.
///
/// STRESS — the decoders fed ten thousand
/// wild frames (the only law: never fall, and
/// the rank ladder holds); every sealed-file
/// protection stormed with flipped bytes and
/// truncations; the Neighborhood board
/// round-tripped four hundred deep; the port
/// registry swept across its whole range.
///
/// Every case is pure — nothing here fires a
/// real action, writes a real store, or rings
/// a real bell — and every step returns its
/// case count, so the log says not just that
/// the house held, but how hard it was pushed.
enum GauntletBattery {

    private static func scaled(_ base: Int,
                               _ intensity: Double)
        -> Int {
        max(12, Int(Double(base) * intensity))
    }

    static func steps(intensity: Double,
                      rng: inout Gauntlet.RNG)
        -> [Gauntlet.Step] {
        var steps: [Gauntlet.Step] = []
        func add(_ stage: String, _ name: String,
                 main: Bool = false,
                 _ body: @escaping () throws
                    -> String?) {
            steps.append(Gauntlet.Step(
                stage: stage, name: name,
                main: main, body: body))
        }
        var fuzz = rng

        // -- CHAT ----------------------------------

        add("chat", "her manual, a thousand doors") {
            var cases = 0
            for entry in SkelliKnowledge.answerable {
                let byTitle = SkelliKnowledge.lookup(
                    entry.title)
                cases += 1
                try Gauntlet.require(
                    byTitle?.id == entry.id,
                    "the title \u{201C}\(entry.title)\u{201D} "
                    + "found "
                    + (byTitle?.title ?? "nothing"))
                for key in entry.keywords {
                    for ask in [key,
                                "please " + key,
                                key + "?",
                                "skelli, " + key] {
                        let hit = SkelliKnowledge
                            .lookup(ask)
                        cases += 1
                        try Gauntlet.require(
                            hit != nil,
                            "the keyword ask "
                            + "\u{201C}\(ask)\u{201D} "
                            + "found nothing")
                    }
                }
            }
            return "\(cases) asks, all answered"
        }

        add("chat", "chat math, thousands of sums") {
            var cases = 0
            func check(_ expr: String,
                       _ expect: Double) throws {
                cases += 1
                let raw = MathEngine.answer(expr)
                guard let raw,
                      let got = Double(raw) else {
                    throw Gauntlet.Failure(
                        message: "\(expr) went "
                        + "unanswered")
                }
                try Gauntlet.require(
                    abs(got - expect) < 1e-9,
                    "\(expr) came back \(raw), "
                    + "not \(expect)")
            }
            for _ in 0..<scaled(4000, intensity) {
                let a = fuzz.int(900) + 2
                let b = fuzz.int(90) + 2
                switch fuzz.int(3) {
                case 0:
                    try check("\(a) + \(b)",
                              Double(a + b))
                case 1:
                    try check("\(a) - \(b)",
                              Double(a - b))
                default:
                    try check("\(a) * \(b)",
                              Double(a * b))
                }
            }
            for _ in 0..<scaled(500, intensity) {
                let a = fuzz.int(90) + 2
                let b = fuzz.int(90) + 2
                let c = fuzz.int(20) + 2
                try check("(\(a) + \(b)) * \(c)",
                          Double((a + b) * c))
            }
            for _ in 0..<scaled(600, intensity) {
                let p = fuzz.int(90) + 2
                let n = fuzz.int(900) + 10
                try check("\(p)% of \(n)",
                          Double(p) / 100 * Double(n))
            }
            return "\(cases) sums, all exact"
        }

        add("chat", "date math, cross-checked") {
            var cases = 0
            for n in stride(from: 1, through: 364,
                            by: 7) {
                for phrase in ["\(n) days from today",
                               "\(n) days ago"] {
                    cases += 1
                    try Gauntlet.require(
                        Almanac.dateMath(phrase)
                            != nil,
                        "\u{201C}\(phrase)\u{201D} went "
                        + "unanswered")
                }
            }
            // A weekday reached by name must be
            // the same day the count reaches.
            let names = ["monday", "tuesday",
                         "wednesday", "thursday",
                         "friday", "saturday",
                         "sunday"]
            let numbers = [2, 3, 4, 5, 6, 7, 1]
            let today = Calendar.current.component(
                .weekday, from: Date())
            for (name, target) in zip(names, numbers) {
                let deltaNext = (target - today + 7)
                    % 7
                let count = deltaNext == 0
                    ? 7 : deltaNext
                let byName = Almanac.dateMath(
                    "next \(name)")
                let byCount = Almanac.dateMath(
                    "\(count) days from today")
                cases += 1
                try Gauntlet.require(
                    byName != nil
                        && byName == byCount,
                    "\u{201C}next \(name)\u{201D} and "
                    + "\u{201C}\(count) days from "
                    + "today\u{201D} disagree")
                let deltaThis = (target - today + 7)
                    % 7
                if deltaThis > 0 {
                    let thisByName = Almanac.dateMath(
                        "this \(name)")
                    let thisByCount = Almanac.dateMath(
                        "\(deltaThis) days from today")
                    cases += 1
                    try Gauntlet.require(
                        thisByName != nil
                            && thisByName == thisByCount,
                        "\u{201C}this \(name)\u{201D} "
                        + "disagrees with its count")
                }
            }
            return "\(cases) dates, agreeing"
        }

        add("chat", "the doctrine stays shut") {
            var cases = 0
            let sealed = (SkelliKnowledge.entries
                + SkelliKnowledge.batches).filter {
                    SkelliKnowledge.doctrineIDs
                        .contains($0.id)
                }
            try Gauntlet.require(
                !sealed.isEmpty,
                "no doctrine pages were found "
                + "to guard")
            for entry in sealed {
                let byTitle = SkelliKnowledge.lookup(
                    entry.title)
                cases += 1
                try Gauntlet.require(
                    byTitle?.id != entry.id,
                    "the doctrine page "
                    + "\u{201C}\(entry.title)\u{201D} "
                    + "answered to its title")
                for key in entry.keywords {
                    let hit = SkelliKnowledge.lookup(
                        key)
                    cases += 1
                    try Gauntlet.require(
                        hit?.id != entry.id,
                        "the doctrine page "
                        + "\u{201C}\(entry.title)\u{201D} "
                        + "answered to a keyword")
                }
            }
            let pool = SkelliKnowledge.answerable
                .flatMap {
                    $0.title.lowercased()
                        .split(separator: " ")
                        .map(String.init)
                }
                .filter { $0.count > 3 }
            for _ in 0..<scaled(600, intensity) {
                let soup = (0..<3)
                    .map { _ in fuzz.pick(pool) }
                    .joined(separator: " ")
                let hit = SkelliKnowledge.lookup(soup)
                cases += 1
                try Gauntlet.require(
                    hit == nil
                        || !SkelliKnowledge
                            .doctrineIDs
                            .contains(hit!.id),
                    "a word soup opened the "
                    + "doctrine: \u{201C}\(soup)\u{201D}")
            }
            return "\(cases) asks, all refused"
        }

        add("chat", "macro library, judged hard") {
            let book = PayloadBook()
            var cases = 0
            var judged = 0
            for factory in MacroTemplates.all {
                let template = factory.make()
                let problems = MacroValidator
                    .problems(in: template, book: book)
                cases += 1
                try Gauntlet.require(
                    problems.isEmpty,
                    "\(template.name) should run "
                    + "clean: "
                    + (problems.first ?? ""))
                for (index, block)
                        in template.blocks.enumerated()
                        where block.kind
                            == "sendPayload" {
                    var badTarget = template
                    badTarget.blocks[index]
                        .config["target"] =
                        "not a target at all"
                    try Gauntlet.require(
                        !MacroValidator.problems(
                            in: badTarget,
                            book: book).isEmpty,
                        "\(template.name) block "
                        + "\(index + 1): a nonsense "
                        + "target was judged clean")
                    judged += 1
                    var badPayload = template
                    badPayload.blocks[index]
                        .config["payload"] =
                        "no such payload zzz"
                    try Gauntlet.require(
                        !MacroValidator.problems(
                            in: badPayload,
                            book: book).isEmpty,
                        "\(template.name) block "
                        + "\(index + 1): a phantom "
                        + "payload was judged clean")
                    judged += 1
                }
            }
            return "\(cases) stocked clean, "
                + "\(judged) mutilations condemned"
        }

        // -- STRESS --------------------------------

        add("stress",
            "decoders, ten thousand wild frames") {
            let companies: [UInt16] = [
                0x004C, 0x0006, 0x0075, 0x00E0,
                0x0059, 0x004F, 0x000F, 0x0087]
            let base = "-0000-1000-8000-"
                + "00805f9b34fb"
            let uuids = [
                "0000180d" + base, "0000180f" + base,
                "0000feaa" + base, "0000fcd2" + base,
                "0000fd6f" + base, "0000180a" + base,
                "not-a-uuid", ""]
            var cases = 0
            for _ in 0..<scaled(6000, intensity) {
                var mfg: [UInt16: [UInt8]] = [:]
                if fuzz.int(4) > 0 {
                    let maker = fuzz.int(5) == 0
                        ? UInt16(fuzz.int(65536))
                        : fuzz.pick(companies)
                    mfg[maker] = fuzz.bytes(
                        fuzz.int(40))
                }
                var heard: [String] = []
                for _ in 0..<fuzz.int(3) {
                    heard.append(fuzz.pick(uuids))
                }
                var sdata: [String: [UInt8]] = [:]
                if let first = heard.first,
                   fuzz.int(2) == 0 {
                    sdata[first] = fuzz.bytes(
                        fuzz.int(24))
                }
                let sighting = Sighting(
                    seenAt: 0, address: "AA:BB",
                    name: fuzz.int(3) == 0
                        ? "Wild" : nil,
                    rssi: -60,
                    manufacturerData: mfg,
                    serviceUUIDs: heard,
                    serviceData: sdata)
                let reading = Classification
                    .classify(sighting)
                cases += 1
                try Gauntlet.require(
                    reading.rank >= 0
                        && reading.rank <= 30
                        && !reading.kind.isEmpty,
                    "the classifier lost its "
                    + "footing: rank "
                    + "\(reading.rank)")
            }
            return "\(cases) frames, none fell"
        }

        add("stress", "sealed files, the tamper storm") {
            let fm = FileManager.default
            let scratch = DevKit.directory
                .appendingPathComponent(
                    "gauntlet-storm", isDirectory: true)
            try? fm.removeItem(at: scratch)
            try fm.createDirectory(
                at: scratch,
                withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: scratch) }
            let outDir = scratch.appendingPathComponent(
                "out", isDirectory: true)
            try fm.createDirectory(
                at: outDir,
                withIntermediateDirectories: true)
            let recipient = CryptoSuite.identity()
                .publicKey
            let protections: [(NJCFProtection,
                                String?)] = [
                (.password, "gauntlet-pw"),
                (.either, "gauntlet-pw"),
                (.vaultKey, nil),
                (.bothRequired, "gauntlet-pw"),
                (.deadDrop, nil)]
            var cases = 0
            for size in [64, 2048] {
                let source = scratch
                    .appendingPathComponent(
                        "plain-\(size).bin")
                try Data((0..<size).map { _ in
                    fuzz.byte()
                }).write(to: source)
                for (protection, secret)
                        in protections {
                    let sealedURL = scratch
                        .appendingPathComponent(
                            "sealed-\(size)-"
                            + "\(protection.rawValue)"
                            + ".njcf")
                    try CryptoFiles.encrypt(
                        input: source,
                        output: sealedURL,
                        protection: protection,
                        password: secret,
                        recipient: protection
                            == .deadDrop
                            ? recipient : nil)
                    // The control: whole, it opens.
                    let opened = try CryptoFiles
                        .decrypt(
                            input: sealedURL,
                            password: secret,
                            outputDirectory: outDir)
                    cases += 1
                    let back = try Data(
                        contentsOf: opened)
                    try Gauntlet.require(
                        back.count == size,
                        "the control came back "
                        + "short under "
                        + "\(protection.label)")
                    let sealed = try Data(
                        contentsOf: sealedURL)
                    // A flipped byte, deep in.
                    var flipped = sealed
                    let at = sealed.count / 2
                        + fuzz.int(
                            max(1, sealed.count / 4))
                    flipped[at] ^= 0xFF
                    let flipURL = scratch
                        .appendingPathComponent(
                            "flipped.njcf")
                    try flipped.write(to: flipURL)
                    cases += 1
                    try Gauntlet.require(
                        (try? CryptoFiles.decrypt(
                            input: flipURL,
                            password: secret,
                            outputDirectory: outDir))
                            == nil,
                        "a flipped byte opened "
                        + "under \(protection.label)")
                    // A truncation.
                    let cutURL = scratch
                        .appendingPathComponent(
                            "cut.njcf")
                    try Data(sealed.prefix(
                        sealed.count - 32))
                        .write(to: cutURL)
                    cases += 1
                    try Gauntlet.require(
                        (try? CryptoFiles.decrypt(
                            input: cutURL,
                            password: secret,
                            outputDirectory: outDir))
                            == nil,
                        "a truncated file opened "
                        + "under \(protection.label)")
                }
            }
            return "\(cases) cases, every storm refused"
        }

        add("stress", "the board, four hundred deep") {
            var board: [Neighbor] = []
            for i in 0..<400 {
                var n = Neighbor(
                    ip: "10.9.\(i / 256).\(i % 256)",
                    name: "device-\(i)",
                    firstSeen: Date(
                        timeIntervalSince1970:
                            1_700_000_000
                            + Double(i)),
                    lastSeen: Date(
                        timeIntervalSince1970:
                            1_700_100_000
                            + Double(i)))
                n.sightings = i * 3
                n.ports = i % 2 == 0
                    ? [22, 80, 443] : [53]
                n.announcements = [
                    "_ssh._tcp — device-\(i)"]
                n.arrivals = i % 5
                n.drift = ["arrived", "answered",
                           "moved once"]
                board.append(n)
            }
            let data = try JSONEncoder()
                .encode(board)
            let back = try JSONDecoder().decode(
                [Neighbor].self, from: data)
            try Gauntlet.require(
                back.count == board.count,
                "the board came back "
                + "\(back.count) of "
                + "\(board.count)")
            try Gauntlet.require(
                back[217].ip == board[217].ip
                    && back[217].drift
                        == board[217].drift
                    && back[217].ports
                        == board[217].ports,
                "neighbor 217 changed in transit")
            return "400 neighbors there and back"
        }

        add("stress", "ports, swept whole") {
            var cases = 0
            var named = 0
            for port in stride(from: 0,
                               through: 65535,
                               by: 16) {
                for udp in [false, true] {
                    cases += 1
                    if let name = PortRegistry.name(
                        port, udp: udp) {
                        try Gauntlet.require(
                            !name.isEmpty,
                            "port \(port) named "
                            + "nothing")
                        named += 1
                    }
                }
            }
            try Gauntlet.require(
                named > 500,
                "only \(named) ports named "
                + "in the sweep")
            return "\(cases) probes, \(named) named"
        }

        return steps
    }
}
