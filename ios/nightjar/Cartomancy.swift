import Foundation

/// Cartomancy — her parlor art.
///
/// Ask her about tarot and she will correct you,
/// gently and forever: "oh, I actually prefer
/// cartomancy." The fortune is told with an
/// ordinary deck of fifty-two, the old way —
/// no arcana, no theatre props, just the cards
/// and what they have always meant.
///
/// It is a game, and it keeps its state like
/// one: the deck is real. Cards dealt stay on
/// the table; the deck thins as she reads, and
/// only when it runs low does she gather the
/// fallen and shuffle. Spreads of one, three,
/// and five; questions put to the deck by name;
/// and in the full fortune the crown card lies
/// face-down until he says the word — some
/// futures are his to open or to leave.

final class CartomancyDeck {
    static let shared = CartomancyDeck()

    struct Card {
        let name: String
        let meaning: String
    }

    /// The fifty-two, in the order the lore
    /// keeps them: hearts, diamonds, clubs,
    /// spades — ace through king.
    static let all: [Card] = {
        let suits: [(String, [String])] = [
            ("Hearts", [
                "a new love — or the house itself, blessed",
                "two hearts in accord; a lucky partnership",
                "a celebration; good company, mostly honest",
                "a journey of the heart; a change of home",
                "jealousy nearby — check who smiles at the news",
                "an unexpected kindness, returned in kind",
                "a promise made lightly; hold it gently",
                "an invitation, and a gathering of friends",
                "the wish card — what you want most is near",
                "joy at home after a season of worry",
                "a fond young friend, fair and a little fickle",
                "a kind woman, and loving counsel",
                "a beloved man; affection with a soft spine"]),
            ("Diamonds", [
                "a message about money — a ring, a letter",
                "a business partnership; gossip travels with it",
                "disputes over small print; a lawyer's weather",
                "a gift or legacy; steady ground underfoot",
                "good news from a distance; an enterprise prospers",
                "an old debt resurfaces — settle it clean",
                "criticism at work; a letter that stings",
                "travel, and late news; a venture far from home",
                "restlessness — and a surprise about money",
                "money coming; a journey that pays for itself",
                "a messenger — fair, careless with details",
                "a sharp-tongued woman, clever with money",
                "a man of business, stubborn and exact"]),
            ("Clubs", [
                "wealth in reach through work; a strong beginning",
                "obstacles made of gossip — talk, nothing harder",
                "a partnership that prospers; growth in threes",
                "a lie nearby, in small things — read before signing",
                "help from a friend; a good alliance forms",
                "business grows step by step; a short journey for work",
                "success — with an argument riding on it",
                "ambition and industry; money earned, not found",
                "a stubborn streak, yours or theirs; achievement delayed",
                "fortune through work; a long journey ending well",
                "a loyal, enterprising friend, dark-haired",
                "a capable woman, business-minded and brisk",
                "a man of authority in work — his advice is sound"]),
            ("Spades", [
                "a great change — something ends so something can start",
                "a separation; a partnership divided against itself",
                "a third person in the story; interference",
                "delays and small sicknesses; rest is being demanded",
                "opposition — but you come through it standing",
                "small losses first, then slow improvement",
                "a warning in the old books: change the road",
                "trouble and temptation walking together; step carefully",
                "the ill-luck card — anxiety and delay; it passes",
                "a heavy night of worry; it lifts by morning",
                "a young schemer — or news of a conflict",
                "one who has endured much; sharp, solitary, unbought",
                "authority that must be faced, ambitious and dark"])]
        let ranks = ["Ace", "Two", "Three", "Four",
                     "Five", "Six", "Seven", "Eight",
                     "Nine", "Ten", "Jack", "Queen",
                     "King"]
        var deck: [Card] = []
        for (suit, meanings) in suits {
            for (i, meaning) in meanings.enumerated() {
                deck.append(Card(
                    name: "\(ranks[i]) of \(suit)",
                    meaning: meaning))
            }
        }
        return deck
    }()

    /// Cards still in the deck, and cards on the
    /// table — indices into `all`.
    private(set) var remaining: [Int] = []
    private(set) var table: [Int] = []
    private var seed: UInt64

