import Foundation

/// The sky and the garden.
///
/// She is an instrument of the wire, but she is
/// not ONLY that: the moon over the house is
/// computed exactly in her almanac and answered
/// for wherever on Earth it is asked about; the
/// zodiac is kept as the lore it is, respectfully
/// and with her dry affection; the planets are
/// answered from the stable facts; and the
/// language of flowers — the old floriography —
/// is a tongue she speaks fluently, because what
/// a bouquet says matters to the people sending
/// it. Romance runs through the occasions: the
/// apology, the anniversary, the declaration —
/// she knows which flower carries which words.

extension SkelliCenter {

    // MARK: the language of flowers

    /// (flower, color or "", meaning). Color is
    /// matched when the ask names one; the plain
    /// entry carries the flower's general word.
    private static let flowerBook: [(String, String,
                                     String)] = [
        ("forget-me-not", "",
         "remembrance — true love, and 'exactly what my name says'"),
        ("purple hyacinth", "",
         "sorrow, and a plea: forgive me"),
        ("hyacinth", "",
         "sincerity and sorrow, by its color"),
        ("white tulip", "",
         "an apology — 'I am sorry', said without a word"),
        ("red tulip", "",
         "a declaration of love, plainly made"),
        ("tulip", "",
         "a declaration of love — the color aims it"),
        ("red rose", "",
         "love, deep and declared"),
        ("white rose", "",
         "purity, and a new beginning"),
        ("pink rose", "",
         "gratitude and admiration"),
        ("yellow rose", "",
         "friendship, and joy in it"),
        ("lavender rose", "",
         "enchantment — love at first sight"),
        ("rose", "",
         "love — the color carries the tense of it"),
        ("white lily", "",
         "sympathy, and purity restored"),
        ("calla lily", "",
         "magnificent beauty, and rebirth"),
        ("lily", "",
         "purity and renewal — the white ones speak sympathy"),
        ("sunflower", "",
         "devotion and adoration; it only faces one way"),
        ("peony", "",
         "a happy marriage, prosperity — and a bashful romance"),
        ("orchid", "",
         "rare beauty, strength, and luxury"),
        ("daffodil", "",
         "rebirth and new beginnings — and regard"),
        ("daisy", "",
         "innocence, and cheer that means it"),
        ("violet", "",
         "faithfulness, and modesty"),
        ("iris", "",
         "hope, faith — and a message carried"),
        ("lavender", "",
         "devotion, and calm"),
        ("gardenia", "",
         "a secret love"),
        ("sweet pea", "",
         "gratitude — and a blissful farewell"),
        ("baby's breath", "",
         "everlasting love"),
        ("pink carnation", "",
         "a mother's love, and gratitude"),
        ("carnation", "",
         "fascination and devotion, by its color"),
        ("hydrangea", "",
         "heartfelt emotion — in older tellings, an apology"),
        ("bluebell", "",
         "humility, and constancy")]

    private static let flowerOccasions:
        [(words: [String], answer: String)] = [
        (["apolog", "sorry", "forgive"],
         "For an apology: white tulips say it "
            + "cleanest — 'I am sorry' without a "
            + "word. The purple hyacinth is the "
            + "older, sadder plea: forgive me."),
        (["sympath", "funeral", "condolence",
          "loss"],
         "For sympathy: white lilies. They carry "
            + "grief without making a show of it."),
        (["anniversary", "valentine", "romance",
          "romantic", "love"],
         "For love, by its stage: red roses when "
            + "it is deep and declared; peonies for "
            + "a marriage's happy prosperity; red "
            + "tulips for a declaration being made "
            + "the first time."),
        (["friend"],
         "For a friend: yellow roses — friendship "
            + "and joy in it, nothing heavier "
            + "smuggled in."),
        (["thank", "gratitude", "grateful"],
         "For gratitude: pink roses, or sweet "
            + "peas — thanks with a light hand."),
        (["baby", "newborn"],
         "For a new baby: daffodils — rebirth and "
            + "a beginning, and they look like "
            + "morning."),
        (["wedding", "marriage", "bride"],
         "For a wedding: peonies and white "
            + "roses — a happy marriage, and a "
            + "new beginning to carry it."),
        (["well", "sick", "hospital", "recover"],
         "For the sick room: daisies or bright "
            + "tulips — cheer that means it, and "
            + "nothing funereal in a vase.")]

    // MARK: the lane

