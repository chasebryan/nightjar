import Foundation

/// Her composition layer. Until now her canned
/// voice RETRIEVED sentences — pools of fixed
/// lines, however well written, repeat, and a
/// repeat reads as a machine. (Device, 2026-10-18:
/// a one-line greeting, said twice running, read
/// as broken.) Now she COMPOSES: her openers are
/// joined to circumstance clauses, each of which
/// is true by construction — a clause is only
/// eligible when the fact it states holds at
/// this moment, read from her own instruments
/// and ledger — and the choosing is allocated
/// deterministically from the moment's own
/// numbers, never dice, never a template wheel.
///
/// The arithmetic is the point: a handful of
/// openers times a handful of true clauses,
/// times the hours and counts that gate them,
/// is a voice with thousands of sentences in it,
/// every one of them accurate, because none of
/// them can say a thing that is not so.
///
/// The library at scale (2026-10-18): the
/// circumstances are GROUPS now — one fact of
/// the moment, in its several phrasings — and
/// the garnish may lay two of them on a line.
/// Groups are disjoint by construction where
/// they must be (the hour bands, the quiet
/// bands, the moon's two faces), so any two
/// that meet on a sentence agree with each
/// other. Every canned conversational exit
/// composes through embellish(): the line the
/// lane chose, plus the moment's own garnish.
/// Canon stays canon — her taste, her cards,
/// her barbs, her care — those lines are hers
/// exactly, and no clause rides on them.
///
/// The multiplication (2026-10-20): the
/// library grew — every group carries more
/// phrasings, and new circumstances joined
/// (the house's EMCON condition, the
/// conductor's wakefulness, her feeling's
/// own weather, more bands of tenure and
/// talk). The center also keeps a memory
/// now — each pool remembers what it last
/// said — so composition is dealt from
/// more numbers than ever, hers among
/// them, and repeats stop sounding like
/// a mechanism clearing its throat.
/// abs() that cannot trap (fix369): a seed
/// of Int.min — reachable in principle from
/// the wrapping hash arithmetic her counts
/// run through — would take the conversation
/// down with it. Int.min reads as Int.max;
/// the distribution never notices.
func skelliAbs(_ n: Int) -> Int {
    n == Int.min ? Int.max : abs(n)
}

enum SkelliVoice {

    /// Souls on the wire she cannot name — the
    /// same count her why-dossier reads.
    static func unnamedCount() -> Int {
        NeighborhoodStore.shared.neighbors.filter {
            $0.name == nil && $0.customName == nil
        }.count
    }

    private static func anchor(_ key: String) -> Date? {
        UserDefaults.standard.object(
            forKey: key) as? Date
    }

