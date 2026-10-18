import Foundation

/// Her deterministic brain: the layer between the
/// operator's words and everything she does with
/// them. Until now her routing matched raw
/// substrings — "sweep" caught, "swept" missed,
/// and "don't sweep" swept. This layer gives her
/// three things she lacked:
///
/// - Word sense: tokenizing and light stemming,
///   so inflections of a word are the word.
/// - Negation: "don't", "never", "not" in front
///   of an action verb means the action does NOT
///   happen — she acknowledges and keeps her
///   hands off.
/// - Ranked knowledge: the manual is searched by
///   stemmed overlap across keywords, titles and
///   bodies, so a paraphrased question still finds
///   its page — and a dead end can name the
///   closest pages instead of shrugging.
///
/// Pure and deterministic, every rule testable:
/// the same sentence always routes the same way.
enum SkelliBrain {

    // MARK: - Words

    /// The ask as bare words: lowercased,
    /// apostrophes folded ("don't" → "dont"),
    /// everything else a separator.
    static func tokens(_ text: String) -> [String] {
        let folded = text.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
        return folded
            .components(separatedBy:
                CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// A light English stemmer — enough for
    /// routing: "sweeping"/"swept" shapes are not
    /// handled (irregulars stay the chain's
    /// business), but the regular families fold:
    /// sealing/sealed/seals → seal, batteries →
    /// battery, scans → scan, devices → device.
    static func stem(_ token: String) -> String {
        var word = token
        if word.count > 4, word.hasSuffix("ing") {
            word = undouble(String(word.dropLast(3)))
        } else if word.count > 3, word.hasSuffix("ed") {
            word = undouble(String(word.dropLast(2)))
        } else if word.count > 3, word.hasSuffix("ies") {
            word = String(word.dropLast(3)) + "y"
        } else if word.count > 3, word.hasSuffix("es"),
                  let before = word.dropLast(2).last,
                  "sxz".contains(before)
                    || word.dropLast(2).hasSuffix("ch")
                    || word.dropLast(2).hasSuffix("sh") {
            word = String(word.dropLast(2))
        } else if word.count > 2, word.hasSuffix("s"),
                  !word.hasSuffix("ss") {
            word = String(word.dropLast())
        }
        return word
    }

    private static func undouble(_ word: String) -> String {
        guard word.count > 2 else { return word }
        let last = word.last!
        if word.dropLast().last == last,
           !"aeiou".contains(last) {
            return String(word.dropLast())
        }
        return word
    }

    static func stemmed(_ text: String) -> [String] {
        tokens(text).map(stem)
    }

    static func stemSet(_ text: String) -> Set<String> {
        Set(stemmed(text))
    }

    // MARK: - Negation

    private static let negators: Set<String> = [
        "dont", "never", "not", "no", "stop",
        "cancel", "quit",
    ]

    /// The action verbs her hands answer to, as
    /// stems — the set the guard protects.
    private static let actionStems: Set<String> = [
        "sweep", "scan", "audit", "serve", "start",
        "stop", "listen", "watch", "trace", "knock",
        "fuzz", "scream", "hunt", "forge", "send",
        "host", "dark", "name", "run", "raise",
        "open", "close", "clear", "delete", "wipe",
    ]

    /// When the ask negates an action — a negator
    /// within three words before an action verb —
    /// the surface verb it negates, else nil.
    /// "stop everything" is safe: "everything" is
    /// no action, and Vanish has already claimed
    /// the sentence before this is consulted.
    static func negatedAction(_ text: String) -> String? {
        let words = tokens(text)
        let stems = words.map(stem)
        for index in stems.indices
        where negators.contains(stems[index]) {
            let window = stems[
                (index + 1)..<min(stems.count, index + 4)]
            for (offset, candidate) in window.enumerated()
            where actionStems.contains(candidate) {
                return words[index + 1 + offset]
            }
        }
        return nil
    }

    // MARK: - Ranked knowledge

    /// Every entry scored against the ask:
    /// a keyword whose stems all appear earns 3,
    /// a title word 2, a body word 1 (at most 4
    /// counted). Sorted best first, ties keeping
    /// the manual's own order.
    static func rankKnowledge(
        _ query: String,
        entries: [SkelliEntry]
    ) -> [(entry: SkelliEntry, score: Int)] {
        let queryStems = stemSet(query)
        guard !queryStems.isEmpty else { return [] }
        var scored: [(Int, Int, SkelliEntry)] = []
        for (order, entry) in entries.enumerated() {
            var score = 0
            for keyword in entry.keywords {
                let keyStems = stemSet(keyword)
                if !keyStems.isEmpty,
                   keyStems.isSubset(of: queryStems) {
                    score += 3
                }
            }
            for word in tokens(entry.title)
            where word.count > 3 {
                if queryStems.contains(stem(word)) {
                    score += 2
                }
            }
            let bodyStems = stemSet(entry.body)
            score += min(4, bodyStems
                .intersection(queryStems).count)
            if score > 0 {
                scored.append((score, order, entry))
            }
        }
        return scored
            .sorted { $0.0 != $1.0
                ? $0.0 > $1.0 : $0.1 < $1.1 }
            .map { (entry: $0.2, score: $0.0) }
    }

    /// The best page for a paraphrased ask, when
    /// the evidence clears the floor.
    static func bestKnowledge(
        _ query: String,
        entries: [SkelliEntry]
    ) -> SkelliEntry? {
        guard let top = rankKnowledge(query,
                                      entries: entries).first,
              top.score >= 4 else { return nil }
        return top.entry
    }
}
