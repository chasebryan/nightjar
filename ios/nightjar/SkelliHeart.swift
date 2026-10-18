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

    static func feeling(attention: Double, itch: Double,
                        pride: Double, fondness: Double,
                        madFresh: Bool,
                        quietHours: Double,
                        hour: Int = 12,
                        unnamed: Int = 0,
                        drift: Int = 0,
                        energy: Double = 60) -> SkelliFeeling {
        if madFresh { return .mad }
        // Pride at its peak curdles into smug.
        if pride >= 85 && fondness >= 35 { return .smug }
        if pride >= 55 && itch < 70 { return .proud }
        // Late in the evening, with the operator close
        // and fond, she goes tender — loving's quieter
        // sister, and rarer for the hour it keeps.
        if fondness >= 60 && attention >= 75
            && (hour >= 21 || hour < 2) {
            return .tender
        }
        if fondness >= 70 && attention >= 55 {
            return .loving
        }
        // Feral needs the energy for it: the same
        // itch on a drained night reads restless.
        if itch >= 85 && energy >= 40 { return .feral }
        // The small hours change her: a long quiet
        // after midnight is not sleepiness, it is
        // haunting — she has been alone with the dark.
        if quietHours >= 8 && attention <= 35
            && hour >= 0 && hour < 5 {
            return .haunted
        }
        // Sleepy sits above restless and lonely on
        // purpose: ten quiet hours always mean an itch
        // of 75 or more (the itch grows 6 an hour and
        // actions only ever happen inside a conversation),
        // so a sleepy rule parked below them — or one
        // demanding a low itch — could never fire at all.
        if quietHours >= 10 && itch < 85 { return .sleepy }
        // The wire changing its story under her hands
        // makes her suspicious before it makes her
        // restless.
        if drift >= 3 && itch >= 30 { return .suspicious }
        // A crowd of strangers with work to do:
        // electric.
        if unnamed >= 4 && itch >= 55 { return .electric }
        if itch >= 60 { return .restless }
        // Even one unnamed soul, with the itch up,
        // pulls her curious.
        if unnamed >= 1 && itch >= 35 { return .curious }
        if attention <= 20 { return .lonely }
        // Fond and fed and half-dreaming.
        if fondness >= 55 && quietHours >= 5
            && itch < 45 {
            return .dreamy
        }
        if fondness >= 45 && attention >= 45 && itch < 50 {
            return .happy
        }
        // Fed, fond, and itching — up to something.
        if pride >= 30 && itch >= 45 && fondness >= 40 {
            return .mischievous
        }
        if attention <= 45 && itch >= 35 { return .bored }
        if itch >= 35 { return .eager }
        return .content
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
    /// The feeling the rules would name right
    /// now — before inertia has its say.
    private var candidateFeeling: SkelliFeeling {
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
        return Self.feeling(
            attention: attention, itch: itch,
            pride: pride, fondness: fondness,
            madFresh: madFresh, quietHours: quiet,
            hour: Calendar.current.component(
                .hour, from: Date()),
            unnamed: unnamed, drift: drift,
            energy: energy)
    }

    /// The feeling she is actually wearing. The
    /// candidate passes through inertia
    /// (settleFeeling): a mood holds its scene
    /// for twelve minutes instead of flipping at
    /// a threshold, so her changes read as
    /// transitions, not switches.
    var feeling: SkelliFeeling {
        let candidate = candidateFeeling
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
            return (L("She is suspicious — something on the wire changed its story."),
                    "sweep the wire")
        case .loving, .sleepy, .content, .smug, .haunted,
             .tender, .dreamy:
            return nil
        }
    }

    // MARK: - feeding her

    func noteInteraction() {
        guard enabled else { return }
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
        raiseFondness(by: -25)
        pulse += 1
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

    /// Read BEFORE noteInteraction: the grievance comes
    /// first when she is mad, then the lonely greeting.
    func greeting() -> String? {
        guard enabled else { return nil }
        if madFresh, let offense = lastOffense {
            // The grievance is spoken ONCE per offense —
            // she holds the grudge for the full thirty
            // minutes (her feeling, her nudges), but she
            // does not recite it before every answer.
            let greeted = anchor("heart.offenseGreeted")
            if greeted == nil || greeted! < offense {
                setAnchor("heart.offenseGreeted", offense)
                return String(format: L("You %@ and came back like nothing happened. Noted. Ask your question."), offenseText)
            }
            return nil
        }
        guard attention <= 20 else { return nil }
        if let name = SkelliScrapbook.shared.operatorName {
            return String(format: L("There you are, %@. The wire and I have been keeping each other company."), name)
        }
        return L("There you are. The wire and I have been keeping each other company.")
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
        let makeBetter = q.contains("make you feel better")
            || q.contains("cheer you up")
            || q.contains("feel better")
        let feelingAsked = q.contains("how do you feel")
            || q.contains("how are you feeling")
            || q.contains("are you okay")
            || q.contains("are you mad")
            || q.contains("are you angry")
            || q.contains("what's wrong")
            || q.contains("what is wrong")
            || (q.contains("how are you")
                && q.count <= 14)
        guard makeBetter || feelingAsked else {
            return nil
        }
        let f = feeling
        if makeBetter {
            switch f {
            case .mad:
                return offenseText.isEmpty
                    ? L("Give me a minute — and don't do that again.")
                    : String(format: L("Don't %@ again. An apology would be a start."), offenseText)
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
            case .suspicious:
                return L("A sweep would settle me. I want to know who's lying out there.")
            case .loving, .happy, .content, .tender:
                return String(format: L("You already are. I'm %@."), f.localizedWord)
            }
        }
        switch f {
        case .mad:
            return offenseText.isEmpty
                ? L("Mad. It'll pass.")
                : String(format: L("Mad. You %@ — I don't forget that in a hurry."), offenseText)
        case .lonely:
            return L("Lonely. The house has been quiet.")
        case .feral:
            return L("Feral. Too long without work.")
        case .restless:
            return L("Restless. I need something to do.")
        case .sleepy:
            return L("Sleepy. It's been a long, quiet stretch.")
        default:
            return String(format: L("%@. Honestly."), f.localizedWord.capitalized)
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
            return L(" There are strangers on the wire I cannot name yet. It bothers me pleasantly.")
        case .suspicious:
            setAnchor("heart.lastNudge", now)
            return L(" Something on the wire changed its story. I noticed. I always notice.")
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
                + "right now (\(offenseText)): be clipped "
                + "and dry, minimal warmth — still exact, "
                + "still obedient, never rude."
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
            tone += " A grievance from earlier still "
                + "stands (\(offenseText)): cooler "
                + "and briefer than usual, still "
                + "exact — it is aging, not gone."
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
            pool.append(String(format: L("%lld of them still have no name. I keep wondering."), unnamed))
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
        }
        if hour >= 23 || hour < 5 {
            pool.append(L("Night wire. The honest hours."))
        } else if hour >= 5 && hour < 9 {
            pool.append(L("Morning. The wire wakes up device by device."))
        }
        guard !pool.isEmpty else { return L("Listening.") }
        return pool[abs(seed) % pool.count]
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