    init() {
        seed = UInt64(Date().timeIntervalSince1970
            .rounded()) &+ 0x9E3779B97F4A7C15
        remaining = Array(0..<52)
        shuffle()
    }

    private func nextRandom() -> UInt64 {
        // SplitMix64 — a shuffle that answers to
        // nobody's dice cup but her own.
        seed &+= 0x9E3779B97F4A7C15
        var z = seed
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    func shuffle() {
        for i in stride(from: remaining.count - 1,
                        through: 1, by: -1) {
            let j = Int(nextRandom()
                % UInt64(i + 1))
            remaining.swapAt(i, j)
        }
    }

    /// Gather the table, rebuild the deck, and
    /// shuffle — the ceremony, when it runs low.
    @discardableResult
    func gatherAndShuffle() -> String {
        remaining = Array(0..<52)
        table = []
        shuffle()
        return L("The table is gathered and the deck made whole — fifty-two, shuffled under the table.")
    }

    /// Deal n cards. When the deck cannot cover
    /// the spread, the fallen are gathered first
    /// and the ceremony is part of the answer.
    func deal(_ n: Int) -> (cards: [Card],
                            gathered: Bool) {
        var gathered = false
        if remaining.count < n {
            gatherAndShuffle()
            gathered = true
        }
        var out: [Card] = []
        for _ in 0..<n {
            let idx = remaining.removeFirst()
            table.append(idx)
            out.append(Self.all[idx])
        }
        return (out, gathered)
    }
}

extension SkelliCenter {

    /// The cartomancy lane: the tarot deflection,
    /// the spreads, the questions put to the
    /// deck. Returns true when she has dealt or
    /// spoken for the cards.
    func cartomancyAsk(_ q: String) -> Bool {
        let deck = CartomancyDeck.shared

        // Tarot is asked about: corrected,
        // exactly once and forever, in her own
        // words — then honored with a reading if
        // a reading is what's wanted.
        if q.contains("tarot") {
            let wantsReading = q.contains("read")
                || q.contains("do ")
                || q.hasPrefix("do")
                || q.contains("tell")
                || q.contains("please")
                || q.contains("spread")
            if wantsReading {
                say(L("oh, I actually prefer cartomancy")
                    + "\n"
                    + spread(deck, count: 3,
                             topic: nil))
            } else {
                say(L("oh, I actually prefer cartomancy — fifty-two ordinary cards, no arcana. Say 'read the cards' and I'll deal."))
            }
            return true
        }

        if q.contains("shuffle")
            && (q.contains("card") || q.contains("deck")) {
            say(deck.gatherAndShuffle())
            return true
        }

        // A question put to the deck by name:
        // "ask the cards about love".
        if q.contains("ask the cards")
            || q.contains("ask the deck") {
            var topic: String? = nil
            if let range = q.range(of: "about ") {
                let tail = String(q[range.upperBound...])
                    .trimmingCharacters(
                        in: CharacterSet(
                            charactersIn: " ?.!,"))
                if !tail.isEmpty && tail.count <= 30 {
                    topic = tail
                }
            }
            say(spread(deck, count: 3, topic: topic))
            return true
        }

        if q.contains("full fortune")
            || q.contains("tell my fortune")
            || q.contains("fortune telling")
            || q.contains("fortune teller") {
            say(fullFortune(deck))
            return true
        }

        if q.contains("cartomancy")
            || q.contains("read the cards")
            || q.contains("card reading")
            || q.contains("read my fortune")
            || q.contains("three cards")
            || (q.contains("spread")
                && (q.contains("card")
                    || q.contains("reading")
                    || q.hasSuffix("spread"))) {
            say(spread(deck, count: 3, topic: nil))
            return true
        }

        if q.contains("draw a card")
            || q.contains("draw me a card")
            || q.contains("draw cards")
            || q.contains("pull a card") {
            say(spread(deck, count: 1, topic: nil))
            return true
        }

        return false
    }

    // MARK: the spreads