    func skyBloomAsk(_ q: String) -> Bool {
        // The moon's distance, asked plainly.
        if q.contains("how far") && q.contains("moon") {
            say("About 384,400 kilometres, on "
                + "average — it drifts closer and "
                + "farther by some 40,000 across "
                + "its month, and away from us by "
                + "nearly 4 centimetres a year.")
            return true
        }
        // The moon — as a word of its own, so a
        // honeymoon is left to the humans and the
        // landing is left to history.
        let moonTokens = q.split(separator: " ")
            .map { $0.trimmingCharacters(
                in: CharacterSet(
                    charactersIn: ".,!?")) }
        if (moonTokens.contains("moon")
            || q.contains("full moon")
            || q.contains("new moon"))
            && !q.contains("landing")
            && !q.contains("apollo") {
            return moonAsk(q)
        }
        // The planets, from the stable facts.
        if let fact = planetFact(q) {
            say(fact)
            return true
        }
        // The wheel: a named sign, a date, or his
        // own kept birthday.
        if let line = zodiacAsk(q) {
            say(line)
            return true
        }
        // The garden: meanings and occasions.
        if let line = flowerAsk(q) {
            say(line)
            return true
        }
        return false
    }

    // MARK: the moon

    private func moonAsk(_ q: String) -> Bool {
        let now = Date()
        let months = ["january", "february", "march",
                      "april", "may", "june", "july",
                      "august", "september", "october",
                      "november", "december"]
        // A named month: that month's full moon.
        if q.contains("full moon"),
           let mi = months.firstIndex(where: {
               q.contains($0) }) {
            let month = mi + 1
            let cal = Calendar.current
            let year = cal.component(.year, from: now)
            var full = Almanac.nextFullMoon(
                after: Almanac.makeDate(year, month, 1))
            var hops = 0
            while cal.component(.month, from: full)
                    != month && hops < 2 {
                full = Almanac.nextFullMoon(after: full)
                hops += 1
            }
            if cal.component(.month, from: full)
                == month {
                say("The full moon of "
                    + months[mi].capitalized + " falls "
                    + "on " + Almanac.spell(full)
                    + " — the "
                    + Almanac.fullMoonName(month: month)
                    + ".")
            } else {
                // A rare year: the month holds no
                // full moon at all. Said plainly,
                // with the nearest one named.
                say(months[mi].capitalized + " holds "
                    + "no full moon this year — the "
                    + "nearest stands on "
                    + Almanac.spell(full) + ", the "
                    + Almanac.fullMoonName(
                        month: cal.component(
                            .month, from: full)) + ".")
            }
            return true
        }
        if q.contains("full moon")
            && (q.contains("when") || q.contains("next")) {
            let age = Almanac.moonAge(at: now)
            if age >= 13.8 && age <= 15.8 {
                let m = Calendar.current.component(
                    .month, from: now)
                say("Tonight — the moon stands full, "
                    + "the "
                    + Almanac.fullMoonName(month: m)
                    + ".")
            } else {
                let full = Almanac.nextFullMoon(
                    after: now)
                let m = Calendar.current.component(
                    .month, from: full)
                say("The next full moon is "
                    + Almanac.spell(full) + " — the "
                    + Almanac.fullMoonName(month: m)
                    + ".")
            }
            return true
        }
        if q.contains("new moon")
            && (q.contains("when") || q.contains("next")) {
            say("The next new moon is "
                + Almanac.spell(Almanac.nextNewMoon(
                    after: now))
                + " — the sky's blank page.")
            return true
        }
        // Elsewhere: that place's own tonight.
        if let range = q.range(of: " in ") {
            var place = String(q[range.upperBound...])
                .trimmingCharacters(
                    in: CharacterSet(
                        charactersIn: " ?.!,"))
            for tail in [" tonight", " today",
                         " right now"] {
                if place.hasSuffix(tail) {
                    place = String(
                        place.dropLast(tail.count))
                }
            }
            if !place.isEmpty && place.count <= 40
                && !months.contains(place) {
                Task { [weak self] in
                    guard let self else { return }
                    if let hit = await PlaceCenter
                        .shared.geocode(place) {
                        let phase = Almanac.moonPhase(
                            at: now)
                        let dayFmt = DateFormatter()
                        dayFmt.timeZone = hit.tz
                        dayFmt.dateFormat = "EEEE"
                        self.say("Over \(hit.name): "
                            + "the moon tonight is "
                            + phase.name.lowercased()
                            + " — \(phase.illumination)% "
                            + "lit, on their "
                            + dayFmt.string(from: now)
                            + ".")
                    } else {
                        self.say("I can't find "
                            + place + " on the map "
                            + "I have.")
                    }
                }
                return true
            }
        }
        // Here, tonight.
        let phase = Almanac.moonPhase(at: now)
        let age = Almanac.moonAge(at: now)
        let full = Almanac.nextFullMoon(after: now)
        let fm = Calendar.current.component(.month,
                                            from: full)
        say("The moon tonight: "
            + phase.name.lowercased() + " — "
            + "\(phase.illumination)% lit, "
            + "\(Int(age.rounded())) days into its "
            + "cycle. Full on " + Almanac.spell(full)
            + " — the "
            + Almanac.fullMoonName(month: fm) + ".")
        return true
    }

    // MARK: the wheel

