import Foundation

/// Her almanac: dates, the calendar, and the
/// year's named days — understood, not looked
/// up. Fixed feasts keep their dates; the
/// moving Western feasts follow their rules
/// (Thanksgiving counts Thursdays, Easter
/// follows the old computus); the lunar year —
/// Hebrew, Islamic, Chinese, Hindu — rides a
/// table carried through 2030, spoken of as
/// "around" where moon-sighting decides. She
/// also keeps the operator's birthday, but
/// only when she is explicitly told it, and
/// the house's book of hours: work she has
/// been given for a date and a time.

enum Almanac {

    static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        return c
    }

    static func makeDate(_ year: Int, _ month: Int,
                         _ day: Int,
                         _ hour: Int = 0,
                         _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute)) ?? Date()
    }

    /// The nth weekday of a month (weekday:
    /// 1 = Sunday … 7 = Saturday); negative n
    /// counts back from the month's end.
    static func nthWeekday(year: Int, month: Int,
                           weekday: Int, _ n: Int)
        -> Date {
        if n > 0 {
            let first = makeDate(year, month, 1)
            let firstWeekday = cal.component(
                .weekday, from: first)
            let delta = (weekday - firstWeekday + 7) % 7
            return makeDate(year, month, 1 + delta
                            + (n - 1) * 7)
        }
        let nextMonth = month == 12
            ? makeDate(year + 1, 1, 1)
            : makeDate(year, month + 1, 1)
        let lastDay = cal.date(byAdding: .day,
                               value: -1,
                               to: nextMonth)!
        let lastWeekday = cal.component(.weekday,
                                        from: lastDay)
        let delta = (lastWeekday - weekday + 7) % 7
        let last = cal.date(byAdding: .day,
                            value: -delta, to: lastDay)!
        return cal.date(byAdding: .day,
                        value: (n + 1) * 7, to: last)!
    }

    /// Easter Sunday by the Gregorian computus.
    static func easter(_ year: Int) -> Date {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return makeDate(year, month, day)
    }

    // MARK: the named days

    enum DayRule {
        case fixed(Int, Int)              // month, day
        case nth(Int, Int, Int)           // month, weekday, n
        case easterOffset(Int)
        case thanksgivingPlus(Int)
        case table([Int: (Int, Int)], approx: Bool)
    }

    struct NamedDay {
        let name: String
        let keys: [String]
        let rule: DayRule
    }

    static let namedDays: [NamedDay] = [
        NamedDay(name: "New Year's Day",
                 keys: ["new year's day", "new year"],
                 rule: .fixed(1, 1)),
        NamedDay(name: "Martin Luther King Jr. Day",
                 keys: ["martin luther king", "mlk"],
                 rule: .nth(1, 2, 3)),
        NamedDay(name: "Groundhog Day",
                 keys: ["groundhog"],
                 rule: .fixed(2, 2)),
        NamedDay(name: "Valentine's Day",
                 keys: ["valentine"],
                 rule: .fixed(2, 14)),
        NamedDay(name: "Presidents' Day",
                 keys: ["presidents' day", "presidents day",
                        "washington's birthday"],
                 rule: .nth(2, 2, 3)),
        NamedDay(name: "Mardi Gras",
                 keys: ["mardi gras", "fat tuesday"],
                 rule: .easterOffset(-47)),
        NamedDay(name: "Ash Wednesday",
                 keys: ["ash wednesday"],
                 rule: .easterOffset(-46)),
        NamedDay(name: "St. Patrick's Day",
                 keys: ["st. patrick", "st patrick",
                        "saint patrick"],
                 rule: .fixed(3, 17)),
        NamedDay(name: "the spring equinox",
                 keys: ["spring equinox", "vernal equinox"],
                 rule: .table([:], approx: true)),
        NamedDay(name: "April Fools' Day",
                 keys: ["april fools", "april fool"],
                 rule: .fixed(4, 1)),
        NamedDay(name: "Good Friday",
                 keys: ["good friday"],
                 rule: .easterOffset(-2)),
        NamedDay(name: "Easter",
                 keys: ["easter"],
                 rule: .easterOffset(0)),
        NamedDay(name: "Earth Day",
                 keys: ["earth day"],
                 rule: .fixed(4, 22)),
        NamedDay(name: "Cinco de Mayo",
                 keys: ["cinco de mayo"],
                 rule: .fixed(5, 5)),
        NamedDay(name: "Mother's Day",
                 keys: ["mother's day", "mothers day",
                        "mother’s day"],
                 rule: .nth(5, 1, 2)),
        NamedDay(name: "Memorial Day",
                 keys: ["memorial day"],
                 rule: .nth(5, 2, -1)),
        NamedDay(name: "Juneteenth",
                 keys: ["juneteenth"],
                 rule: .fixed(6, 19)),
        NamedDay(name: "Father's Day",
                 keys: ["father's day", "fathers day",
                        "father’s day"],
                 rule: .nth(6, 1, 3)),
        NamedDay(name: "the summer solstice",
                 keys: ["summer solstice"],
                 rule: .table([:], approx: true)),
        NamedDay(name: "Independence Day",
                 keys: ["independence day", "fourth of july",
                        "4th of july", "july 4th"],
                 rule: .fixed(7, 4)),
        NamedDay(name: "Labor Day",
                 keys: ["labor day", "labour day"],
                 rule: .nth(9, 2, 1)),
        NamedDay(name: "Columbus Day",
                 keys: ["columbus day",
                        "indigenous peoples"],
                 rule: .nth(10, 2, 2)),
        NamedDay(name: "Halloween",
                 keys: ["halloween"],
                 rule: .fixed(10, 31)),
        NamedDay(name: "Veterans Day",
                 keys: ["veterans day", "veteran's day"],
                 rule: .fixed(11, 11)),
        NamedDay(name: "Thanksgiving",
                 keys: ["thanksgiving"],
                 rule: .nth(11, 5, 4)),
        NamedDay(name: "Black Friday",
                 keys: ["black friday"],
                 rule: .thanksgivingPlus(1)),
        NamedDay(name: "the winter solstice",
                 keys: ["winter solstice"],
                 rule: .table([:], approx: true)),
        NamedDay(name: "Christmas Eve",
                 keys: ["christmas eve"],
                 rule: .fixed(12, 24)),
        NamedDay(name: "Christmas",
                 keys: ["christmas"],
                 rule: .fixed(12, 25)),
        NamedDay(name: "Boxing Day",
                 keys: ["boxing day"],
                 rule: .fixed(12, 26)),
        NamedDay(name: "New Year's Eve",
                 keys: ["new year's eve"],
                 rule: .fixed(12, 31)),
        NamedDay(name: "daylight saving time begins",
                 keys: ["daylight saving begins",
                        "daylight savings begins",
                        "spring forward",
                        "clocks go forward"],
                 rule: .nth(3, 1, 2)),
        NamedDay(name: "daylight saving time ends",
                 keys: ["daylight saving ends",
                        "daylight savings ends",
                        "fall back", "clocks go back"],
                 rule: .nth(11, 1, 1)),
        // The lunar year, carried in a table
        // through 2030: (month, day) of the
        // first day, by year.
        NamedDay(name: "Chinese New Year",
                 keys: ["chinese new year", "lunar new year"],
                 rule: .table([
                    2025: (1, 29), 2026: (2, 17),
                    2027: (2, 6), 2028: (1, 26),
                    2029: (2, 13), 2030: (2, 3)],
                    approx: false)),
        NamedDay(name: "Ramadan",
                 keys: ["ramadan"],
                 rule: .table([
                    2025: (3, 1), 2026: (2, 18),
                    2027: (2, 8), 2028: (1, 28),
                    2029: (1, 17), 2030: (1, 6)],
                    approx: true)),
        NamedDay(name: "Passover",
                 keys: ["passover", "pesach"],
                 rule: .table([
                    2025: (4, 13), 2026: (4, 2),
                    2027: (4, 22), 2028: (4, 11),
                    2029: (4, 1), 2030: (4, 18)],
                    approx: false)),
        NamedDay(name: "Eid al-Fitr",
                 keys: ["eid al-fitr", "eid al fitr",
                        "eid"],
                 rule: .table([
                    2025: (3, 30), 2026: (3, 20),
                    2027: (3, 10), 2028: (2, 28),
                    2029: (2, 15), 2030: (2, 4)],
                    approx: true)),
        NamedDay(name: "Eid al-Adha",
                 keys: ["eid al-adha", "eid al adha"],
                 rule: .table([
                    2025: (6, 7), 2026: (5, 27),
                    2027: (5, 17), 2028: (5, 5),
                    2029: (4, 25), 2030: (4, 14)],
                    approx: true)),
        NamedDay(name: "Rosh Hashanah",
                 keys: ["rosh hashanah"],
                 rule: .table([
                    2025: (9, 23), 2026: (9, 12),
                    2027: (10, 2), 2028: (9, 21),
                    2029: (9, 10), 2030: (9, 28)],
                    approx: false)),
        NamedDay(name: "Yom Kippur",
                 keys: ["yom kippur"],
                 rule: .table([
                    2025: (10, 2), 2026: (9, 21),
                    2027: (10, 11), 2028: (9, 30),
                    2029: (9, 19), 2030: (10, 7)],
                    approx: false)),
        NamedDay(name: "Diwali",
                 keys: ["diwali", "deepavali"],
                 rule: .table([
                    2025: (10, 20), 2026: (11, 8),
                    2027: (10, 28), 2028: (10, 16),
                    2029: (11, 5), 2030: (10, 25)],
                    approx: true)),
        NamedDay(name: "Hanukkah",
                 keys: ["hanukkah", "chanukah"],
                 rule: .table([
                    2025: (12, 15), 2026: (12, 5),
                    2027: (12, 25), 2028: (12, 13),
                    2029: (12, 2), 2030: (12, 21)],
                    approx: false)),
    ]

    /// The seasons ride fixed approximations;
    /// the table entries above with empty
    /// tables are resolved here.
    static func resolve(_ day: NamedDay, year: Int)
        -> (date: Date, approx: Bool)? {
        switch day.rule {
        case .fixed(let m, let d):
            return (makeDate(year, m, d), false)
        case .nth(let m, let w, let n):
            return (nthWeekday(year: year, month: m,
                               weekday: w, n), false)
        case .easterOffset(let off):
            return (cal.date(byAdding: .day, value: off,
                             to: easter(year))!, false)
        case .thanksgivingPlus(let off):
            let t = nthWeekday(year: year, month: 11,
                               weekday: 5, 4)
            return (cal.date(byAdding: .day, value: off,
                             to: t)!, false)
        case .table(let table, let approx):
            if day.name.contains("equinox")
                || day.name.contains("solstice") {
                // The turning points of the year,
                // to the day astronomy gives.
                if day.name.contains("spring") {
                    return (makeDate(year, 3, 20), true)
                }
                if day.name.contains("summer") {
                    return (makeDate(year, 6, 21), true)
                }
                if day.name.contains("winter") {
                    return (makeDate(year, 12, 21), true)
                }
                return (makeDate(year, 9, 22), true)
            }
            guard let (m, d) = table[year]
            else { return nil }
            return (makeDate(year, m, d), approx)
        }
    }

    /// The next occurrence of a named day, on
    /// or after the start of today.
    static func next(_ day: NamedDay,
                     from: Date = Date())
        -> (date: Date, approx: Bool)? {
        let year = cal.component(.year, from: from)
        let today = cal.startOfDay(for: from)
        for y in [year, year + 1] {
            if let hit = resolve(day, year: y),
               hit.date >= today {
                return hit
            }
        }
        return nil
    }

    static func matchNamedDay(in q: String)
        -> NamedDay? {
        // Longest key wins, so Christmas Eve is
        // not swallowed by Christmas.
        var best: NamedDay? = nil
        var bestLen = 0
        for day in namedDays {
            for key in day.keys where q.contains(key) {
                if key.count > bestLen {
                    best = day
                    bestLen = key.count
                }
            }
        }
        return best
    }

    static func nextHoliday(from: Date = Date())
        -> (day: NamedDay, date: Date,
            approx: Bool)? {
        var best: (NamedDay, Date, Bool)? = nil
        for day in namedDays {
            if let hit = next(day, from: from),
               best == nil || hit.date < best!.1 {
                best = (day, hit.date, hit.approx)
            }
        }
        return best
    }

    static func holidayToday(_ date: Date = Date())
        -> NamedDay? {
        let today = cal.startOfDay(for: date)
        let year = cal.component(.year, from: date)
        for day in namedDays {
            if let hit = resolve(day, year: year),
               cal.startOfDay(for: hit.date) == today {
                return day
            }
        }
        return nil
    }

    // MARK: phrasing

    static func spell(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f.string(from: date)
    }

    static func spellShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
    }

    /// Date arithmetic for any date, not only
    /// her named days: "how many days until
    /// march 3", "how long since june 5",
    /// "what day is december 25", "what date
    /// is it in 30 days". Exact calendar math,
    /// answered with the date spelled in full.
    /// Nil when the ask carries no readable
    /// date or no date question.
    // MARK: the moon — computed, never looked up

    /// The synodic month, and the new moon it is
    /// counted from: 6 January 2000, 18:14 UTC.
    private static let synodic = 29.53058867

    static func moonAge(at date: Date) -> Double {
        let jd = date.timeIntervalSince1970 / 86400
            + 2440587.5
        let raw = (jd - 2451550.1)
            .truncatingRemainder(dividingBy: synodic)
        return raw >= 0 ? raw : raw + synodic
    }

    static func moonPhase(at date: Date)
        -> (name: String, illumination: Int) {
        let age = moonAge(at: date)
        let illum = Int(((1 - cos(2 * Double.pi * age
            / synodic)) / 2 * 100).rounded())
        let names = ["New moon", "Waxing crescent",
                     "First quarter", "Waxing gibbous",
                     "Full moon", "Waning gibbous",
                     "Last quarter", "Waning crescent"]
        let idx = Int((age / synodic * 8)
            .rounded()) % 8
        return (names[idx], illum)
    }

    /// The next date the moon stands full (age at
    /// least half the cycle), counted from a date.
    static func nextFullMoon(after date: Date) -> Date {
        var wait = synodic / 2 - moonAge(at: date)
        if wait <= 0 { wait += synodic }
        return date.addingTimeInterval(wait * 86400)
    }

    static func nextNewMoon(after date: Date) -> Date {
        var wait = synodic - moonAge(at: date)
        if wait <= 0 { wait += synodic }
        return date.addingTimeInterval(wait * 86400)
    }

    /// The traditional names of the full moons,
    /// by the month they fall in.
    static func fullMoonName(month: Int) -> String {
        let names = ["Wolf Moon", "Snow Moon",
                     "Worm Moon", "Pink Moon",
                     "Flower Moon", "Strawberry Moon",
                     "Buck Moon", "Sturgeon Moon",
                     "Harvest Moon", "Hunter's Moon",
                     "Beaver Moon", "Cold Moon"]
        return names[max(0, min(11, month - 1))]
    }

    // MARK: the zodiac — the old wheel, kept as lore

    /// (name, first month/day, last month/day,
    /// her one line on the sign). Capricorn wraps
    /// the year: its start is in December.
    static let zodiacTable: [(name: String,
                              start: (Int, Int),
                              end: (Int, Int),
                              trait: String)] = [
        ("Aries", (3, 21), (4, 19),
         "Bold first steps, and a short fuse for boredom."),
        ("Taurus", (4, 20), (5, 20),
         "Patient, rooted, and immovable once decided."),
        ("Gemini", (5, 21), (6, 20),
         "Two minds, both quick; conversation is its weather."),
        ("Cancer", (6, 21), (7, 22),
         "A shell built around a whole ocean of feeling."),
        ("Leo", (7, 23), (8, 22),
         "Warm, theatrical, and loyal to its pride."),
        ("Virgo", (8, 23), (9, 22),
         "Precision as a love language; it notices everything."),
        ("Libra", (9, 23), (10, 22),
         "It weighs everything twice and charms the scales."),
        ("Scorpio", (10, 23), (11, 21),
         "Still water, deep currents; nothing is casual."),
        ("Sagittarius", (11, 22), (12, 21),
         "Aimed at the horizon; honesty without a silencer."),
        ("Capricorn", (12, 22), (1, 19),
         "It climbs — slowly, entirely, without witnesses."),
        ("Aquarius", (1, 20), (2, 18),
         "From the future, visiting; allergic to ordinary."),
        ("Pisces", (2, 19), (3, 20),
         "Half in this world, half in a beautiful one of its own.")]

    static func zodiac(month: Int, day: Int)
        -> (name: String, trait: String, cusp: Bool) {
        for row in zodiacTable {
            let (sm, sd) = row.start
            let (em, ed) = row.end
            let md = month * 100 + day
            let inside = sm <= em
                ? (md >= sm * 100 + sd
                   && md <= em * 100 + ed)
                : (md >= sm * 100 + sd
                   || md <= em * 100 + ed)
            if inside {
                let nearStart = month == sm
                    && abs(day - sd) <= 1
                let nearEnd = month == em
                    && abs(day - ed) <= 1
                return (row.name, row.trait,
                        nearStart || nearEnd)
            }
        }
        return ("Aries", zodiacTable[0].trait, false)
    }

    static func zodiacNamed(_ name: String)
        -> (range: String, trait: String)? {
        for row in zodiacTable
        where row.name.lowercased() == name {
            let months = ["January", "February",
                          "March", "April", "May",
                          "June", "July", "August",
                          "September", "October",
                          "November", "December"]
            let range = "\(months[row.start.0 - 1]) "
                + "\(row.start.1) – "
                + "\(months[row.end.0 - 1]) "
                + "\(row.end.1)"
            return (range, row.trait)
        }
        return nil
    }

    static func dateMath(_ q: String) -> String? {
        let today = cal.startOfDay(for: Date())
        func dayDiff(_ target: Date) -> Int {
            cal.dateComponents(
                [.day], from: today,
                to: cal.startOfDay(for: target)).day
                ?? 0
        }
        func countPhrase(_ days: Int) -> String {
            if days == 0 { return L("That is today.") }
            if days > 0 {
                return days == 1
                    ? L("1 day from today.")
                    : String(format: L("%lld days from today."), days)
            }
            return days == -1
                ? L("1 day ago.")
                : String(format: L("%lld days ago."), -days)
        }
        // "in 30 days" / "30 days from now" /
        // "30 days ago": a count and a direction.
        if q.contains("days") {
            let tokens = q.split(separator: " ")
            for (i, token) in tokens.enumerated() {
                guard let n = Int(token),
                      i + 1 < tokens.count,
                      tokens[i + 1].hasPrefix("day")
                else { continue }
                let ago = q.contains("ago")
                guard ago || q.hasPrefix("in ")
                        || q.contains("from now")
                        || q.contains("what date")
                        || q.contains("what day")
                else { continue }
                let target = cal.date(
                    byAdding: .day,
                    value: ago ? -n : n,
                    to: today)!
                return spell(target) + " — "
                    + countPhrase(dayDiff(target))
            }
        }
        // A month date, read by the same parser
        // that reads a told birthday.
        guard let told = parseToldBirthday(q)
        else { return nil }
        let questiony = q.contains("how many days")
            || q.contains("how long")
            || q.contains("what day")
            || q.contains("what date")
            || q.contains("when")
            || q.contains("until")
            || q.contains("since")
        guard questiony else { return nil }
        let thisYear = cal.component(.year,
                                     from: Date())
        func occurrence(_ year: Int) -> Date? {
            makeDate(year, told.month, told.day)
        }
        if q.contains("since"), told.year == nil {
            var target = occurrence(thisYear)!
            if dayDiff(target) > 0 {
                target = occurrence(thisYear - 1)!
            }
            return spell(target) + " — "
                + countPhrase(dayDiff(target))
        }
        if let year = told.year {
            guard let target = occurrence(year)
            else { return nil }
            return spell(target) + " — "
                + countPhrase(dayDiff(target))
        }
        var target = occurrence(thisYear)!
        if dayDiff(target) < 0 {
            target = occurrence(thisYear + 1)!
        }
        return spell(target) + " — "
            + countPhrase(dayDiff(target))
    }

    /// "today" / "tomorrow" / "in 68 days" /
    /// "3 days ago", for a date against now.
    static func whenPhrase(_ date: Date,
                           from: Date = Date()) -> String {
        let days = cal.dateComponents(
            [.day], from: cal.startOfDay(for: from),
            to: cal.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return L("today")
        case 1: return L("tomorrow")
        case -1: return L("yesterday")
        case 2...Int.max:
            return String(format: L("in %lld days"),
                          days)
        default:
            return String(format: L("%lld days ago"),
                          -days)
        }
    }

    /// The operator's birthday, kept only when
    /// it was explicitly told to her: a month
    /// and day, and the year when one was given.
    static var birthday: (month: Int, day: Int,
                          year: Int?)? {
        get {
            guard let raw = UserDefaults.standard
                .string(forKey: "skelli.birthday")
            else { return nil }
            let parts = raw.split(separator: "-")
                .compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return (parts[1], parts[2],
                    parts[0] == 0 ? nil : parts[0])
        }
        set {
            if let b = newValue {
                UserDefaults.standard.set(
                    "\(b.year ?? 0)-\(b.month)-\(b.day)",
                    forKey: "skelli.birthday")
            } else {
                UserDefaults.standard.removeObject(
                    forKey: "skelli.birthday")
            }
        }
    }

    /// "June 5" — a month and a day, spelled
    /// without a year.
    static func spellMonthDay(_ month: Int,
                              _ day: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f.string(from: makeDate(2001, month,
                                       day))
    }

    /// Read a birthday out of a telling: a
    /// month named, a day numbered, and a year
    /// when one is spoken. Nil when no date
    /// can honestly be read.
    static func parseToldBirthday(_ q: String)
        -> (month: Int, day: Int, year: Int?)? {
        for (name, number) in SkelliSchedule.monthNames {
            guard let r = q.range(of: name)
            else { continue }
            let digits = "0123456789"
            let tail = q[r.upperBound...]
            let dayDigits = tail.drop(while: {
                    !digits.contains($0) })
                .prefix(while: { digits.contains($0) })
            let head = q[..<r.lowerBound]
            let dayHead = head.reversed().prefix(
                while: { digits.contains($0) })
            guard let day = Int(dayDigits)
                    ?? Int(String(dayHead.reversed())),
                  (1...31).contains(day)
            else { continue }
            var year: Int? = nil
            if let yRegex = try? NSRegularExpression(
                pattern: "\\b(19|20)\\d{2}\\b"),
               let ym = yRegex.firstMatch(
                in: q, range: NSRange(q.startIndex...,
                                       in: q)),
               let yr = Range(ym.range, in: q) {
                year = Int(q[yr])
            }
            return (number, day, year)
        }
        // Numeric: 6/5, 6/5/1999, 6-5-1999.
        if let regex = try? NSRegularExpression(
            pattern: "(\\d{1,2})[/-](\\d{1,2})"
                + "(?:[/-](\\d{4}))?"),
           let m = regex.firstMatch(
            in: q, range: NSRange(q.startIndex...,
                                   in: q)),
           let mR = Range(m.range(at: 1), in: q),
           let dR = Range(m.range(at: 2), in: q),
           let month = Int(q[mR]),
           let day = Int(q[dR]),
           (1...12).contains(month),
           (1...31).contains(day) {
            var year: Int? = nil
            if m.range(at: 3).location != NSNotFound,
               let yR = Range(m.range(at: 3), in: q) {
                year = Int(q[yR])
            }
            return (month, day, year)
        }
        return nil
    }

    static func nextBirthday(from: Date = Date())
        -> Date? {
        guard let b = birthday else { return nil }
        let year = cal.component(.year, from: from)
        let today = cal.startOfDay(for: from)
        for y in [year, year + 1] {
            let date = makeDate(y, b.month, b.day)
            if date >= today { return date }
        }
        return nil
    }

    static func birthdayToday(_ date: Date = Date())
        -> Bool {
        guard let b = birthday else { return false }
        let year = cal.component(.year, from: date)
        return cal.startOfDay(for: makeDate(year,
                                            b.month,
                                            b.day))
            == cal.startOfDay(for: date)
    }

    /// A stable key for a day, for once-a-day
    /// marks.
    static func todayKey(_ date: Date = Date())
        -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// MARK: - The book of hours