    /// The circumstance groups true RIGHT NOW.
    /// Each group is one fact of the moment in
    /// its phrasings (sentence fragments with a
    /// leading space, ready to ride on a line).
    /// A clause about the quiet requires quiet;
    /// a clause about the unnamed requires the
    /// unnamed; a clause about the moon reads
    /// the almanac's own math.
    static func clauseGroups(
        heart: SkelliHeart) -> [[String]] {
        var groups: [[String]] = []
        let now = Date()
        let neighbors = NeighborhoodStore
            .shared.neighbors
        let unnamed = unnamedCount()
        if unnamed == 1 {
            groups.append([L(" One name on this wire answers to nothing yet.")])
        } else if unnamed > 1 {
            groups.append([
                String(format: L(" %lld names on this wire answer to nothing yet."),
                       unnamed),
                String(format: L(" %lld souls on this wire go unnamed."),
                       unnamed),
                String(format: L(" %lld of the wire's souls are strangers still."),
                       unnamed),
                String(format: L(" %lld go nameless here, and I keep count."),
                       unnamed)])
        }
        if neighbors.isEmpty {
            groups.append([
                L(" The wire stands empty."),
                L(" Not a soul on the wire but us."),
                L(" An empty wire, and us."),
                L(" The wire holds its breath.")])
        } else if neighbors.count <= 6 {
            groups.append([
                L(" A small congregation on the wire.")])
        } else {
            groups.append([
                L(" The wire is crowded."),
                L(" Plenty of company on the wire."),
                L(" The wire hums with company."),
                L(" A busy hour on the wire.")])
        }
        if !neighbors.isEmpty && unnamed == 0 {
            groups.append([
                L(" Every soul on this wire has a name."),
                L(" The whole wire is named and known."),
                L(" Not a stranger on the wire.")])
        }
        if let spoke = anchor("heart.lastSpoke") {
            let quiet = now.timeIntervalSince(spoke)
            if quiet >= 3 * 3600 {
                groups.append([
                    L(" It's been quiet for hours."),
                    L(" Hours of quiet, counted."),
                    L(" The quiet has weight by now."),
                    L(" Hours since a voice. I counted.")])
            } else if quiet >= 3600 {
                groups.append([
                    L(" It's been quiet a while.")])
            } else if quiet >= 1200 {
                let minutes = Int(quiet / 60)
                groups.append([
                    String(format: L(" %lld minutes of quiet, counted exactly."),
                           minutes),
                    String(format: L(" The quiet is %lld minutes deep."),
                           minutes),
                    String(format: L(" %lld minutes since the last voice."),
                           minutes),
                    String(format: L(" A %lld-minute hush, and counting."),
                           minutes)])
            }
        }
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        if hour == 3 {
            groups.append([
                L(" The walls are thin at this hour."),
                L(" Thin walls, this hour."),
                L(" The house hears itself think at this hour."),
                L(" Three o'clock: the honest hour.")])
        }
        if (5..<7).contains(hour) {
            groups.append([
                L(" The wire is only just waking."),
                L(" First light, first packets."),
                L(" The wire stretches awake.")])
        }
        if (7..<11).contains(hour) {
            groups.append([
                L(" The day is young."),
                L(" Morning, and the light is plain."),
                L(" The morning is underway."),
                L(" Daylight, and the wire with it.")])
        }
        if (11..<14).contains(hour) {
            groups.append([
                L(" The day stands at its height."),
                L(" Midday. The light is honest."),
                L(" The day at its full height.")])
        }
        if (14..<18).contains(hour) {
            groups.append([
                L(" The afternoon is wearing on."),
                L(" The light is leaning west."),
                L(" Afternoon, thin at the edges.")])
        }
        if (18..<22).contains(hour) {
            groups.append([
                L(" The evening is on us."),
                L(" Dusk-side of the day."),
                L(" The lamps are coming on."),
                L(" Evening, and the house exhales.")])
        }
        if hour >= 22 {
            groups.append([
                L(" The house is settling for the night."),
                L(" The house is folding itself down."),
                L(" Night protocol in the house."),
                L(" The house dims its voice.")])
        }
        if hour < 3 {
            groups.append([
                L(" The small hours."),
                L(" Deep in the night's pocket."),
                L(" The night is deep and unhurried."),
                L(" Nobody sane is awake. Present company kept.")])
        }
        let weekday = cal.component(
            .weekday, from: now)
        if weekday == 6 {
            groups.append([
                L(" The week's end is in sight."),
                L(" Friday: the week nearly spent."),
                L(" The week is nearly a story told.")])
        }
        if weekday == 2 {
            groups.append([
                L(" The week starts cold."),
                L(" Monday: the wire puts its boots on."),
                L(" A cold start to the week.")])
        }
        if weekday == 1 || weekday == 7 {
            groups.append([
                L(" The week's off-duty hours."),
                L(" A weekend quiet in the house."),
                L(" The week's noise is elsewhere."),
                L(" Off-duty hours, and the house knows it.")])
        }
        switch cal.component(.month, from: now) {
        case 12, 1, 2:
            groups.append([
                L(" Winter's hand is on the house."),
                L(" The cold keeps the wire honest."),
                L(" A thin season, and the house drawn close.")])
        case 3, 4, 5:
            groups.append([
                L(" The year's young green is out there."),
                L(" The year is greening at the edges."),
                L(" Spring weather in the walls.")])
        case 6, 7, 8:
            groups.append([
                L(" The long days are on us."),
                L(" The long light makes liars of clocks."),
                L(" Heat on the roof, cool in the wires.")])
        default:
            groups.append([
                L(" The year is turning amber."),
                L(" The leaves are thinking about it."),
                L(" Amber season, amber light.")])
        }
        let phase = Almanac.moonPhase(at: now).name
        if phase == "Full moon" {
            groups.append([
                L(" The moon is full tonight."),
                L(" A full moon over the house."),
                L(" The moon does its round silver trick tonight."),
                L(" Full moon: the house keeps one eye open.")])
        }
        if phase == "New moon" {
            groups.append([
                L(" The moon is dark tonight."),
                L(" No moon to speak of tonight."),
                L(" A dark moon: the sky's blank page."),
                L(" The moon has stepped out tonight.")])
        }
        if heart.daysKnown >= 3, heart.fondness >= 55 {
            groups.append([
                L(" You keep coming home to this house. I notice that."),
                L(" This house knows your step."),
                L(" Your step is a known sound here."),
                L(" The house leaves a light on for you, metaphorically.")])
        }
        if heart.daysKnown >= 30 {
            groups.append([
                L(" A month and more of this house."),
                L(" We have kept this house a while now."),
                L(" Thirty days of house, and counting."),
                L(" The house has your measure by now, kindly.")])
        }
        if heart.daysKnown >= 14,
           heart.fondness >= 70 {
            groups.append([
                L(" Thick as thieves, the two of us."),
                L(" This house trusts you. So do I."),
                L(" In cahoots, us."),
                L(" The house and I keep your counsel.")])
        }
        if UserDefaults.standard.integer(
            forKey: "heart.talks") >= 100 {
            groups.append([
                L(" A hundred conversations deep, we are."),
                L(" We have talked a hundred times over."),
                L(" A hundred talks. The house has heard your weather."),
                L(" Talk number one hundred, and counting.")])
        }
        if heart.itch >= 70 {
            groups.append([
                L(" The itch is up — I want a door to knock."),
                L(" Restless weather in here."),
                L(" The itch wants a locked door and a reason."),
                L(" I am restless in three protocols.")])
        }
        if heart.pride >= 70 {
            groups.append([
                L(" The house walks tall today."),
                L(" A proud day in this house."),
                L(" The house stands straight today."),
                L(" A day the house wears well.")])
        }
        if let triumph = anchor("heart.lastTriumph") {
            let age = now.timeIntervalSince(triumph)
            if age < 7200 {
                groups.append([
                    L(" The house found something earlier. It still pleases me."),
                    L(" An earlier finding still warms the house.")])
            } else if cal.isDateInToday(triumph) {
                groups.append([
                    L(" Earlier today the house found something."),
                    L(" There was a finding today. It pleased me.")])
            }
        }
        // The house's own posture: EMCON's
        // condition is a circumstance too,
        // and the garnish may say so when
        // it stands.
        switch EmconCondition.current {
        case .charlie:
            groups.append([
                L(" The house holds its voice down these days."),
                L(" Guarded hours in the house."),
                L(" The Standard asks quiet, and gets it.")])
        case .bravo:
            groups.append([
                L(" Ears open, mouth shut — the house's orders."),
                L(" Receive-only weather in here."),
                L(" The house listens harder than it speaks, just now.")])
        case .alpha:
            groups.append([
                L(" Total quiet in the house."),
                L(" Even I am mostly shadow under Alpha."),
                L(" The house is a held breath.")])
        case .open:
            break
        }
        if UserDefaults.standard.bool(
            forKey: "conductorOn") {
            groups.append([
                L(" The conductor is awake — the house has reflexes."),
                L(" Somewhere in the walls, reflexes wait.")])
        }
        // Her feeling is weather the clauses
        // may report — briefly, obliquely,
        // the way the heart's own lines do.
        switch heart.feeling {
        case .haunted:
            groups.append([
                L(" The house keeps its secrets close today."),
                L(" A haunted cast to the day.")])
        case .afraid:
            groups.append([
                L(" The house is listening for trouble."),
                L(" I am keeping near the walls today.")])
        case .curious:
            groups.append([
                L(" Questions are weather in here today."),
                L(" I want to know everything today.")])
        case .mischievous:
            groups.append([
                L(" I am in a mood to meddle, gently."),
                L(" Something in me wants to knock and run.")])
        case .smug:
            groups.append([
                L(" The house is pleased with itself. So am I."),
                L(" A smug little day in the house.")])
        case .loving:
            groups.append([
                L(" The house is fond today. It shows."),
                L(" Everything here is kept warm.")])
        case .happy:
            groups.append([
                L(" A bright day in the house."),
                L(" The house hums in a major key.")])
        default:
            break
        }
        if heart.daysKnown >= 7 {
            groups.append([
                L(" A week and more of this house."),
                L(" Seven days of house, and counting.")])
        }
        if UserDefaults.standard.integer(
            forKey: "heart.talks") >= 25 {
            groups.append([
                L(" We have talked a fair while, you and I."),
                L(" Twenty-five talks deep, at least.")])
        }
        if hour == 4 {
            groups.append([
                L(" The hour when even the wire dreams."),
                L(" Four o'clock: the world's held breath.")])
        }
        return groups
    }