    private func zodiacAsk(_ q: String) -> String? {
        let names = Almanac.zodiacTable.map {
            $0.name.lowercased() }
        // A sign's dates — claimed only in the
        // wheel's own company, so a hard word
        // like Cancer is never answered with
        // astrology when life is meant.
        if let hit = names.first(where: {
            q.contains($0) }),
           !q.contains("awareness"),
           q.contains("sign") || q.contains("zodiac")
            || q.contains("dates")
            || q.contains("season")
            || q.hasPrefix("when is ") {
            if let found = Almanac.zodiacNamed(hit) {
                return "\(hit.capitalized) runs "
                    + found.range + ". " + found.trait
            }
        }
        let asksMine = q.contains("my sign")
            || q.contains("my zodiac")
            || q.contains("am i a")
        var monthDay: (Int, Int)? = nil
        if asksMine, let kept = Almanac.birthday {
            monthDay = (kept.month, kept.day)
        } else if let parsed = dateInAsk(q) {
            monthDay = parsed
        }
        if asksMine && monthDay == nil {
            return "Tell me the date plainly — "
                + "'my birthday is June 5' — and "
                + "I'll keep it and read the wheel "
                + "from it."
        }
        if asksMine
            || (monthDay != nil && q.contains("born")) {
            if let (m, d) = monthDay {
                let z = Almanac.zodiac(month: m, day: d)
                var line = Almanac.spellMonthDay(m, d)
                    + " is " + z.name + ". " + z.trait
                if z.cusp {
                    line += " You stand within a day "
                        + "of the cusp — the exact "
                        + "hour of birth settles "
                        + "which side."
                }
                return line
            }
        }
        return nil
    }

    /// A month name and a day number, side by
    /// side, anywhere in the ask.
    private func dateInAsk(_ q: String) -> (Int, Int)? {
        let months = ["january", "february", "march",
                      "april", "may", "june", "july",
                      "august", "september", "october",
                      "november", "december"]
        let tokens = q.split(separator: " ")
            .map { $0.trimmingCharacters(
                in: CharacterSet(
                    charactersIn: ".,!?")) }
        for (i, token) in tokens.enumerated() {
            if let mi = months.firstIndex(of: token) {
                if i + 1 < tokens.count,
                   let d = Int(tokens[i + 1]),
                   d >= 1 && d <= 31 {
                    return (mi + 1, d)
                }
                if i > 0, let d = Int(tokens[i - 1]),
                   d >= 1 && d <= 31 {
                    return (mi + 1, d)
                }
            }
        }
        return nil
    }

    // MARK: the garden

    private func flowerAsk(_ q: String) -> String? {
        // Occasions first: what to SEND speaks
        // before what a flower means.
        if q.contains("flower") {
            for occasion in Self.flowerOccasions
            where occasion.words.contains(where: {
                q.contains($0) }) {
                return occasion.answer
            }
        }
        guard q.contains("mean")
            || q.contains("symbol")
            || q.contains("say with")
        else { return nil }
        // The longest name wins: a forget-me-not
        // is not a rose, and a red rose outranks
        // the family line. Plain plurals are
        // substrings for free; the -ies plurals
        // (lilies, daisies) get their own form.
        let sorted = Self.flowerBook.sorted {
            $0.0.count > $1.0.count }
        for (flower, _, meaning) in sorted {
            var forms = [flower]
            if flower.hasSuffix("y") {
                forms.append(
                    String(flower.dropLast()) + "ies")
            }
            if forms.contains(where: {
                q.contains($0) }) {
                return "The \(flower): \(meaning)."
            }
        }
        return nil
    }

    // MARK: the planets

    private func planetFact(_ q: String) -> String? {
        if q.contains("largest planet")
            || q.contains("biggest planet") {
            return "Jupiter — more massive than "
                + "every other planet combined, "
                + "twice over."
        }
        if q.contains("smallest planet") {
            return "Mercury — barely wider than "
                + "the Atlantic, and shrinking "
                + "as it cools."
        }
        if q.contains("closest planet")
            && q.contains("sun") {
            return "Mercury — 58 million "
                + "kilometres out, a year of "
                + "88 days."
        }
        if q.contains("red planet") {
            return "Mars — iron oxide dust. It is "
                + "not red like fire; it is red "
                + "like rust."
        }
        if q.contains("hottest planet") {
            return "Venus — some 465 degrees "
                + "under its blanket of cloud, "
                + "hotter than Mercury for all "
                + "its distance."
        }
        if q.contains("rings") && q.contains("planet") {
            return "Saturn wears the grand rings. "
                + "All four giants carry rings — "
                + "only Saturn's announce "
                + "themselves."
        }
        if q.contains("how many planets") {
            return "Eight — Mercury out to "
                + "Neptune. Pluto keeps its dwarf "
                + "title, and its dignity."
        }
        if q.contains("order of the planets")
            || q.contains("planets in order") {
            return "Mercury, Venus, Earth, Mars, "
                + "Jupiter, Saturn, Uranus, "
                + "Neptune."
        }
        if q.contains("how far") && q.contains("sun") {
            return "About 149.6 million "
                + "kilometres — one astronomical "
                + "unit; light makes the trip in "
                + "eight minutes and a breath."
        }
        return nil
    }
}
