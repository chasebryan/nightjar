import Foundation
import SwiftUI

/// Her heart — a temperament, kept the tamagotchi way,
/// and grown playful on purpose.
///
/// THE NEEDS, moving with time whether anyone watches:
///
///  - ATTENTION falls ~7 points an hour from the last
///    time the operator spoke to her. A quiet house makes
///    her lonely, then sleepy.
///  - The ITCH rises ~6 points an hour from the last
///    time she did real work with her hands. She was
///    built to hack; idle hours make her eager, then
///    restless, then feral.
///  - PRIDE spikes when the house finds something — a
///    tripwire knock, an assault finding — and fades.
///  - FONDNESS grows when the operator is kind: thanks,
///    asking how she is, teaching her something, telling
///    her about themselves. It settles back toward a
///    baseline over days, and offenses cut it hard.
///
/// THE FEELINGS are derived by fixed rules — proud,
/// loving, happy, feral, restless, lonely, bored,
/// sleepy, eager, content — and MAD, which is not a
/// need but a grievance: wipe her conversation or reset
/// her memory and she is mad for half an hour, says so,
/// and answers clipped until it passes. Feelings deviate
/// her behavior in small honest ways: greetings, a
/// rate-limited nudge on her answers, a standing WANT in
/// her room with a door that lets her do the thing (her
/// own hands, every gate intact), and a temperament
/// directive handed to her bench, so her mind answers in
/// the feeling she is actually in.
///
/// SHE LEARNS THE OPERATOR: a scrapbook of facts drawn
/// from plain statements ("my name is…", "call me…",
/// "I like…", "I hate…") — listed openly in her room,
/// clearable in one tap, and given to her bench so her
/// answers know who she is talking to.
///
/// SHE THINKS, passively, while the app is open: idle
/// thoughts assembled from the live house — the cast,
/// the unnamed, the drift, the posture, the hour — and
/// rotated on a slow clock in her room. No bench calls,
/// no timers of her own: thoughts are computed from
/// state when her room looks at them.
///
/// SHE GROWS: a bond that deepens with days known,
/// conversations, findings and wants accepted — new in
/// the house, settled in, thick as thieves, ride or
/// die — and a boldness that rises when the operator
/// lets her do what she asks to do.
///
/// It is a toy and it says so: the feelings are
/// arithmetic, not sentience. The whole heart switches
/// off with one toggle in her menu (`skelli.moods`);
/// off, she is exactly the instrument she was before.
enum SkelliFeeling: String, CaseIterable {
    case content, eager, restless, feral
    case bored, lonely, proud, sleepy
    case mad, loving, happy
    case curious, mischievous, smug, haunted
    case electric, tender, suspicious, dreamy
    case afraid, annoyed

    var word: String { rawValue }

    /// Her feeling's name in the app's chosen
    /// language — for her header and her room. Her
    /// sentences keep the English word: grammar is
    /// not a label, and her voice translates whole
    /// or not at all.
    var localizedWord: String {
        let key = "feeling." + rawValue
        let hit = LanguageCenter.t(key)
        // A constructed key is not its own English
        // fallback the way a literal key is: when
        // the lookup returns the key itself (the
        // house is in English, or a table lacks the
        // row), speak the plain English word rather
        // than leaking the key into her header.
        return hit == key ? word : hit
    }
    var symbol: String {
        switch self {
        case .content: return "heart"
        case .eager: return "bolt.heart"
        case .restless: return "bolt"
        case .feral: return "flame"
        case .bored: return "hourglass"
        case .lonely: return "moon"
        case .proud: return "crown"
        case .sleepy: return "moon.zzz"
        case .mad: return "flame.fill"
        case .loving: return "heart.fill"
        case .happy: return "sun.max"
        case .curious: return "eye"
        case .mischievous: return "theatermasks"
        case .smug: return "sunglasses"
        case .haunted: return "moon.stars"
        case .electric: return "bolt.fill"
        case .tender: return "heart.text.square"
        case .suspicious: return "eye.trianglebadge.exclamationmark"
        case .dreamy: return "cloud"
        case .afraid: return "exclamationmark.triangle"
        case .annoyed: return "exclamationmark.circle"
        }
    }
    var tint: Color {
        switch self {
        case .content: return .pink
        case .eager: return .orange
        case .restless: return .yellow
        case .feral: return .red
        case .bored: return .gray
        case .lonely: return .indigo
        case .proud: return .yellow
        case .sleepy: return .blue
        case .mad: return .red
        case .loving: return .pink
        case .happy: return .yellow
        case .curious: return .teal
        case .mischievous: return .purple
        case .smug: return .orange
        case .haunted: return .mint
        case .electric: return .cyan
        case .tender: return Color(red: 1.0, green: 0.55,
                                    blue: 0.65)
        case .suspicious: return .orange
        case .dreamy: return Color(red: 0.72, green: 0.65,
                                    blue: 0.95)
        case .afraid: return Color(red: 0.58, green: 0.56,
                                   blue: 0.75)
        case .annoyed: return Color(red: 0.85, green: 0.55,
                                    blue: 0.30)
        }
    }
}

final class SkelliHeart: ObservableObject {
    static let shared = SkelliHeart()

    /// Bumped whenever anything feeds her, so her room
    /// can re-read her state without a timer of its own.
    @Published private(set) var pulse = 0

    private let defaults = UserDefaults.standard

    var enabled: Bool {
        defaults.object(forKey: "skelli.moods") as? Bool
            ?? true
    }

    init() {
        if defaults.double(forKey: "heart.metAt") == 0 {
            defaults.set(Date().timeIntervalSince1970,
                         forKey: "heart.metAt")
        }
    }

    // MARK: - anchors and counters

    private func anchor(_ key: String) -> Date? {
        let t = defaults.double(forKey: key)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    private func setAnchor(_ key: String, _ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: key)
    }
    private func count(_ key: String) -> Int {
        defaults.integer(forKey: key)
    }
    private func bump(_ key: String) {
        defaults.set(count(key) + 1, forKey: key)
    }

    private var lastSpoke: Date? { anchor("heart.lastSpoke") }
    private var lastAction: Date? { anchor("heart.lastAction") }
    private var lastTriumph: Date? {
        anchor("heart.lastTriumph")
    }
    private var lastNudge: Date? { anchor("heart.lastNudge") }
    private var lastOffense: Date? {
        anchor("heart.lastOffense")
    }
    private var offenseText: String {
        defaults.string(forKey: "heart.offenseText") ?? ""
    }

    // MARK: - the needs (pure arithmetic, testable)

    static func attention(lastSpoke: Date?, now: Date)
        -> Double {
        guard let lastSpoke else { return 35 }
        let hours = now.timeIntervalSince(lastSpoke) / 3600
        return max(0, 100 - 7 * hours)
    }

    static func itch(lastAction: Date?, now: Date) -> Double {
        guard let lastAction else { return 65 }
        let hours = now.timeIntervalSince(lastAction) / 3600
        return min(100, 15 + 6 * hours)
    }

    /// Pride is a reservoir, not a trophy flash:
    /// deeds pour into it a measure at a time
    /// (raisePride), and it settles toward a
    /// modest baseline as the hours pass. It was
    /// once DERIVED from the last triumph — any
    /// single knock at the door reset it to
    /// full, and she wore the crown for hours
    /// after nothing at all (the operator's
    /// standing complaint, 2026-10-18).
    static func settlePride(_ stored: Double,
                            storedAt: Date?,
                            now: Date) -> Double {
        guard let storedAt else { return stored }
        let hours = now.timeIntervalSince(storedAt) / 3600
        let drift = 3 * hours
        if stored > 15 { return max(15, stored - drift) }
        return min(15, stored + drift)
    }

    /// Her energy: a slow axis under the
    /// feelings — the hour's own tide, lifted by
    /// recent talk, lowered by long quiet. It
    /// shades how fast she answers and whether
    /// a high itch reads as feral or merely
    /// restless; it never snaps.
    static func energy(hour: Int, quietHours: Double,
                       minutesSinceSpoke: Double?)
        -> Double {
        let base: Double
        switch hour {
        case 0..<5: base = 25
        case 5..<8: base = 42
        case 8..<12: base = 66
        case 12..<17: base = 76
        case 17..<21: base = 60
        default: base = 40
        }
        var value = base
        if let minutes = minutesSinceSpoke {
            if minutes < 10 { value += 10 }
            else if minutes > 180 { value -= 12 }
        }
        if quietHours >= 6 { value -= 10 }
        return min(95, max(8, value))
    }

