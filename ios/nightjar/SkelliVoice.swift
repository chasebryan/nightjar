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
                       unnamed)])
        }
        if neighbors.isEmpty {
            groups.append([
                L(" The wire stands empty."),
                L(" Not a soul on the wire but us.")])
        } else if neighbors.count <= 6 {
            groups.append([
                L(" A small congregation on the wire.")])
        } else {
            groups.append([
                L(" The wire is crowded."),
                L(" Plenty of company on the wire.")])
        }
        if !neighbors.isEmpty && unnamed == 0 {
            groups.append([
                L(" Every soul on this wire has a name."),
                L(" The whole wire is named and known.")])
        }
        if let spoke = anchor("heart.lastSpoke") {
            let quiet = now.timeIntervalSince(spoke)
            if quiet >= 3 * 3600 {
                groups.append([
                    L(" It's been quiet for hours."),
                    L(" Hours of quiet, counted.")])
            } else if quiet >= 3600 {
                groups.append([
                    L(" It's been quiet a while.")])
            } else if quiet >= 1200 {
                let minutes = Int(quiet / 60)
                groups.append([
                    String(format: L(" %lld minutes of quiet, counted exactly."),
                           minutes),
                    String(format: L(" The quiet is %lld minutes deep."),
                           minutes)])
            }
        }
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        if hour == 3 {
            groups.append([
                L(" The walls are thin at this hour."),
                L(" Thin walls, this hour.")])
        }
        if (5..<7).contains(hour) {
            groups.append([
                L(" The wire is only just waking.")])
        }
        if (7..<11).contains(hour) {
            groups.append([
                L(" The day is young."),
                L(" Morning, and the light is plain.")])
        }
        if (11..<14).contains(hour) {
            groups.append([
                L(" The day stands at its height.")])
        }
        if (14..<18).contains(hour) {
            groups.append([
                L(" The afternoon is wearing on.")])
        }
        if (18..<22).contains(hour) {
            groups.append([
                L(" The evening is on us."),
                L(" Dusk-side of the day.")])
        }
        if hour >= 22 {
            groups.append([
                L(" The house is settling for the night."),
                L(" The house is folding itself down.")])
        }
        if hour < 3 {
            groups.append([
                L(" The small hours."),
                L(" Deep in the night's pocket.")])
        }
        let weekday = cal.component(
            .weekday, from: now)
        if weekday == 6 {
            groups.append([
                L(" The week's end is in sight."),
                L(" Friday: the week nearly spent.")])
        }
        if weekday == 2 {
            groups.append([
                L(" The week starts cold.")])
        }
        if weekday == 1 || weekday == 7 {
            groups.append([
                L(" The week's off-duty hours."),
                L(" A weekend quiet in the house.")])
        }
        switch cal.component(.month, from: now) {
        case 12, 1, 2:
            groups.append([
                L(" Winter's hand is on the house.")])
        case 3, 4, 5:
            groups.append([
                L(" The year's young green is out there.")])
        case 6, 7, 8:
            groups.append([
                L(" The long days are on us.")])
        default:
            groups.append([
                L(" The year is turning amber.")])
        }
        let phase = Almanac.moonPhase(at: now).name
        if phase == "Full moon" {
            groups.append([
                L(" The moon is full tonight."),
                L(" A full moon over the house.")])
        }
        if phase == "New moon" {
            groups.append([
                L(" The moon is dark tonight."),
                L(" No moon to speak of tonight.")])
        }
        if heart.daysKnown >= 3, heart.fondness >= 55 {
            groups.append([
                L(" You keep coming home to this house. I notice that."),
                L(" This house knows your step.")])
        }
        if heart.daysKnown >= 30 {
            groups.append([
                L(" A month and more of this house."),
                L(" We have kept this house a while now.")])
        }
        if heart.daysKnown >= 14,
           heart.fondness >= 70 {
            groups.append([
                L(" Thick as thieves, the two of us."),
                L(" This house trusts you. So do I.")])
        }
        if UserDefaults.standard.integer(
            forKey: "heart.talks") >= 100 {
            groups.append([
                L(" A hundred conversations deep, we are."),
                L(" We have talked a hundred times over.")])
        }
        if heart.itch >= 70 {
            groups.append([
                L(" The itch is up — I want a door to knock."),
                L(" Restless weather in here.")])
        }
        if heart.pride >= 70 {
            groups.append([
                L(" The house walks tall today."),
                L(" A proud day in this house.")])
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
        return groups
    }

    /// The first phrasing of each true group —
    /// the library's plain face, kept for the
    /// callers that only ever wanted the list.
    static func eligibleClauses(
        heart: SkelliHeart) -> [String] {
        clauseGroups(heart: heart).map { $0[0] }
    }

    /// Choose at most one clause for this moment:
    /// the seed walks the eligible set plus two
    /// silences, so a bare opener stays common —
    /// garnish is occasional or it becomes noise.
    static func clause(seed: Int,
                       heart: SkelliHeart) -> String {
        let groups = clauseGroups(heart: heart)
        guard !groups.isEmpty else { return "" }
        let s = abs(seed)
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
        let s = abs(seed)
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