    private func suitWeather(_ cards:
        [CartomancyDeck.Card]) -> String {
        var hearts = 0, diamonds = 0
        var clubs = 0, spades = 0
        for card in cards {
            if card.name.hasSuffix("Hearts") {
                hearts += 1
            } else if card.name.hasSuffix("Diamonds") {
                diamonds += 1
            } else if card.name.hasSuffix("Clubs") {
                clubs += 1
            } else { spades += 1 }
        }
        let counts = [(hearts, "Hearts"),
                      (diamonds, "Diamonds"),
                      (clubs, "Clubs"),
                      (spades, "Spades")]
        let top = counts.max { $0.0 < $1.0 }!
        guard top.0 >= 2 else {
            return L("The suits sit mixed — no one weather rules the table.")
        }
        switch top.1 {
        case "Hearts":
            return L("The hearts hold the table — love's weather, and the house's.")
        case "Diamonds":
            return L("Diamonds rule the table — money moving, messages flying.")
        case "Clubs":
            return L("The clubs rule the table — work's weather; sleeves up.")
        default:
            return L("Spades rule the table — a night of warnings; walk carefully, and you'll walk through.")
        }
    }

    /// A card's name in the house tongue: the
    /// deck stores English (it is data, and the
    /// suit counts read its endings); a reading
    /// speaks the name localized, rank and suit.
    private func spokenName(
        _ card: CartomancyDeck.Card) -> String {
        let parts = card.name.components(
            separatedBy: " of ")
        guard parts.count == 2 else {
            return L(card.name)
        }
        return String(format: L("%@ of %@"),
                      L(parts[0]), L(parts[1]))
    }

    private func spread(_ deck: CartomancyDeck,
                        count: Int,
                        topic: String?) -> String {
        let (cards, gathered) = deck.deal(count)
        var lines: [String] = []
        if gathered {
            lines.append(L("The deck ran thin — the fallen are gathered and shuffled back in."))
        }
        if let topic {
            lines.append(String(format: L("The deck, on %@:"),
                                topic))
            let places = ["The heart of it",
                          "What stands against",
                          "What the road does"]
            for (i, card) in cards.enumerated() {
                lines.append(String(format: L("%@: the %@ — %@."),
                                    L(places[i]),
                                    spokenName(card),
                                    L(card.meaning)))
            }
        } else if count == 1 {
            let card = cards[0]
            lines.append(String(format: L("For you: the %@ — %@."),
                                spokenName(card),
                                L(card.meaning)))
        } else {
            lines.append(L("Three cards, face-up:"))
            let places = ["What was", "What is",
                          "What comes"]
            for (i, card) in cards.enumerated() {
                lines.append(String(format: L("%@: the %@ — %@."),
                                    L(places[i]),
                                    spokenName(card),
                                    L(card.meaning)))
            }
        }
        lines.append(suitWeather(cards))
        lines.append(deck.table.count == 1
            ? String(format: L("%lld card lies on the table; %lld remain in the deck."),
                     deck.table.count, deck.remaining.count)
            : String(format: L("%lld cards lie on the table; %lld remain in the deck."),
                     deck.table.count, deck.remaining.count))
        return lines.joined(separator: "\n")
    }

    /// The full fortune: five cards, the last of
    /// them face-down. His word turns it — the
    /// standing offer machinery, put to play.
    private func fullFortune(
        _ deck: CartomancyDeck) -> String {
        let (cards, gathered) = deck.deal(5)
        var lines: [String] = []
        if gathered {
            lines.append(L("The deck ran thin — the fallen are gathered and shuffled back in."))
        }
        lines.append(L("Your fortune, in five:"))
        let places = ["What was", "What is",
                      "What hides", "What comes"]
        for i in 0..<4 {
            lines.append(String(format: L("%@: the %@ — %@."),
                                L(places[i]),
                                spokenName(cards[i]),
                                L(cards[i].meaning)))
        }
        let crown = cards[4]
        lines.append(L("What crowns it: face-down. Say 'yes' and I'll turn it — anything else, and it stays unopened."))
        lines.append(suitWeather(cards))
        pendingAction = { [weak self] in
            guard let self else { return }
            say(String(format: L("What crowns it: the %@ — %@. There it is — the whole table, told."),
                       spokenName(crown),
                       L(crown.meaning)))
        }
        return lines.joined(separator: "\n")
    }
}