struct ScheduledItem: Codable, Identifiable {
    var id: String
    var when: Date
    var what: String
    var reminder: Bool
    var created: Date
}

/// Work she has been given for a date and a
/// time — persisted on the device, fired
/// through her own ask path when the hour
/// comes, so every gate the work answers to
/// in person still stands at the hour.
final class SkelliSchedule {
    static let shared = SkelliSchedule()

    private(set) var items: [ScheduledItem] = []

    init() { load() }

    private func load() {
        if let data = UserDefaults.standard.data(
            forKey: "skelli.schedule"),
           let decoded = try? JSONDecoder().decode(
            [ScheduledItem].self, from: data) {
            items = decoded.sorted { $0.when < $1.when }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data,
                forKey: "skelli.schedule")
        }
    }

    func add(when: Date, what: String, reminder: Bool) {
        items.append(ScheduledItem(
            id: UUID().uuidString, when: when,
            what: what, reminder: reminder,
            created: Date()))
        items.sort { $0.when < $1.when }
        persist()
    }

    func cancelAll() {
        items = []
        persist()
    }

    /// Everything whose hour has come, lifted
    /// out of the book.
    func takeDue(now: Date = Date()) -> [ScheduledItem] {
        let due = items.filter { $0.when <= now }
        if !due.isEmpty {
            items.removeAll { $0.when <= now }
            persist()
        }
        return due
    }

    // MARK: parsing an hour out of an ask

    static let monthNames: [(String, Int)] = [
        ("january", 1), ("february", 2), ("march", 3),
        ("april", 4), ("may", 5), ("june", 6),
        ("july", 7), ("august", 8), ("september", 9),
        ("october", 10), ("november", 11),
        ("december", 12), ("jan", 1), ("feb", 2),
        ("mar", 3), ("apr", 4), ("jun", 6), ("jul", 7),
        ("aug", 8), ("sep", 9), ("sept", 9),
        ("oct", 10), ("nov", 11), ("dec", 12),
    ]

    static let weekdayNames: [(String, Int)] = [
        ("sunday", 1), ("monday", 2), ("tuesday", 3),
        ("wednesday", 4), ("thursday", 5),
        ("friday", 6), ("saturday", 7),
    ]

    /// An hour of the day out of words like
    /// "9", "9pm", "9:30", "21:00", "noon",
    /// "midnight" — nil when no hour is spoken.
    static func parseHour(_ text: String)
        -> (hour: Int, minute: Int)? {
        if text.contains("midnight") {
            return (0, 0)
        }
        if text.contains("noon") { return (12, 0) }
        let pattern = "(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?"
        guard let regex = try? NSRegularExpression(
                pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex...,
                               in: text)),
              let hr = Range(match.range(at: 1),
                             in: text),
              var hour = Int(text[hr])
        else { return nil }
        var minute = 0
        if match.range(at: 2).location != NSNotFound,
           let mr = Range(match.range(at: 2), in: text) {
            minute = Int(text[mr]) ?? 0
        }
        if match.range(at: 3).location != NSNotFound,
           let ar = Range(match.range(at: 3), in: text) {
            let ap = text[ar]
            if ap == "pm", hour < 12 { hour += 12 }
            if ap == "am", hour == 12 { hour = 0 }
        }
        guard (0...23).contains(hour),
              (0...59).contains(minute)
        else { return nil }
        return (hour, minute)
    }

    /// Read an ask for appointed work: a when
    /// and a what. Nil when no when is spoken —
    /// the ask is then ordinary, for now.
    static func parse(_ q: String)
        -> (when: Date, what: String,
            reminder: Bool)? {
        let cal = Almanac.cal
        let now = Date()
        let today = cal.startOfDay(for: now)
        var day: Date? = nil
        var rest = q

        // "in 20 minutes", "in 2 hours",
        // "in 3 days".
        if let regex = try? NSRegularExpression(
            pattern: "in (\\d+) (minute|minutes|hour|hours|day|days)"),
           let match = regex.firstMatch(
            in: q, range: NSRange(q.startIndex...,
                                   in: q)),
           let nr = Range(match.range(at: 1), in: q),
           let ur = Range(match.range(at: 2), in: q),
           let n = Int(q[nr]) {
            let unit = q[ur]
            let seconds: TimeInterval =
                unit.hasPrefix("minute") ? Double(n) * 60
                : unit.hasPrefix("hour") ? Double(n) * 3600
                : Double(n) * 86400
            let when = now.addingTimeInterval(seconds)
            var what = q
            if let full = Range(match.range, in: q) {
                what.removeSubrange(full)
            }
            return finish(when: when, what: what, q: q)
        }

        if rest.contains("tomorrow") {
            day = cal.date(byAdding: .day, value: 1,
                           to: today)
            rest = rest.replacingOccurrences(
                of: "tomorrow", with: " ")
        } else if rest.contains("tonight") {
            day = today
            rest = rest.replacingOccurrences(
                of: "tonight", with: " at 20:00 ")
        }
        // A named date: "october 31", "31 october".
        if day == nil {
            for (name, number) in monthNames {
                guard let r = rest.range(of: name)
                else { continue }
                let tail = rest[r.upperBound...]
                let head = rest[..<r.lowerBound]
                let digits = "0123456789"
                let dayTail = tail.drop(while: {
                    !digits.contains($0) })
                let num = dayTail.prefix(while: {
                    digits.contains($0) })
                let dayHead = head.reversed().prefix(
                    while: { digits.contains($0) })
                let dayNum = Int(num)
                    ?? Int(String(dayHead.reversed()))
                if let dayNum, (1...31).contains(dayNum) {
                    let year = cal.component(.year,
                                             from: now)
                    var candidate = Almanac.makeDate(
                        year, number, dayNum)
                    if candidate < today {
                        candidate = Almanac.makeDate(
                            year + 1, number, dayNum)
                    }
                    day = candidate
                    rest = rest.replacingOccurrences(
                        of: name, with: " ")
                        .replacingOccurrences(
                            of: String(dayNum), with: " ")
                    break
                }
            }
        }
        // A weekday: "on friday", "friday".
        if day == nil {
            for (name, weekday) in weekdayNames
            where rest.contains(name) {
                let current = cal.component(
                    .weekday, from: now)
                var delta = (weekday - current + 7) % 7
                if delta == 0 { delta = 7 }
                day = cal.date(byAdding: .day,
                               value: delta, to: today)
                rest = rest.replacingOccurrences(
                    of: name, with: " ")
                break
            }
        }
        // The operator's own birthday as a day.
        if day == nil, rest.contains("my birthday"),
           let next = Almanac.nextBirthday() {
            day = cal.startOfDay(for: next)
            rest = rest.replacingOccurrences(
                of: "my birthday", with: " ")
        }
        // A named day of the year as a day.
        if day == nil,
           let named = Almanac.matchNamedDay(in: rest),
           let hit = Almanac.next(named) {
            day = cal.startOfDay(for: hit.date)
            for key in named.keys where rest.contains(key) {
                rest = rest.replacingOccurrences(
                    of: key, with: " ")
                break
            }
        }

        // The hour: spoken after "at", or the
        // day carries its default. An address
        // after "at" is not an hour — "knock at
        // 10.0.0.1" appoints nothing.
        var hourMinute: (Int, Int)? = nil
        if let atRange = rest.range(of: " at ") {
            let tail = String(rest[atRange.upperBound...])
            let firstToken = tail.split(separator: " ")
                .first.map(String.init) ?? ""
            if !firstToken.contains(".") {
                hourMinute = parseHour(tail)
            }
            if hourMinute != nil {
                rest = String(rest[..<atRange.lowerBound])
            }
        }
        if day == nil, hourMinute != nil {
            // An hour alone is for today, or for
            // tomorrow when today's has passed.
            day = today
        }
        guard var day else { return nil }
        if let (h, m) = hourMinute {
            day = cal.date(bySettingHour: h, minute: m,
                           second: 0, of: day) ?? day
            if hourMinute != nil,
               day <= now, q.contains(" at ") {
                // "at 9" when 9 has gone: the next 9.
                if cal.isDateInToday(day) {
                    day = cal.date(byAdding: .day,
                                   value: 1, to: day) ?? day
                }
            }
        } else if day == today, !q.contains("tonight") {
            return nil
        }
        return finish(when: day, what: rest, q: q)
    }

    private static func finish(when: Date, what: String,
                               q: String)
        -> (when: Date, what: String, reminder: Bool)? {
        // Work token by token, so honest words
        // that merely contain the filler ("that",
        // "button") are never mangled.
        let reminder = q.contains("remind me")
        var tokens = what.split(separator: " ")
            .map(String.init)
            .filter { $0 != "at" && $0 != "on"
                      && $0 != "please" }
        while let first = tokens.first,
              ["remind", "me", "to", "remember",
               "schedule"].contains(first) {
            tokens.removeFirst()
        }
        let text = tokens.joined(separator: " ")
        // An appointed what is an order or a
        // note, never a question: a question
        // wearing a time is still a question.
        let questions: Set<String> = ["what",
            "what's", "whats", "who",
            "when", "where", "why", "how", "is",
            "are", "do", "does", "can", "could",
            "would", "tell", "don't", "dont",
            "never"]
        guard text.count >= 2,
              let first = tokens.first,
              !questions.contains(first)
        else { return nil }
        return (when, text, reminder)
    }

    /// The hour a kept item names, for her
    /// confirmation and her lists.
    static func spellWhen(_ date: Date) -> String {
        let day = DateFormatter()
        day.dateStyle = .medium
        day.timeStyle = .none
        let clock = DateFormatter()
        clock.dateStyle = .none
        clock.timeStyle = .short
        let when = Almanac.whenPhrase(date)
        return "\(when) — \(day.string(from: date)) at "
            + clock.string(from: date)
    }
}