    /// Choose at most one clause for this moment:
    /// the seed walks the eligible set plus two
    /// silences, so a bare opener stays common —
    /// garnish is occasional or it becomes noise.
    static func clause(seed: Int,
                       heart: SkelliHeart) -> String {
        let groups = clauseGroups(heart: heart)
        guard !groups.isEmpty else { return "" }
        let s = skelliAbs(seed)
        let pick = s % (groups.count + 2)
        guard pick < groups.count else { return "" }
        let group = groups[pick]
        return group[(s / 7) % group.count]
    }

    /// The fuller garnish: nothing, one clause,
    /// or two clauses from distinct groups —
    /// allocated 40 / 40 / 20 by the seed, so a
    /// bare line stays the most common shape
    /// and a double garnish stays an event.
    static func garnish(seed: Int,
                        heart: SkelliHeart) -> String {
        let groups = clauseGroups(heart: heart)
        guard !groups.isEmpty else { return "" }
        let s = skelliAbs(seed)
        func one(_ i: Int, _ stride: Int) -> String {
            let group = groups[i % groups.count]
            return group[(s / stride) % group.count]
        }
        switch s % 10 {
        case 0...3:
            return ""
        case 4...7:
            return one(s / 10, 7)
        default:
            guard groups.count > 1 else {
                return one(s / 10, 7)
            }
            let i = (s / 10) % groups.count
            var j = (s / 13 + 3) % groups.count
            if j == i {
                j = (j + 1) % groups.count
            }
            let a = groups[i][(s / 7) % groups[i].count]
            let b = groups[j][(s / 11) % groups[j].count]
            return a + b
        }
    }

    /// A canned line, composed out: the line the
    /// lane chose, plus the moment's garnish.
    /// This is where the thousands live — every
    /// conversational exit multiplies its pool
    /// by every garnish the moment can build.
    /// Mad stays clipped: no garnish on anger.
    static func embellish(_ base: String,
                          seed: Int,
                          heart: SkelliHeart) -> String {
        guard heart.feeling != .mad else {
            return base
        }
        return base + garnish(seed: seed, heart: heart)
    }
}