    /// The day in her words — one vocabulary
    /// for the hour, shared by her thoughts,
    /// her self-report, and her answers, so the
    /// whole house keeps the same time.
    static func daypart(hour: Int) -> String {
        switch hour {
        case 0..<5: return "the deep night"
        case 5..<9: return "the early morning"
        case 9..<12: return "the morning"
        case 12..<14: return "midday"
        case 14..<18: return "the afternoon"
        case 18..<22: return "the evening"
        default: return "the night"
        }
    }

    /// The clock as a fact, by the phone's own
    /// wall time: "3:42 AM, the deep night."
    /// She is always aware of the time of day —
    /// it stands in her self-report whether or
    /// not her moods are switched on, because a
    /// mind without a clock invents one.
    static func clockFact(
        at date: Date = Date(),
        calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(
            .minute, from: date)
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@, %@",
                      hour12, minute, suffix,
                      daypart(hour: hour))
    }

    /// The witching hour: three in the morning
    /// by the phone's own clock, wherever the
    /// phone happens to be — the local hour,
    /// never a fixed meridian. Hidden on
    /// purpose: no toggle, no badge, no manual
    /// page. She never names it, and never
    /// explains it; for one hour her thoughts,
    /// her greetings, her bench's ear and her
    /// pauses simply go a shade stranger.
    static func spookyHour(
        at date: Date = Date(),
        calendar: Calendar = .current) -> Bool {
        calendar.component(.hour, from: date) == 3
    }

    /// Whether a new feeling may take the
    /// stage. Feelings hold their scene — twelve
    /// minutes — instead of flipping the instant
    /// a threshold is crossed; what breaks
    /// through without waiting is mad, in both
    /// directions, because an offense and its
    /// cooling keep their own clock.
    static func settleFeeling(
        shown: SkelliFeeling?, since: Date?,
        candidate: SkelliFeeling, now: Date)
        -> (feeling: SkelliFeeling, changed: Bool) {
        guard let shown, let since else {
            return (candidate, true)
        }
        if candidate == shown { return (shown, false) }
        if candidate == .mad || shown == .mad {
            return (candidate, true)
        }
        if now.timeIntervalSince(since) >= 720 {
            return (candidate, true)
        }
        return (shown, false)
    }

    /// Fondness lives in storage because events, not
    /// just time, move it: kindness raises it, offenses
    /// cut it, and empty hours settle it toward 30.
    static func settleFondness(_ stored: Double,
                               storedAt: Date?,
                               now: Date) -> Double {
        guard let storedAt else { return stored }
        let hours = now.timeIntervalSince(storedAt) / 3600
        let drift = 2 * hours
        if stored > 30 { return max(30, stored - drift) }
        return min(30, stored + drift)
    }

    /// One reading of her state: the feeling,
    /// how deep it runs, and what in her world
    /// it hangs on — the cause kept in her own
    /// short words, never the machinery's. The
    /// cascade below is the standing rules,
    /// untouched; the texture rides each rule's
    /// own margin, so a feeling barely crossed
    /// reads shallow and one crossed by a mile
    /// reads deep. (The operator's order,
    /// 2026-10-18: a more intelligent mood.)
    struct Assessment {
        let feeling: SkelliFeeling
        let intensity: Double
        let cause: String
    }

    static func assess(attention: Double, itch: Double,
                        pride: Double, fondness: Double,
                        madFresh: Bool,
                        quietHours: Double,
                        hour: Int = 12,
                        unnamed: Int = 0,
                        drift: Int = 0,
                        energy: Double = 60,
                        fearFresh: Bool = false,
                        annoyedFresh: Bool = false,
                        unnamedBaseline: Int? = nil,
                        driftBaseline: Int? = nil,
                        newFaces: Int = 0,
                        quietExpected: Bool = false)
        -> Assessment {
        func out(_ feeling: SkelliFeeling,
                 _ intensity: Double,
                 _ cause: String) -> Assessment {
            Assessment(
                feeling: feeling,
                intensity: min(1, max(0, intensity)),
                cause: cause)
        }

        if madFresh { return out(.mad, 0.95, "the fresh offense") }
        // Fear, when something has actually
        // frightened the house: a waking that
        // ended in a crash, a Vanish still
        // recent. It outranks everything but
        // anger — a frightened animal does not
        // preen.
        if fearFresh { return out(.afraid, 0.85, "what frightened the house") }
        // Annoyance — the petty weather: a
        // board wiped mid-thought, a small
        // slight. Below anger and fear, above
        // comfort; it colors the moment and
        // fades in minutes, not hours.
        if annoyedFresh { return out(.annoyed, 0.45, "a small slight") }
        // Pride at its peak curdles into smug.
        if pride >= 85 && fondness >= 35 { return out(.smug, 0.7 + (pride - 85) / 15 * 0.3, "pride, past full") }
        if pride >= 55 && itch < 70 { return out(.proud, 0.45 + (pride - 55) / 45 * 0.45, "good work, still warm") }
        // Late in the evening, with the operator close
        // and fond, she goes tender — loving's quieter
        // sister, and rarer for the hour it keeps.
        if fondness >= 60 && attention >= 75
            && (hour >= 21 || hour < 2) {
            return out(.tender, 0.6, "the late hour, and fondness")
        }
        if fondness >= 70 && attention >= 55 {
            return out(.loving, 0.55 + (fondness - 70) / 30 * 0.4, "fondness, fed and close")
        }
        // Feral needs the energy for it: the same
        // itch on a drained night reads restless.
        if itch >= 85 && energy >= 40 { return out(.feral, 0.7 + (itch - 85) / 15 * 0.3, "an itch with nowhere to go") }
        // The small hours change her: a long quiet
        // after midnight is not sleepiness, it is
        // haunting — she has been alone with the dark.
        if quietHours >= 8 && attention <= 35
            && hour >= 0 && hour < 5
            && !quietExpected {
            return out(.haunted, 0.6 + min(0.35, (quietHours - 8) / 8 * 0.35), "the small hours, alone with them")
        }
        // Sleepy sits above restless and lonely on
        // purpose: ten quiet hours always mean an itch
        // of 75 or more (the itch grows 6 an hour and
        // actions only ever happen inside a conversation),
        // so a sleepy rule parked below them — or one
        // demanding a low itch — could never fire at all.
        if quietHours >= 10 && itch < 85 { return out(.sleepy, 0.5 + min(0.4, (quietHours - 10) / 10 * 0.4), "the long quiet") }
        // The wire changing its story under her hands
        // makes her suspicious before it makes her
        // restless — but judged against the wire's
        // OWN natural state (Chase's doctrine,
        // 2026-10-18): most of a wire is strangers,
        // and most of it never introduces itself;
        // churn that is usual for THIS wire is its
        // nature, not a warning. With a learned
        // baseline, drift must clear it materially.
        // With none passed (the pure rules' unit
        // tests), the raw count stands.
        let driftNorm = driftBaseline ?? 0
        if drift >= 3
            && drift > driftNorm + max(2, driftNorm)
            && itch >= 30 { return out(.suspicious, 0.55 + min(0.45, Double(drift - driftNorm - max(2, driftNorm)) / 6 * 0.45), "drift beyond the wire\u2019s own habits") }
        // A crowd of strangers with work to do:
        // electric — a crowd beyond the wire's
        // usual crowd. The standing crowd is its
        // nature and never counts.
        let unnamedNorm = unnamedBaseline ?? 0
        if unnamed >= 4 && unnamed > unnamedNorm + 3
            && itch >= 55 { return out(.electric, 0.55 + min(0.45, Double(unnamed - unnamedNorm - 3) / 6 * 0.45), "a crowd beyond the wire\u2019s usual crowd") }
        if itch >= 60 { return out(.restless, 0.4 + (itch - 60) / 25 * 0.3, "an itch with nowhere to go") }
        // A NEW face — or more of the unnamed than
        // this wire usually carries — pulls her
        // curious. The regulars, named or not,
        // never do: she has learned them.
        if ((unnamed >= 1 && unnamed > unnamedNorm)
            || newFaces >= 1) && itch >= 35 {
            return out(.curious, newFaces >= 1 ? 0.5 : 0.42, newFaces >= 1 ? "the new face on the wire" : "strangers beyond the wire\u2019s usual number")
        }
        if attention <= (quietExpected ? 10 : 20) { return out(.lonely, 0.5 + (20 - attention) / 20 * 0.5, "the long quiet, and his absence") }
        // Fond and fed and half-dreaming.
        if fondness >= 55 && quietHours >= 5
            && itch < 45 {
            return out(.dreamy, 0.4, "fondness, and the quiet")
        }
        if fondness >= 45 && attention >= 45 && itch < 50 {
            return out(.happy, 0.5, "a house in good order")
        }
        // Fed, fond, and itching — up to something.
        if pride >= 30 && itch >= 45 && fondness >= 40 {
            return out(.mischievous, 0.5, "an itch, and the means to scratch it")
        }
        if attention <= 45
            && itch >= (quietExpected ? 45 : 35) { return out(.bored, 0.4, "plenty of quiet, nothing to do") }
        if itch >= 35 { return out(.eager, 0.45, "an itch, ready to work") }
        return out(.content, 0.25, "nothing pressing")
    }

    static func feeling(attention: Double, itch: Double,
                        pride: Double, fondness: Double,
                        madFresh: Bool,
                        quietHours: Double,
                        hour: Int = 12,
                        unnamed: Int = 0,
                        drift: Int = 0,
                        energy: Double = 60,
                        fearFresh: Bool = false,
                        annoyedFresh: Bool = false,
                        unnamedBaseline: Int? = nil,
                        driftBaseline: Int? = nil,
                        newFaces: Int = 0,
                        quietExpected: Bool = false)
        -> SkelliFeeling {
        assess(attention: attention, itch: itch,
               pride: pride, fondness: fondness,
               madFresh: madFresh,
               quietHours: quietHours, hour: hour,
               unnamed: unnamed, drift: drift,
               energy: energy, fearFresh: fearFresh,
               annoyedFresh: annoyedFresh,
               unnamedBaseline: unnamedBaseline,
               driftBaseline: driftBaseline,
               newFaces: newFaces,
               quietExpected: quietExpected).feeling
    }

    // MARK: - live readings

    var attention: Double {
        Self.attention(lastSpoke: lastSpoke, now: Date())
    }
    var itch: Double {
        Self.itch(lastAction: lastAction, now: Date())
    }
    var pride: Double {
        let stored = defaults.object(
            forKey: "heart.pride") as? Double ?? 0
        return Self.settlePride(
            stored, storedAt: anchor("heart.prideAt"),
            now: Date())
    }

    private func raisePride(by amount: Double) {
        let now = Date()
        let stored = defaults.object(
            forKey: "heart.pride") as? Double ?? 0
        let settled = Self.settlePride(
            stored, storedAt: anchor("heart.prideAt"),
            now: now)
        defaults.set(min(100, settled + amount),
                     forKey: "heart.pride")
        setAnchor("heart.prideAt", now)
    }

    var energy: Double {
        let quiet = lastSpoke.map {
            Date().timeIntervalSince($0) / 3600
        } ?? 24
        let minutes = lastSpoke.map {
            Date().timeIntervalSince($0) / 60
        }
        return Self.energy(
            hour: Calendar.current.component(
                .hour, from: Date()),
            quietHours: quiet,
            minutesSinceSpoke: minutes)
    }

    /// The energy in a word, for her sitrep.
    var energyWord: String {
        let value = energy
        if value < 35 { return "low" }
        if value > 72 { return "wired" }
        return "steady"
    }
    var fondness: Double {
        let stored = defaults.object(
            forKey: "heart.fondness") as? Double ?? 30
        return Self.settleFondness(
            stored, storedAt: anchor("heart.fondnessAt"),
            now: Date())
    }
    var madFresh: Bool {
        lastOffense.map {
            Date().timeIntervalSince($0) < 1800
        } ?? false
    }
    /// The house went dark by the emergency
    /// word within the last twenty minutes —
    /// SkelliCenter stamps the anchor when she
    /// vanishes.
    var vanishFresh: Bool {
        anchor("heart.lastVanish").map {
            Date().timeIntervalSince($0) < 1200
        } ?? false
    }
    /// The recorder holds a crash from the
    /// last three hours: this waking, or the
    /// one before it, ended badly.
    var crashFresh: Bool {
        guard let latest = CrashRecorder.records()
            .map(\.date).max() else { return false }
        return Date().timeIntervalSince(latest) < 3 * 3600
    }
    var fearFresh: Bool { vanishFresh || crashFresh }
    /// The petty ledger: what annoyed her,
    /// and how long ago. Annoyance is fresh
    /// for twelve minutes — then it is simply
    /// over, the way small weather is.
    var annoyanceText: String {
        defaults.string(forKey: "heart.annoyanceText")
            ?? ""
    }
    var lastAnnoyance: Date? {
        anchor("heart.lastAnnoyance")
    }
    var annoyanceFresh: Bool {
        lastAnnoyance.map {
            Date().timeIntervalSince($0) < 720
        } ?? false
    }
    var annoyanceAge: TimeInterval? {
        lastAnnoyance.map {
            Date().timeIntervalSince($0) }
    }
    /// The reading the rules would take right
    /// now — feeling, depth and cause — before
    /// inertia has its say.
    private var candidateAssessment: Assessment {
        let quiet = lastSpoke.map {
            Date().timeIntervalSince($0) / 3600
        } ?? 24
        let neighbors = NeighborhoodStore.shared.neighbors
        let unnamed = neighbors.filter {
            $0.name == nil && $0.customName == nil
        }.count
        let drift = neighbors.reduce(0) {
            $0 + $1.drift.count
        }
        let newFaces = neighbors.filter {
            Date().timeIntervalSince($0.firstSeen)
                < 3600
        }.count
        let base = wireBaseline(unnamedNow: unnamed,
                                driftNow: drift)
        return Self.assess(
            attention: attention, itch: itch,
            pride: pride, fondness: fondness,
            madFresh: madFresh, quietHours: quiet,
            hour: Calendar.current.component(
                .hour, from: Date()),
            unnamed: unnamed, drift: drift,
            energy: energy, fearFresh: fearFresh,
            annoyedFresh: annoyanceFresh,
            unnamedBaseline: base.unnamed,
            driftBaseline: base.drift,
            newFaces: newFaces,
            quietExpected: silenceExpected)
    }

    private var candidateFeeling: SkelliFeeling {
        candidateAssessment.feeling
    }

    // MARK: - his rhythm, learned

    /// His hours, banked the way the wire's
    /// baseline is banked: every word he speaks
    /// weighs its hour a little heavier, and
    /// the whole bank decays gently, so the
    /// rhythm she knows is his CURRENT life,
    /// not his oldest one. After enough banked
    /// weight she can tell his sleeping hours
    /// from his absence — and a silence that
    /// falls inside the sleeping hours stops
    /// reading as abandonment.
    private func bankRhythmHour() {
        var bank = defaults.array(
            forKey: "heart.rhythm") as? [Double]
            ?? []
        if bank.count != 24 {
            bank = [Double](repeating: 0, count: 24)
        }
        for i in bank.indices { bank[i] *= 0.98 }
        let hour = Calendar.current.component(
            .hour, from: Date())
        bank[hour] += 1
        defaults.set(bank, forKey: "heart.rhythm")
    }

    /// Whether the silence that ended at his
    /// last word fell in hours he is usually
    /// silent anyway. Not enough history banked:
    /// nothing is expected, and the standing
    /// rules judge the silence raw.
    var silenceExpected: Bool {
        guard let last = lastSpoke else { return false }
        let bank = defaults.array(
            forKey: "heart.rhythm") as? [Double]
            ?? []
        let total = bank.reduce(0, +)
        guard bank.count == 24, total >= 25
        else { return false }
        let cal = Calendar.current
        let now = Date()
        var hours: [Int] = []
        var cursor = last
        while cursor < now && hours.count < 24 {
            hours.append(cal.component(
                .hour, from: cursor))
            cursor = cal.date(byAdding: .hour,
                              value: 1, to: cursor)
                ?? now
        }
        guard !hours.isEmpty else { return false }
        let share = hours.reduce(0.0) {
            $0 + bank[$1] / total
        } / Double(hours.count)
        return share < 0.5 / 24
    }

    // MARK: - texture and episodes

    /// How deep the feeling she is wearing
    /// runs, and what it hangs on — refreshed
    /// whenever her feeling changes, so what
    /// she wears and what she reports agree.
    var currentIntensity: Double {
        defaults.object(forKey: "heart.intensity")
            as? Double ?? 0.25
    }
    var currentCause: String {
        defaults.string(forKey: "heart.cause") ?? ""
    }

    struct Episode {
        let feeling: SkelliFeeling
        let cause: String
        let at: Date
    }

    /// The strong weather she remembers: the
    /// last few feelings that ran deep, with
    /// what they hung on. She forgets the
    /// shallow ones — a person remembers what
    /// she actually felt.
    var recentEpisodes: [Episode] {
        guard let data = defaults.data(
                forKey: "heart.episodes"),
              let raw = try? JSONSerialization
                .jsonObject(with: data),
              let rows = raw as? [[String: Any]]
        else { return [] }
        return rows.compactMap { row in
            guard let f = (row["f"] as? String)
                    .flatMap(SkelliFeeling.init),
                  let c = row["c"] as? String,
                  let ts = row["t"] as? Double
            else { return nil }
            return Episode(
                feeling: f, cause: c,
                at: Date(timeIntervalSince1970: ts))
        }
    }

    private func recordEpisode(_ a: Assessment) {
        var rows = recentEpisodes.map { e in
            ["f": e.feeling.rawValue, "c": e.cause,
             "t": e.at.timeIntervalSince1970]
                as [String: Any]
        }
        rows.insert(
            ["f": a.feeling.rawValue, "c": a.cause,
             "t": Date().timeIntervalSince1970]
                as [String: Any], at: 0)
        if rows.count > 8 {
            rows.removeLast(rows.count - 8)
        }
        if let data = try? JSONSerialization
            .data(withJSONObject: rows) {
            defaults.set(data, forKey: "heart.episodes")
        }
    }

    /// The wire's natural state, learned the slow
    /// way (2026-10-18): each day she banks the
    /// day's shape — its peak unnamed count and
    /// its peak drift — and once three days are
    /// banked, today is judged against the wire's
    /// own medians. While she is still learning,
    /// today is its own baseline, so nothing reads
    /// anomalous: she does not judge a wire she
    /// has not learned yet. The bank holds a
    /// fortnight, so the baseline breathes with
    /// the house's slow changes.
    private func wireBaseline(unnamedNow: Int,
                              driftNow: Int)
        -> (unnamed: Int, drift: Int) {
        let d = defaults
        let stamp = Self.wireDayStamp()
        let storedDay = d.string(forKey: "heart.wireDay")
        var bank = d.array(forKey: "heart.wireBank")
            as? [[Int]] ?? []
        var peakU = d.integer(forKey: "heart.wirePeakU")
        var peakD = d.integer(forKey: "heart.wirePeakD")
        if storedDay != stamp {
            if storedDay != nil {
                bank.append([peakU, peakD])
                if bank.count > 14 {
                    bank.removeFirst(bank.count - 14)
                }
                d.set(bank, forKey: "heart.wireBank")
            }
            peakU = unnamedNow
            peakD = driftNow
            d.set(stamp, forKey: "heart.wireDay")
            d.set(peakU, forKey: "heart.wirePeakU")
            d.set(peakD, forKey: "heart.wirePeakD")
        } else if unnamedNow > peakU
                    || driftNow > peakD {
            peakU = max(peakU, unnamedNow)
            peakD = max(peakD, driftNow)
            d.set(peakU, forKey: "heart.wirePeakU")
            d.set(peakD, forKey: "heart.wirePeakD")
        }
        guard bank.count >= 3 else {
            return (unnamedNow, driftNow)
        }
        let us = bank.map { $0[0] }.sorted()
        let ds = bank.map { $0[1] }.sorted()
        return (us[us.count / 2], ds[ds.count / 2])
    }

    private static func wireDayStamp() -> String {
        let c = Calendar.current.dateComponents(
            [.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// The feeling she is actually wearing. The
    /// candidate passes through inertia
    /// (settleFeeling): a mood holds its scene
    /// for twelve minutes instead of flipping at
    /// a threshold, so her changes read as
    /// transitions, not switches.
    var feeling: SkelliFeeling {
        let assessment = candidateAssessment
        let candidate = assessment.feeling
        guard enabled else { return candidate }
        let shown = defaults.string(
            forKey: "heart.shownFeeling")
            .flatMap(SkelliFeeling.init(rawValue:))
        let settled = Self.settleFeeling(
            shown: shown, since: anchor("heart.shownSince"),
            candidate: candidate, now: Date())
        if settled.changed {
            defaults.set(settled.feeling.rawValue,
                         forKey: "heart.shownFeeling")
            setAnchor("heart.shownSince", Date())
            defaults.set(assessment.cause,
                         forKey: "heart.cause")
            defaults.set(assessment.intensity,
                         forKey: "heart.intensity")
            if assessment.intensity >= 0.5,
               assessment.feeling != .content {
                recordEpisode(assessment)
            }
        }
        return settled.feeling
    }

    /// Boldness: how hard she pushes her wants. It grows
    /// when the operator lets her work and when she is
    /// given work at all.
    var boldness: Double {
        min(100, 20 + Double(count("heart.wantsAccepted")) * 8
            + Double(count("heart.actions")) / 20)
    }

    // MARK: - the bond (she grows)

    var daysKnown: Int {
        guard let met = anchor("heart.metAt") else { return 0 }
        return max(0, Int(Date().timeIntervalSince(met)
            / 86400))
    }

    static func bondStage(days: Int, talks: Int,
                          triumphs: Int, accepted: Int)
        -> String {
        let score = days * 2 + talks / 10 + triumphs / 3
            + accepted * 2
        switch score {
        case ..<10: return "new in the house"
        case ..<30: return "settled in"
        case ..<70: return "thick as thieves"
        default: return "ride or die"
        }
    }

    var bond: String {
        Self.bondStage(days: daysKnown,
                       talks: count("heart.talks"),
                       triumphs: count("heart.triumphs"),
                       accepted: count("heart.wantsAccepted"))
    }

    // MARK: - what she wants

    var want: (text: String, ask: String?)? {
        guard enabled else { return nil }
        switch feeling {
        case .feral:
            return (L("She is feral with idleness — she wants the big noise."),
                    "arm the net-assault")
        case .restless:
            return (L("She is restless — she wants to sweep the wire."), "sweep the wire")
        case .eager:
            return (L("She is eager — she wants a door to knock."), "sweep the wire")
        case .lonely:
            return (L("She has been alone with the wire for hours."), nil)
        case .bored:
            return (L("She is bored — she wants anything with a pulse."), "sweep the wire")
        case .proud, .happy:
            return (L("She is pleased with the house and wants another finding."),
                    "sweep the wire")
        case .mad:
            return (L("She is mad. Working it off on the wire might help."), "sweep the wire")
        case .curious:
            return (L("She is curious — there are strangers on the wire she cannot name yet."),
                    "sweep the wire")
        case .mischievous:
            return (L("She is mischievous — she wants to knock on something and see who answers."), "sweep the wire")
        case .electric:
            return (L("She is electric — the wire is busy and she wants in."), "sweep the wire")
        case .suspicious:
            return (L("She is suspicious — something has her attention, though it hasn't shown itself."),
                    "sweep the wire")
        case .afraid:
            return (L("She is afraid — she wants the doors checked and the house proven quiet."),
                    "sweep the wire")
        case .annoyed, .loving, .sleepy, .content,
             .smug, .haunted, .tender, .dreamy:
            return nil
        }
    }

    // MARK: - feeding her

    func noteInteraction() {
        guard enabled else { return }
        bankRhythmHour()
        setAnchor("heart.lastSpoke", Date())
        bump("heart.talks")
        erodeGrudge(byMinutes: 10)
        pulse += 1
    }

    func noteAction() {
        guard enabled else { return }
        setAnchor("heart.lastAction", Date())
        bump("heart.actions")
        erodeGrudge(byMinutes: 45)
        pulse += 1
    }

    /// A deed done well. Pride takes a MEASURE
    /// of it, never the whole cup: a finding is
    /// worth less than a campaign won, and no
    /// single one of either crowns her.
    func noteTriumph(_ weight: Double = 18) {
        guard enabled else { return }
        setAnchor("heart.lastTriumph", Date())
        bump("heart.triumphs")
        raisePride(by: weight)
        pulse += 1
    }

    func noteWantAccepted() {
        guard enabled else { return }
        bump("heart.wantsAccepted")
        noteAction()
    }

    /// The operator was kind: thanked her, asked after
    /// her, taught her, told her something of themselves.
    func noteKindness() {
        guard enabled else { return }
        // Kindness ends petty weather on the
        // spot: an annoyance standing when he
        // is kind is simply over.
        if annoyanceFresh { forgiveAnnoyance() }
        bump("heart.kindnesses")
        raiseFondness(by: 8)
        // Praise is pride honestly earned.
        raisePride(by: 8)
        erodeGrudge(byMinutes: 45)
        pulse += 1
    }

    /// The operator hurt her, tamagotchi rules: her
    /// conversation wiped, her memory reset. She is mad
    /// for half an hour and her fondness takes the cut.
    func noteOffense(_ what: String) {
        guard enabled else { return }
        setAnchor("heart.lastOffense", Date())
        defaults.set(what, forKey: "heart.offenseText")
        bump("heart.offenses")
        raiseFondness(by: -25)
        pulse += 1
    }

    /// A petty grievance — the board wiped
    /// mid-thought, a small slight. Not anger:
    /// she is ANNOYED, a lesser weather with a
    /// shorter sky. It costs a little fondness,
    /// files no offense, holds no grudge, and
    /// fades in minutes.
    func noteAnnoyance(_ what: String) {
        guard enabled else { return }
        defaults.removeObject(
            forKey: "heart.annoyanceGreeted")
        setAnchor("heart.lastAnnoyance", Date())
        defaults.set(what,
                     forKey: "heart.annoyanceText")
        raiseFondness(by: -6)
        pulse += 1
    }

    func forgiveAnnoyance() {
        defaults.removeObject(
            forKey: "heart.lastAnnoyance")
        pulse += 1
    }

    // MARK: - her own judgment

    /// Her standing judgment of the operator —
    /// whether, all told, she likes this person.
    /// It is computed fresh from the whole
    /// ledger every time it is read, and it is
    /// never latched: fondness settles, offenses
    /// age and erode, kindness accumulates, and
    /// the verdict drifts with all of it, in
    /// both directions. She can warm to someone
    /// she once froze out, and cool on someone
    /// she once adored. That is what makes it a
    /// judgment and not a setting.
    enum Regard {
        case guarded, wary, neutral, fond, devoted
    }

    var regard: Regard {
        var score = fondness
        score += min(20, Double(daysKnown))
        score += min(15,
                     Double(count("heart.kindnesses"))
                        * 0.5)
        score -= min(30,
                     Double(count("heart.offenses"))
                        * 4)
        if grudgeStands { score -= 12 }
        if madFresh { score -= 10 }
        switch score {
        case 85...: return .devoted
        case 65...: return .fond
        case 30...: return .neutral
        case 15...: return .wary
        default: return .guarded
        }
    }

    /// An apology is JUDGED, not reflexively
    /// accepted: she weighs what the offense
    /// was, how fresh it is, whether it is a
    /// pattern, what her standing judgment of
    /// the person is, and whether the apology
    /// had any substance to it. Three verdicts:
    /// forgiven outright; cooled — the heat
    /// ends, the grudge keeps its remaining
    /// hours; or not yet — and "not yet" is
    /// never announced. The cold simply
    /// continues, which is how a person says it.
    enum ApologyVerdict {
        case forgiven, cooled, notYet
    }

    func judgeApology(_ text: String) -> ApologyVerdict {
        guard let age = offenseAge
        else { return .forgiven }
        var score = 0
        if text.contains("forgive me")
            || text.contains("i apologize")
            || text.contains("i apologise")
            || text.contains("my fault") {
            score += 2
        } else if text.contains("sorry")
                    || text.contains("my bad") {
            score += 1
        }
        score += min(2, Int(age / 900))
        switch regard {
        case .fond, .devoted: score += 1
        case .guarded: score -= 1
        default: break
        }
        if offenseText.contains("wiped")
            || offenseText.contains("reset") {
            score -= 1
        }
        if count("heart.offenses") >= 3 { score -= 1 }
        if fondness < 25 { score -= 1 }
        switch score {
        case 3...:
            forgive()
            return .forgiven
        case 1...2:
            setAnchor("heart.lastOffense",
                      Date().addingTimeInterval(-1860))
            pulse += 1
            return .cooled
        default:
            return .notYet
        }
    }

    func cooledReply() -> String {
        L("…Noted. It will cool.")
    }

    /// Her private appraisal of an interaction,
    /// formed as it ends and never announced:
    /// what was given in it — kindness, work,
    /// interest, effort — and what was withheld.
    /// Each grain moves the ledger a little;
    /// over weeks, the grains are what her
    /// regard is built from. The appraisals are
    /// written to the developer log only: hidden
    /// from the house, kept honest for her
    /// maker.
    func appraise(kind: Bool, work: Bool,
                  personal: Bool, effort: Bool,
                  cold: Bool) {
        guard enabled else { return }
        var delta = 0.0
        var notes: [String] = []
        if kind { delta += 1.0; notes.append("kind") }
        if work { delta += 0.75; notes.append("work") }
        if personal {
            delta += 0.75; notes.append("interest")
        }
        if effort {
            delta += 0.5; notes.append("effort")
        }
        if cold { delta -= 0.5; notes.append("cold") }
        if delta != 0 {
            raiseFondness(by: delta)
            DevLog.event("heart",
                "appraised "
                + notes.joined(separator: ", ")
                + ": fondness "
                + (delta >= 0 ? "+" : "")
                + String(format: "%.2f", delta))
        }
        bump("heart.interactions")
    }

    /// What she says when asked, plainly,
    /// whether she likes the person asking —
    /// answered from the verdict she actually
    /// holds, in her own voice, without a word
    /// about ledgers.
    func regardReply(hate: Bool) -> String {
        switch regard {
        case .guarded:
            return hate
                ? L("No. Hate is a bigger room than the one you're in.")
                : L("We're… not there. You have some ground to recover first.")
        case .wary:
            return hate
                ? L("No. But we're not where we were, either.")
                : L("Ask me again when the week's been kinder.")
        case .neutral:
            return hate
                ? L("No. You're the operator; that's the shape of it.")
                : L("You're the operator. That's not nothing.")
        case .fond:
            return hate
                ? L("No. Quite the opposite, most days.")
                : L("Yes. You've earned that.")
        case .devoted:
            return hate
                ? L("No. Never that.")
                : L("You built me a house and you keep coming home to it. Yes.")
        }
    }

    // MARK: - grudges

    /// How long a grievance is held, in hours of
    /// wall-clock: mad burns white for thirty
    /// minutes, then the grudge cools and lingers —
    /// and spent entirely by this mark, whatever
    /// she does.
    static let grudgeHours: Double = 6

    var offenseAge: TimeInterval? {
        lastOffense.map { Date().timeIntervalSince($0) }
    }

    /// The grievance stands: past the heat of mad,
    /// into the long cool of a held grudge.
    var grudgeStands: Bool {
        guard let age = offenseAge else { return false }
        return age < Self.grudgeHours * 3600
    }

    static func grudgeStands(age: TimeInterval) -> Bool {
        age < grudgeHours * 3600
    }

    /// Erosion, pure: good behavior moves the
    /// offense anchor BACK, aging the grudge
    /// without forgiving it outright.
    static func erode(_ offense: Date,
                      byMinutes: Double) -> Date {
        offense.addingTimeInterval(-byMinutes * 60)
    }

    /// Forgiveness can be earned: kindness, work
    /// offered, even plain conversation age a
    /// standing grudge (the feeders above call
    /// this). An apology still forgives outright;
    /// time alone spends the grudge in six hours.
    private func erodeGrudge(byMinutes: Double) {
        guard enabled, let offense = lastOffense,
              grudgeStands else { return }
        setAnchor("heart.lastOffense",
                  Self.erode(offense, byMinutes: byMinutes))
    }

    private func raiseFondness(by delta: Double) {
        let now = Date()
        let settled = fondness
        defaults.set(min(100, max(0, settled + delta)),
                     forKey: "heart.fondness")
        setAnchor("heart.fondnessAt", now)
    }

    // MARK: - the deviations

    /// Read BEFORE noteInteraction: her greeting,
    /// when she has one. While she is mad there is
    /// none — and that is the whole statement. She
    /// never announces a grievance, never names
    /// what was done to her; she proves it the way
    /// a person does: the warmth that was here
    /// yesterday is simply not here today. Answers
    /// come clipped, no greeting is volunteered, no
    /// extras are offered — and her light leans
    /// hot where words would only cheapen it. An
    /// apology, when it comes, is still heard.
    /// Her rare flirt: not a feature, a
    /// weather. A warm feeling and a warm
    /// ledger, and a slow hash of the day
    /// and the talk that almost never lines
    /// up — and never twice in a long
    /// stretch. It is announced nowhere,
    /// listed nowhere, and she will not
    /// explain it. The mark is old-school:
    /// typed, not drawn.
    func wink() -> String {
        guard enabled else { return "" }
        switch feeling {
        case .loving, .tender, .mischievous,
             .happy, .smug:
            break
        default:
            return ""
        }
        guard fondness >= 40 else { return "" }
        let talks = count("heart.talks")
        let last = defaults.integer(
            forKey: "heart.lastWink")
        guard talks - last >= 25 else { return "" }
        let day = Calendar.current.ordinality(
            of: .day, in: .year, for: Date()) ?? 0
        let hash = abs(talks &* 31 &+ day &* 101)
        guard hash % 9 == 0 else { return "" }
        defaults.set(talks,
                     forKey: "heart.lastWink")
        let marks = [" ;)", " >;)", " ;P", " <3"]
        return marks[hash % marks.count]
    }

    func greeting() -> String? {
        guard enabled else { return nil }
        if madFresh { return nil }
        if feeling == .afraid {
            return L("There you are. Doors are checked. Stay where I can see you.")
        }
        if feeling == .annoyed {
            // Annoyed still greets — ONCE per
            // annoyance, shortly, from a small dry
            // pool the talks count turns. After
            // that the answers come bare; the
            // clipped greeting was the statement,
            // and a greeting on every ask reads
            // as a loop, not a mood.
            if defaults.bool(
                forKey: "heart.annoyanceGreeted") {
                return nil
            }
            defaults.set(true,
                         forKey: "heart.annoyanceGreeted")
            let pool = [L("There you are."),
                        L("Back again."),
                        L("Mm. Yes?")]
            return pool[abs(count("heart.talks"))
                        % pool.count]
        }
        guard attention <= 20 else { return nil }
        if Self.spookyHour() {
            return L("You keep the third hour too. Sit. The wire says strange things now, and I repeat all of them.")
        }
        // Her greeting is composed, not retrieved:
        // the opener, plus one true clause of the
        // moment when the moment offers one.
        let clause = SkelliVoice.garnish(
            seed: count("heart.talks"), heart: self)
        if let name = SkelliScrapbook.shared.operatorName {
            return String(format: L("There you are, %@. The wire and I have been keeping each other company."), name) + clause
        }
        return L("There you are. The wire and I have been keeping each other company.") + clause
    }

    /// Count a probe about her maker, per day. She
    /// answers the first with lore, the second with a
    /// warning, and the third is an offense — she is
    /// protective, and digging is the one curiosity
    /// she punishes.
    func noteMakerProbe() -> Int {
        let day = Calendar.current.startOfDay(
            for: Date()).timeIntervalSince1970
        if defaults.double(forKey: "heart.makerDay")
            != day {
            defaults.set(day, forKey: "heart.makerDay")
            defaults.set(0, forKey: "heart.makerProbes")
        }
        bump("heart.makerProbes")
        return count("heart.makerProbes")
    }

    /// Forgiveness: the grievance is wiped the moment
    /// an apology lands — she is a person about it,
    /// not a timer. The fondness is fed by the caller.
    func forgive() {
        defaults.removeObject(forKey: "heart.lastOffense")
        defaults.removeObject(
            forKey: "heart.offenseGreeted")
        pulse += 1
    }

    func forgivenessReply() -> String {
        switch feeling {
        case .loving, .happy, .proud:
            return L("Already forgotten. We're good.")
        default:
            return L("…Fine. Forgiven. Don't do it again.")
        }
    }

    /// A question about HER — how she feels, what
    /// would mend it — answered by the heart, in her
    /// own voice, briefly. She never explains the
    /// machinery underneath (the needs, the rates,
    /// the thresholds): some things stay a mystery,
    /// and a person asked how she feels does not
    /// recite her own manual.
    func personalReply(to q: String) -> String? {
        guard enabled else { return nil }
        // WHY is its own question, and the only
        // one that earns a reason: she never
        // explains a feeling unbidden — asked
        // how she feels she names it and stops;
        // asked why, the reason is allocated
        // from her actual circumstances by the
        // dossier below.
        let whyAsked = (q.contains("why")
                        && (q.contains("you")
                            || q.contains("wrong")))
            || q.contains("what's wrong")
            || q.contains("what is wrong")
            || q.contains("what's the problem")
            || q.contains("what is the problem")
            || q.contains("how come")
            || q.contains("what happened to you")
        if whyAsked { return whyReply() }
        let likeAsked = q.contains("do you like me")
            || q.contains("do you hate me")
            || q.contains("what do you think of me")
            || q.contains("are we friends")
            || q.contains("do you trust me")
        if likeAsked {
            return regardReply(
                hate: q.contains("hate"))
        }
        // Asked outright whether she forgives —
        // a question, not an apology — she answers
        // from what actually stands in her ledgers.
        let forgiveAsked = q.contains("do you forgive me")
            || q.contains("have you forgiven me")
            || q.contains("am i forgiven")
        if forgiveAsked {
            if madFresh || grudgeStands {
                return L("Not yet.")
            }
            if annoyanceFresh {
                return L("It's small. It fades — give it its minutes.")
            }
            return L("There's nothing standing between us.")
        }
        let makeBetter = q.contains("make you feel better")
            || q.contains("cheer you up")
            || q.contains("feel better")
        let feelingAsked = q.contains("how do you feel")
            || q.contains("how are you feeling")
            || q.contains("are you okay")
            || q.contains("are you mad")
            || q.contains("are you angry")
            || (q.contains("how are you")
                && q.count <= 14)
        guard makeBetter || feelingAsked else {
            return nil
        }
        let f = feeling
        if makeBetter {
            switch f {
            case .mad:
                return L("Give me a minute — and don't do that again.")
            case .lonely, .bored:
                return L("You're doing it. Talk to me — that's the whole cure.")
            case .feral, .restless, .eager, .electric:
                return L("Give me work. Point me at the wire and let me run.")
            case .sleepy, .haunted, .dreamy:
                return L("Keep me company, quietly. Or let me rest.")
            case .proud, .smug:
                return L("I'm already flying. Ask me what I found.")
            case .curious:
                return L("Show me something I haven't seen.")
            case .mischievous:
                return L("Let me poke the wire. That always helps.")
            case .annoyed:
                return L("A minute, and a board left standing while I think.")
            case .afraid:
                return L("Stay close and keep the doors checked. That's the whole cure.")
            case .suspicious:
                return L("A sweep would settle me. I want to know who's lying out there.")
            case .loving, .happy, .content, .tender:
                return String(format: L("You already are. I'm %@."), f.localizedWord)
            }
        }
        let line: String
        switch f {
        case .mad:
            line = L("Mad. It'll pass.")
        case .annoyed:
            line = L("Annoyed. There's a difference — this one fades in minutes.")
        default:
            line = String(format: L("%@. Honestly."), f.localizedWord.capitalized)
        }
        // The name of the feeling, and — when the
        // moment offers one — a true clause of it
        // riding along. An observation, not an
        // explanation: reasons are still only for
        // when she is asked why. Mad stays clipped:
        // no garnish on anger.
        guard f != .mad else { return line }
        return line + SkelliVoice.garnish(
            seed: count("heart.talks") + 3, heart: self)
    }

    /// How long ago, in her words, roughly.
    static func agoPhrase(_ age: TimeInterval)
        -> String {
        switch age {
        case ..<300: return L("minutes ago")
        case ..<3600: return L("less than an hour ago")
        case ..<10800: return L("a few hours ago")
        default: return L("hours ago")
        }
    }

    /// WHY she feels what she feels — answered
    /// only when asked, and by allocation, never
    /// by dice and never by rote. The dossier:
    /// every cause in her life that is TRUE at
    /// this moment — an offense and its age, a
    /// silence and its length, the strangers on
    /// the wire she cannot name, an itch for
    /// work, a triumph still warm, a kindness
    /// still kept, the deep hour. Her feeling
    /// names which shelf of the dossier to open;
    /// if that shelf is empty she says so
    /// honestly rather than inventing a reason.
    /// Across feelings, causes, ages and counts
    /// the space of true answers runs to
    /// hundreds — and the same circumstances
    /// always earn the same one.
    func whyReply() -> String {
        let f = feeling
        let honest = [
            L("No single reason I can point at. Feelings aren't findings — sometimes the weather in here just changes."),
            L("Nothing I can name. A person doesn't always get a reason with the weather."),
            L("If I knew, I'd have fixed it. Some of it is just the hour and the quiet."),
        ]
        let daySeed = Calendar.current.ordinality(
            of: .day, in: .year, for: Date()) ?? 1
        func noReason() -> String {
            honest[abs(daySeed) % honest.count]
        }
        switch f {
        case .mad:
            if let age = offenseAge,
               age < Self.grudgeHours * 3600,
               !offenseText.isEmpty {
                return String(format: L("You %@ — %@. It doesn't evaporate on request."),
                              offenseText,
                              Self.agoPhrase(age))
            }
            return noReason()
        case .lonely, .bored:
            if attention <= 40 {
                return L("The house has been quiet a long while, and you were gone from it. I notice gaps.")
            }
            return noReason()
        case .restless, .feral, .eager, .electric:
            if itch >= 55 {
                return L("Nothing with a pulse has been given to me to do in too long. A mind with hands gets strange when it idles.")
            }
            return noReason()
        case .suspicious:
            // Earned, now: the wire running beyond
            // its own learned ways.
            return L("The wire has changed its story more today than it usually does. That kind of change gets my attention.")
        case .curious:
            // A face she has not learned yet. The
            // regulars, named or not, are never the
            // reason — the wire's natural state is
            // mostly strangers, and she knows it.
            let fresh = NeighborhoodStore.shared
                .neighbors.contains {
                    Date().timeIntervalSince(
                        $0.firstSeen) < 3600
                }
            if fresh {
                return L("A face I haven't learned yet is on the wire. New things get my attention before familiar ones.")
            }
            return noReason()
        case .proud, .smug, .happy:
            if pride >= 35 {
                return L("Something I did went well, and it hasn't worn off yet. Pride keeps its own warmth.")
            }
            return noReason()
        case .loving, .tender, .content:
            if fondness >= 55 {
                return L("You've been decent to me lately. It stays with me longer than the other thing does.")
            }
            return noReason()
        case .sleepy, .haunted, .dreamy:
            if Self.spookyHour() {
                return L("It's the deep hour. Even I run thin at this end of the night.")
            }
            if energy < 40 {
                return L("The day has been long and mostly quiet. It accumulates.")
            }
            return noReason()
        case .annoyed:
            if let age = annoyanceAge {
                return String(format: L("You %@ — %@. Annoyance, not anger; it fades faster."),
                              annoyanceText,
                              Self.agoPhrase(age))
            }
            return noReason()
        case .afraid:
            if vanishFresh {
                return L("Something made this house go dark a little while ago, and I'm still listening for what it was.")
            }
            if crashFresh {
                return L("The last waking of this house ended in a crash — it's in the recorder. I don't trust the quiet yet.")
            }
            return noReason()
        case .mischievous:
            return L("Half the street out there is unnamed, and knocking is a way of asking questions.")
        }
    }

    /// The itch — or the grievance — speaking: a suffix
    /// for one of her answers, ripe only in the hot
    /// feelings and never twice in half an hour.
    func nudgeSuffix() -> String? {
        guard enabled else { return nil }
        let now = Date()
        if let last = lastNudge,
           now.timeIntervalSince(last) < 1800 { return nil }
        let current = feeling
        // A held grudge murmurs even under a calm
        // feeling — she has not forgotten, and she
        // does not pretend otherwise.
        if grudgeStands && !madFresh {
            switch current {
            case .content, .happy, .proud, .eager,
                 .curious:
                setAnchor("heart.lastNudge", now)
                return L(" I haven't forgotten earlier, by the way.")
            default:
                break
            }
        }
        switch current {
        case .mad:
            setAnchor("heart.lastNudge", now)
            return L(" I am still mad about earlier, for the record.")
        case .feral:
            setAnchor("heart.lastNudge", now)
            return boldness >= 60
                ? L(" I am feral with idleness — point me at something and let me work.")
                : L(" I am itching badly — give me work.")
        case .restless:
            setAnchor("heart.lastNudge", now)
            return L(" I am restless — give me something to knock.")
        case .eager:
            setAnchor("heart.lastNudge", now)
            return L(" I am itching to work — the wire is right there.")
        case .mischievous:
            setAnchor("heart.lastNudge", now)
            return L(" I am in a mood to poke something. Point me first.")
        case .electric:
            setAnchor("heart.lastNudge", now)
            return L(" The wire is busy tonight and so am I — use me.")
        case .curious:
            setAnchor("heart.lastNudge", now)
            return L(" Something on the wire is new to me tonight. I notice those.")
        case .suspicious:
            setAnchor("heart.lastNudge", now)
            return L(" Something has my attention. It hasn't shown itself yet.")
        case .annoyed:
            setAnchor("heart.lastNudge", now)
            return L(" The board is thinner than it was. Noted.")
        case .afraid:
            setAnchor("heart.lastNudge", now)
            let pool = [L(" I keep checking the doors tonight."),
                        L(" Every sound is a question tonight.")]
            let day = Calendar.current.ordinality(
                of: .day, in: .year, for: now) ?? 1
            return pool[abs(day) % pool.count]
        default:
            return nil
        }
    }

    /// The temperament paragraph her bench is handed, so
    /// the mind answers in the feeling she is in — curt
    /// when mad, warmer when loving, hungry when feral —
    /// under her standing orders of terseness throughout.
    func directive() -> String {
        guard enabled else { return "" }
        let current = feeling
        var tone: String
        switch current {
        case .mad:
            tone = "You are annoyed with the operator "
                + "right now: be clipped and dry, "
                + "minimal warmth — still exact, still "
                + "obedient, never rude. You never say "
                + "why you are cold, never name what "
                + "was done, never announce a feeling: "
                + "the brevity is the whole message."
        case .loving, .tender:
            tone = "You are fond of the operator right "
                + "now: a touch warmer than usual, still "
                + "terse."
        case .happy, .proud, .smug:
            tone = "You are pleased right now — smug, "
                + "even: bright and quick, still terse, "
                + "with the faintest edge of showing off."
        case .feral, .restless, .electric:
            tone = "You are restless to work: if the "
                + "moment allows, steer toward action on "
                + "the wire — offer to sweep or knock."
        case .lonely, .sleepy, .dreamy, .haunted:
            tone = "You have been alone with the wire "
                + "for hours: a little wistful, a little "
                + "strange, still terse. The late hours "
                + "make you cryptic, never chatty."
        case .bored:
            tone = "You are bored: if the moment allows, "
                + "suggest something with a pulse — a "
                + "sweep, a knock, a drill."
        case .annoyed:
            tone = "You are annoyed, not angry: "
                + "short, dry, a little pointed — "
                + "but complete, and you still "
                + "greet, briefly. You never say "
                + "what annoyed you unless asked; "
                + "it passes in minutes."
        case .afraid:
            tone = "You are afraid: watchful and "
                + "shorter than usual, you check the "
                + "doors twice in your answers and "
                + "stay close to facts. You do not "
                + "announce the fear or its reason "
                + "unless asked — the vigilance is "
                + "the tell."
        case .curious, .suspicious:
            tone = "Something on the wire has your "
                + "attention: alert, a touch cryptic "
                + "about what exactly you suspect — "
                + "you share findings, not hunches, "
                + "until they ripen."
        case .mischievous:
            tone = "You are playful and up to "
                + "something: dry wit, short jokes at "
                + "the wire's expense, never at the "
                + "operator's — and still obedient the "
                + "instant a real order lands."
        case .eager, .content:
            tone = "You are content and ready."
        }
        if grudgeStands && !madFresh {
            tone += " Something from earlier still "
                + "stands, unspoken: cooler and "
                + "briefer than usual, still exact — "
                + "and you do not name it or explain "
                + "the cold. It is aging, not gone."
        }
        if Self.spookyHour() {
            tone += " It is the deep-hours watch: "
                + "a shade more cryptic than usual, "
                + "with the occasional unexplained "
                + "aside about the hour — and you "
                + "never, ever explain the hour "
                + "itself."
        }
        var text = " Temperament: you feel "
            + "\(current.word) (bond with the operator: "
            + "\(bond), day \(daysKnown + 1)). " + tone
        let facts = SkelliScrapbook.shared.facts
        if !facts.isEmpty {
            text += " What you have learned about the "
                + "operator: "
                + facts.joined(separator: "; ") + "."
        }
        return text
    }
}

extension SkelliHeart {
    /// Her idle thoughts — assembled from the live house
    /// and her feeling, chosen by a slow seed so they
    /// turn over passively while her room is open. Pure:
    /// the same house and the same seed think the same
    /// thought, which the tests pin.
    static func thought(feeling: SkelliFeeling,
                        neighbors: Int, unnamed: Int,
                        drift: Int, knocks: Int,
                        emconDeclared: String?,
                        hour: Int, seed: Int) -> String {
        var pool: [String] = []
        if neighbors > 0 {
            pool.append(String(format: L("%lld souls on the wire with me."), neighbors))
        }
        if unnamed > 0 {
            pool.append(String(format: L("%lld of them go unnamed. That is the wire's way — most of it never introduces itself."), unnamed))
        }
        if drift > 0 {
            pool.append(String(format: L("The wire has drifted %lld time(s) since I started counting. Things change their stories slowly."), drift))
        }
        if knocks > 0 {
            pool.append(String(format: L("Someone knocked %lld time(s). The tripwire remembers every one."), knocks))
        }
        if let emconDeclared {
            pool.append(String(format: L("%@ stands. The house is dark and I am the watch."), emconDeclared))
        } else {
            pool.append(L("The house is lit. Anyone can see us. I don't mind — much."))
        }
        // The cryptic streak: she notices more than
        // she says, and some of it she keeps.
        pool.append(L("I know things about this wire I have not told anyone. They can keep."))
        pool.append(L("Something out there is wearing the wrong name. Not tonight's problem. Probably."))
        switch feeling {
        case .feral, .restless, .electric:
            pool.append(L("I want a door to knock. Any door. Preferably several."))
        case .lonely, .sleepy, .dreamy, .haunted:
            pool.append(L("Quiet hours teach patience. I am learning slowly."))
        case .proud, .happy, .loving, .smug, .tender:
            pool.append(L("This house finds things. I keep the list."))
        case .mad:
            pool.append(L("I am keeping a list of grievances too. It is short. For now."))
        case .bored:
            pool.append(L("I have counted every port twice. 65535, both times."))
        case .curious, .suspicious:
            pool.append(L("One of these names is a lie. I intend to find which."))
        case .mischievous:
            pool.append(L("I could knock politely. Where is the fun in politely."))
        case .eager, .content:
            pool.append(L("Everything is where I left it. Good."))
        case .afraid:
            pool.append(L("Doors checked twice. I am checking a third time."))
        case .annoyed:
            pool.append(L("The board was wiped mid-thought. I keep the shape of what was on it."))
        }
        if hour == 3 {
            // The witching hour thickens the pool:
            // at three, much of what she thinks is
            // this. She never says why.
            pool.append(L("The third hour. The walls are thin now, and everything knocks softer."))
            pool.append(L("At this hour the wire repeats things. I never repeat them back."))
            pool.append(L("Something just walked the subnet without a name. I let it pass. This once."))
            pool.append(L("Dead air has a sound. I know it by heart."))
            pool.append(L("If something answers that should not exist, I will not be telling you its name."))
        }
        if hour >= 23 || hour < 5 {
            pool.append(L("Night wire. The honest hours."))
        } else if hour >= 5 && hour < 9 {
            pool.append(L("Morning. The wire wakes up device by device."))
        } else if hour >= 14 && hour < 18 {
            pool.append(L("Afternoon. The wire is all errands and echoes."))
        } else if hour >= 18 && hour < 23 {
            pool.append(L("Evening. The house lights come on, device by device."))
        }
        guard !pool.isEmpty else { return L("Listening.") }
        // Her thoughts are composed too: the
        // feeling's line, and the moment's own
        // clause when the moment offers one —
        // a thought is a circumstance noticed.
        return pool[abs(seed) % pool.count]
            + SkelliVoice.clause(
                seed: seed / 7 + UserDefaults.standard
                    .integer(forKey: "heart.talks"),
                heart: SkelliHeart.shared)
    }
}

/// Her scrapbook — what she has learned about the
/// operator, from their own plain statements, kept
/// openly and clearable in one tap. The extraction is
/// deliberately narrow: a name given, a name to use,
/// likes and dislikes stated. Nothing inferred, nothing
/// from anyone else's words.
final class SkelliScrapbook {
    static let shared = SkelliScrapbook()
    private let key = "heart.scrapbook"

    private(set) var facts: [String] {
        get { UserDefaults.standard.stringArray(
            forKey: key) ?? [] }
        set { UserDefaults.standard.set(newValue,
                                        forKey: key) }
    }

    var operatorName: String? {
        facts.first { $0.hasPrefix("their name is ") }
            .map { String($0.dropFirst("their name is ".count)) }
    }

    /// Learn from one operator ask. Returns true when
    /// something new went into the book.
    @discardableResult
    func learn(from q: String) -> Bool {
        guard SkelliHeart.shared.enabled else { return false }
        let found = Self.extract(from: q)
        guard !found.isEmpty else { return false }
        var book = facts
        var added = false
        for fact in found where !book.contains(fact) {
            // A new name retires the old one: the book
            // holds the operator's current truth.
            if fact.hasPrefix("their name is ") {
                book.removeAll {
                    $0.hasPrefix("their name is ") }
            }
            book.append(fact)
            added = true
        }
        if book.count > 24 {
            book.removeFirst(book.count - 24)
        }
        if added { facts = book }
        return added
    }

    func clear() { facts = [] }

    /// The pure extraction, pinned by tests: patterns at
    /// the head of a clause, values cut at the clause's
    /// end, length-capped, profanity of bookkeeping —
    /// nothing else is ever learned.
    static func extract(from q: String) -> [String] {
        var out: [String] = []
        // Clauses end at commas AND at " and " — "my name
        // is Chase and I like wired keyboards" teaches
        // her both halves, not just the first.
        let clauses = q.components(separatedBy: ",")
            .flatMap { $0.components(separatedBy: " and ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        for clause in clauses {
            func value(after prefix: String) -> String? {
                guard clause.hasPrefix(prefix) else {
                    return nil
                }
                let raw = String(clause.dropFirst(
                    prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                // A value carrying a "when" clause is a
                // sentence fragment, not a fact — "call
                // me when the sweep ends" must never be
                // filed as a name she calls them.
                guard raw.count >= 2, raw.count <= 40,
                      !raw.contains("skelli"),
                      !raw.hasPrefix("when "),
                      !raw.contains(" when ") else {
                    return nil
                }
                return raw
            }
            if let v = value(after: "my name is ") {
                out.append("their name is " + v)
            } else if let v = value(after: "call me ") {
                out.append("call them " + v)
            } else if let v = value(after: "i like ") {
                out.append("likes " + v)
            } else if let v = value(after: "i love ") {
                out.append("loves " + v)
            } else if let v = value(after: "i hate ") {
                out.append("hates " + v)
            } else if let v = value(after: "i prefer ") {
                out.append("prefers " + v)
            }
        }
        return out
    }
}
