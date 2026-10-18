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

    /// The circumstance clauses true RIGHT NOW,
    /// as sentence fragments (leading space, ready
    /// to ride on an opener). A clause about the
    /// quiet requires quiet; a clause about the
    /// unnamed requires the unnamed.
    static func eligibleClauses(
        heart: SkelliHeart) -> [String] {
        var out: [String] = []
        let unnamed = unnamedCount()
        if unnamed == 1 {
            out.append(L(" One name on this wire answers to nothing yet."))
        } else if unnamed > 1 {
            out.append(String(format: L(" %lld names on this wire answer to nothing yet."),
                              unnamed))
        }
        if let spoke = anchor("heart.lastSpoke") {
            let quiet = Date().timeIntervalSince(spoke)
            if quiet >= 3 * 3600 {
                out.append(L(" It's been quiet for hours."))
            } else if quiet >= 3600 {
                out.append(L(" It's been quiet a while."))
            }
        }
        let hour = Calendar.current.component(
            .hour, from: Date())
        if hour == 3 {
            out.append(L(" The walls are thin at this hour."))
        }
        if (5..<7).contains(hour) {
            out.append(L(" The wire is only just waking."))
        }
        if hour >= 22 {
            out.append(L(" The house is settling for the night."))
        }
        if heart.daysKnown >= 3, heart.fondness >= 55 {
            out.append(L(" You keep coming home to this house. I notice that."))
        }
        if let triumph = anchor("heart.lastTriumph"),
           Date().timeIntervalSince(triumph) < 7200 {
            out.append(L(" The house found something earlier. It still pleases me."))
        }
        return out
    }

    /// Choose at most one clause for this moment:
    /// the seed walks the eligible set plus two
    /// silences, so a bare opener stays common —
    /// garnish is occasional or it becomes noise.
    static func clause(seed: Int,
                       heart: SkelliHeart) -> String {
        let pool = eligibleClauses(heart: heart)
        guard !pool.isEmpty else { return "" }
        let pick = abs(seed) % (pool.count + 2)
        return pick < pool.count ? pool[pick] : ""
    }
}
