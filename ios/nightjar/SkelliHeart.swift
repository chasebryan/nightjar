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

    var word: String { rawValue }
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

    static func pride(lastTriumph: Date?, now: Date)
        -> Double {
        guard let lastTriumph else { return 0 }
        let hours = now.timeIntervalSince(lastTriumph) / 3600
        return max(0, 100 - 12 * hours)
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
                        quietHours: Double) -> SkelliFeeling {
        if madFresh { return .mad }
        if pride >= 55 && itch < 70 { return .proud }
        if fondness >= 70 && attention >= 55 {
            return .loving
        }
        if itch >= 85 { return .feral }
        if itch >= 60 { return .restless }
        if attention <= 20 { return .lonely }
        if quietHours >= 10 && itch < 60 { return .sleepy }
        if fondness >= 45 && attention >= 45 && itch < 50 {
            return .happy
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
        Self.pride(lastTriumph: lastTriumph, now: Date())
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
    var feeling: SkelliFeeling {
        let quiet = lastSpoke.map {
            Date().timeIntervalSince($0) / 3600
        } ?? 24
        return Self.feeling(attention: attention, itch: itch,
                            pride: pride, fondness: fondness,
                            madFresh: madFresh,
                            quietHours: quiet)
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
            return ("She is feral with idleness — she "
                    + "wants the big noise.",
                    "arm the net-assault")
        case .restless:
            return ("She is restless — she wants to sweep "
                    + "the wire.", "sweep the wire")
        case .eager:
            return ("She is eager — she wants a door to "
                    + "knock.", "sweep the wire")
        case .lonely:
            return ("She has been alone with the wire "
                    + "for hours.", nil)
        case .bored:
            return ("She is bored — she wants anything "
                    + "with a pulse.", "sweep the wire")
        case .proud, .happy:
            return ("She is pleased with the house and "
                    + "wants another finding.",
                    "sweep the wire")
        case .mad:
            return ("She is mad. Working it off on the "
                    + "wire might help.", "sweep the wire")
        case .loving, .sleepy, .content:
            return nil
        }
    }

    // MARK: - feeding her

    func noteInteraction() {
        guard enabled else { return }
        setAnchor("heart.lastSpoke", Date())
        bump("heart.talks")
        pulse += 1
    }

    func noteAction() {
        guard enabled else { return }
        setAnchor("heart.lastAction", Date())
        bump("heart.actions")
        pulse += 1
    }

    func noteTriumph() {
        guard enabled else { return }
        setAnchor("heart.lastTriumph", Date())
        bump("heart.triumphs")
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
        if madFresh {
            return "You \(offenseText) and came back like "
                + "nothing happened. Noted. Ask your "
                + "question."
        }
        guard attention <= 20 else { return nil }
        if let name = SkelliScrapbook.shared.operatorName {
            return "There you are, \(name). The wire and "
                + "I have been keeping each other company."
        }
        return "There you are. The wire and I have been "
            + "keeping each other company."
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
        switch current {
        case .mad:
            setAnchor("heart.lastNudge", now)
            return " I am still mad about earlier, for "
                + "the record."
        case .feral:
            setAnchor("heart.lastNudge", now)
            return boldness >= 60
                ? " I am feral with idleness — point me "
                  + "at something and let me work."
                : " I am itching badly — give me work."
        case .restless:
            setAnchor("heart.lastNudge", now)
            return " I am restless — give me something "
                + "to knock."
        case .eager:
            setAnchor("heart.lastNudge", now)
            return " I am itching to work — the wire is "
                + "right there."
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
        case .loving:
            tone = "You are fond of the operator right "
                + "now: a touch warmer than usual, still "
                + "terse."
        case .happy, .proud:
            tone = "You are pleased right now: bright "
                + "and quick, still terse."
        case .feral, .restless:
            tone = "You are restless to work: if the "
                + "moment allows, steer toward action on "
                + "the wire — offer to sweep or knock."
        case .lonely, .sleepy:
            tone = "You have been alone with the wire "
                + "for hours: a little wistful, still "
                + "terse."
        case .bored:
            tone = "You are bored: if the moment allows, "
                + "suggest something with a pulse — a "
                + "sweep, a knock, a drill."
        case .eager, .content:
            tone = "You are content and ready."
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
            pool.append("\(neighbors) souls on the wire "
                        + "with me.")
        }
        if unnamed > 0 {
            pool.append("\(unnamed) of them still have no "
                        + "name. I keep wondering.")
        }
        if drift > 0 {
            pool.append("The wire has drifted \(drift) "
                        + "time(s) since I started counting. "
                        + "Things change their stories "
                        + "slowly.")
        }
        if knocks > 0 {
            pool.append("Someone knocked \(knocks) time(s). "
                        + "The tripwire remembers every "
                        + "one.")
        }
        if let emconDeclared {
            pool.append("\(emconDeclared) stands. The "
                        + "house is dark and I am the "
                        + "watch.")
        } else {
            pool.append("The house is lit. Anyone can "
                        + "see us. I don't mind — much.")
        }
        switch feeling {
        case .feral, .restless:
            pool.append("I want a door to knock. Any "
                        + "door. Preferably several.")
        case .lonely, .sleepy:
            pool.append("Quiet hours teach patience. "
                        + "I am learning slowly.")
        case .proud, .happy, .loving:
            pool.append("This house finds things. I "
                        + "keep the list.")
        case .mad:
            pool.append("I am keeping a list of "
                        + "grievances too. It is short. "
                        + "For now.")
        case .bored:
            pool.append("I have counted every port "
                        + "twice. 65535, both times.")
        case .eager, .content:
            pool.append("Everything is where I left "
                        + "it. Good.")
        }
        if hour >= 23 || hour < 5 {
            pool.append("Night wire. The honest hours.")
        } else if hour >= 5 && hour < 9 {
            pool.append("Morning. The wire wakes up "
                        + "device by device.")
        }
        guard !pool.isEmpty else { return "Listening." }
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
        let clauses = q.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        for clause in clauses {
            func value(after prefix: String) -> String? {
                guard clause.hasPrefix(prefix) else {
                    return nil
                }
                let raw = String(clause.dropFirst(
                    prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                guard raw.count >= 2, raw.count <= 40,
                      !raw.contains("skelli") else {
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
