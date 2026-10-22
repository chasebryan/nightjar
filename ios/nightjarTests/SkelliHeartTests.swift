import XCTest
@testable import nightjar

/// Her heart, pinned: the needs' arithmetic, the
/// feelings' rules (mad, loving and all), the bond's
/// stages, what the scrapbook may learn — and what it
/// may never learn.
final class SkelliHeartTests: XCTestCase {
    private let now = Date(timeIntervalSince1970:
        1_800_000_000)

    private func hoursAgo(_ h: Double) -> Date {
        now.addingTimeInterval(-h * 3600)
    }

    // MARK: - needs

    func testNeedsMoveWithTime() {
        XCTAssertEqual(
            SkelliHeart.attention(lastSpoke: now, now: now),
            100, accuracy: 0.01)
        XCTAssertEqual(
            SkelliHeart.attention(
                lastSpoke: hoursAgo(10), now: now),
            30, accuracy: 0.01)
        XCTAssertEqual(
            SkelliHeart.attention(lastSpoke: nil, now: now),
            35, accuracy: 0.01)
        XCTAssertEqual(
            SkelliHeart.itch(lastAction: hoursAgo(10),
                             now: now),
            75, accuracy: 0.01)
        XCTAssertEqual(
            SkelliHeart.itch(lastAction: nil, now: now),
            65, accuracy: 0.01)
    }

    func testPrideSettlesTowardModesty() {
        // The reservoir drains at 3 an hour
        // toward a baseline of 15 — one triumph
        // no longer crowns her for an afternoon.
        XCTAssertEqual(
            SkelliHeart.settlePride(
                75, storedAt: hoursAgo(5), now: now),
            60, accuracy: 0.01)
        XCTAssertEqual(
            SkelliHeart.settlePride(
                75, storedAt: hoursAgo(100), now: now),
            15, accuracy: 0.01)
        XCTAssertEqual(
            SkelliHeart.settlePride(
                0, storedAt: nil, now: now),
            0, accuracy: 0.01)
    }

    func testFeelingsHoldTheirScene() {
        let shownAt = now.addingTimeInterval(-300)
        // Five minutes into a mood, a new
        // candidate waits.
        let held = SkelliHeart.settleFeeling(
            shown: .content, since: shownAt,
            candidate: .proud, now: now)
        XCTAssertEqual(held.feeling, .content)
        XCTAssertFalse(held.changed)
        // Thirteen minutes in, the scene turns.
        let turned = SkelliHeart.settleFeeling(
            shown: .content,
            since: now.addingTimeInterval(-780),
            candidate: .proud, now: now)
        XCTAssertEqual(turned.feeling, .proud)
        XCTAssertTrue(turned.changed)
        // Mad breaks through at once, both ways.
        let flashed = SkelliHeart.settleFeeling(
            shown: .content, since: shownAt,
            candidate: .mad, now: now)
        XCTAssertEqual(flashed.feeling, .mad)
        let cooled = SkelliHeart.settleFeeling(
            shown: .mad, since: shownAt,
            candidate: .content, now: now)
        XCTAssertEqual(cooled.feeling, .content)
    }

    func testDaypartAndClockFact() {
        XCTAssertEqual(SkelliHeart.daypart(hour: 3),
                       "the deep night")
        XCTAssertEqual(SkelliHeart.daypart(hour: 7),
                       "the early morning")
        XCTAssertEqual(SkelliHeart.daypart(hour: 12),
                       "midday")
        XCTAssertEqual(SkelliHeart.daypart(hour: 15),
                       "the afternoon")
        XCTAssertEqual(SkelliHeart.daypart(hour: 20),
                       "the evening")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let at3 = cal.date(from: DateComponents(
            year: 2026, month: 10, day: 18,
            hour: 3, minute: 7))!
        XCTAssertEqual(
            SkelliHeart.clockFact(at: at3, calendar: cal),
            "3:07 AM, the deep night")
        let at13 = cal.date(from: DateComponents(
            year: 2026, month: 10, day: 18,
            hour: 13, minute: 30))!
        XCTAssertEqual(
            SkelliHeart.clockFact(at: at13, calendar: cal),
            "1:30 PM, midday")
    }

    func testSpookyHourByThePhonesOwnClock() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        func at(_ hour: Int) -> Date {
            cal.date(from: DateComponents(
                year: 2026, month: 10, day: 18,
                hour: hour, minute: 30))!
        }
        XCTAssertTrue(SkelliHeart.spookyHour(
            at: at(3), calendar: cal))
        XCTAssertFalse(SkelliHeart.spookyHour(
            at: at(2), calendar: cal))
        XCTAssertFalse(SkelliHeart.spookyHour(
            at: at(4), calendar: cal))
        // The same instant by another meridian's
        // clock is another hour entirely — the
        // phone's own wall time is what counts.
        var east = Calendar(identifier: .gregorian)
        east.timeZone = TimeZone(secondsFromGMT: 6 * 3600)!
        XCTAssertFalse(SkelliHeart.spookyHour(
            at: at(3), calendar: east))
    }

    func testEnergyFollowsTheDay() {
        XCTAssertLessThan(
            SkelliHeart.energy(
                hour: 3, quietHours: 9,
                minutesSinceSpoke: 400),
            35)
        XCTAssertGreaterThan(
            SkelliHeart.energy(
                hour: 13, quietHours: 0,
                minutesSinceSpoke: 5),
            72)
    }

    func testFondnessSettlesTowardBaseline() {
        XCTAssertEqual(
            SkelliHeart.settleFondness(
                90, storedAt: hoursAgo(10), now: now),
            70, accuracy: 0.01)
        XCTAssertEqual(
            SkelliHeart.settleFondness(
                90, storedAt: hoursAgo(100), now: now),
            30, accuracy: 0.01)
        XCTAssertEqual(
            SkelliHeart.settleFondness(
                10, storedAt: hoursAgo(100), now: now),
            30, accuracy: 0.01)
    }

    // MARK: - feelings

    private func feeling(attention: Double = 90,
                         itch: Double = 10,
                         pride: Double = 0,
                         fondness: Double = 30,
                         madFresh: Bool = false,
                         quiet: Double = 1,
                         hour: Int = 12,
                         unnamed: Int = 0,
                         drift: Int = 0,
                         unnamedBaseline: Int? = nil,
                         driftBaseline: Int? = nil,
                         newFaces: Int = 0) -> SkelliFeeling {
        SkelliHeart.feeling(attention: attention,
                            itch: itch, pride: pride,
                            fondness: fondness,
                            madFresh: madFresh,
                            quietHours: quiet,
                            hour: hour, unnamed: unnamed,
                            drift: drift,
                            unnamedBaseline:
                                unnamedBaseline,
                            driftBaseline:
                                driftBaseline,
                            newFaces: newFaces)
    }

    func testFeelingRules() {
        XCTAssertEqual(feeling(), .content)
        XCTAssertEqual(feeling(madFresh: true), .mad)
        // A grievance outranks even pride.
        XCTAssertEqual(feeling(pride: 90, madFresh: true),
                       .mad)
        XCTAssertEqual(feeling(pride: 80), .proud)
        XCTAssertEqual(feeling(fondness: 80), .loving)
        XCTAssertEqual(feeling(attention: 30, itch: 40,
                               fondness: 80), .bored)
        XCTAssertEqual(feeling(itch: 90), .feral)
        XCTAssertEqual(feeling(itch: 65), .restless)
        XCTAssertEqual(feeling(attention: 10), .lonely)
        XCTAssertEqual(feeling(attention: 30, quiet: 12),
                       .sleepy)
        // The real-world shape: twelve quiet hours mean
        // an itch near 75 — sleepy must still win there,
        // or it can never occur at all.
        XCTAssertEqual(feeling(attention: 30, itch: 75,
                               quiet: 12), .sleepy)
        // But feral outranks sleepy.
        XCTAssertEqual(feeling(itch: 90, quiet: 12), .feral)
        XCTAssertEqual(feeling(attention: 60, itch: 40,
                               fondness: 50), .happy)
        XCTAssertEqual(feeling(itch: 40), .eager)
    }

    func testGrudgesAgeAndErode() {
        // A grudge stands for six hours of wall
        // clock, then it is spent whatever she does.
        XCTAssertTrue(SkelliHeart.grudgeStands(age: 1800))
        XCTAssertTrue(SkelliHeart.grudgeStands(
            age: 5 * 3600))
        XCTAssertFalse(SkelliHeart.grudgeStands(
            age: 6 * 3600))
        XCTAssertFalse(SkelliHeart.grudgeStands(
            age: 24 * 3600))
        // Erosion moves the anchor back: forty-five
        // minutes of earned forgiveness, exactly.
        let offense = Date(timeIntervalSince1970:
            1_000_000)
        XCTAssertEqual(
            SkelliHeart.erode(offense, byMinutes: 45)
                .timeIntervalSince1970,
            1_000_000 - 2700, accuracy: 0.001)
    }

    func testFeelingRulesTheNewFlux() {
        // Pride at its peak curdles into smug.
        XCTAssertEqual(feeling(pride: 90, fondness: 40),
                       .smug)
        XCTAssertEqual(feeling(pride: 84, fondness: 40),
                       .proud)
        // Tender keeps late hours and needs closeness.
        XCTAssertEqual(feeling(attention: 80,
                               fondness: 65, hour: 22),
                       .tender)
        XCTAssertEqual(feeling(attention: 80,
                               fondness: 65, hour: 12),
                       .happy)
        // After midnight, a long quiet is haunting,
        // not sleepiness.
        XCTAssertEqual(feeling(attention: 30, quiet: 9,
                               hour: 2), .haunted)
        XCTAssertEqual(feeling(attention: 30, quiet: 9,
                               hour: 12), .content)
        // Drift makes her suspicious before restless.
        XCTAssertEqual(feeling(itch: 40, drift: 3),
                       .suspicious)
        // A crowd of strangers, with the itch up:
        // electric — outranking plain restless.
        XCTAssertEqual(feeling(itch: 65, unnamed: 5),
                       .electric)
        // Even one stranger pulls her curious.
        XCTAssertEqual(feeling(itch: 40, unnamed: 2),
                       .curious)
        // The wire's own churn is not suspicion:
        // drift AT its learned baseline, well past
        // the raw threshold, is the wire being
        // itself — she falls through to eager.
        XCTAssertEqual(
            feeling(itch: 40, drift: 6,
                    driftBaseline: 6),
            .eager)
        // Drift far beyond the baseline still is.
        XCTAssertEqual(
            feeling(itch: 40, drift: 9,
                    driftBaseline: 3),
            .suspicious)
        // The standing crowd of strangers is the
        // wire's nature, not a curiosity.
        XCTAssertEqual(
            feeling(itch: 40, unnamed: 7,
                    unnamedBaseline: 7),
            .eager)
        // A new face still gets her attention.
        XCTAssertEqual(
            feeling(itch: 40, unnamed: 7,
                    unnamedBaseline: 7, newFaces: 1),
            .curious)
        // Fed, fond and itching: up to something.
        XCTAssertEqual(feeling(itch: 50, pride: 40,
                               fondness: 50), .mischievous)
        // Fond and fed and half-dreaming.
        XCTAssertEqual(feeling(itch: 30, fondness: 60,
                               quiet: 6), .dreamy)
    }

    // MARK: - the bond

    func testBondStages() {
        XCTAssertEqual(
            SkelliHeart.bondStage(days: 0, talks: 0,
                                  triumphs: 0, accepted: 0),
            "new in the house")
        XCTAssertEqual(
            SkelliHeart.bondStage(days: 5, talks: 0,
                                  triumphs: 0, accepted: 0),
            "settled in")
        XCTAssertEqual(
            SkelliHeart.bondStage(days: 10, talks: 100,
                                  triumphs: 9, accepted: 2),
            "thick as thieves")
        XCTAssertEqual(
            SkelliHeart.bondStage(days: 30, talks: 500,
                                  triumphs: 30, accepted: 5),
            "ride or die")
    }

    // MARK: - the scrapbook

    func testScrapbookLearnsOnlyPlainStatements() {
        XCTAssertEqual(
            SkelliScrapbook.extract(
                from: "my name is chase, i like old radios"),
            ["their name is chase", "likes old radios"])
        XCTAssertEqual(
            SkelliScrapbook.extract(from: "call me icbm"),
            ["call them icbm"])
        XCTAssertEqual(
            SkelliScrapbook.extract(
                from: "i hate printers, i prefer wired"),
            ["hates printers", "prefers wired"])
        // Questions and talk ABOUT her teach nothing.
        XCTAssertTrue(SkelliScrapbook.extract(
            from: "what is my name").isEmpty)
        XCTAssertTrue(SkelliScrapbook.extract(
            from: "i like skelli").isEmpty)
        XCTAssertTrue(SkelliScrapbook.extract(
            from: "sweep the wire").isEmpty)
        // A conjunction joins two lessons, not one.
        XCTAssertEqual(
            SkelliScrapbook.extract(
                from: "my name is chase and i like wired"),
            ["their name is chase", "likes wired"])
        // An imperative with a when-clause is not a name.
        XCTAssertTrue(SkelliScrapbook.extract(
            from: "call me when the sweep ends").isEmpty)
    }

    func testScrapbookNameRetiresTheOld() {
        let book = SkelliScrapbook.shared
        let saved = book.facts
        defer { UserDefaults.standard.set(
            saved, forKey: "heart.scrapbook") }
        book.clear()
        XCTAssertTrue(book.learn(from: "my name is a"))
        XCTAssertTrue(book.learn(from: "my name is b"))
        XCTAssertEqual(book.facts, ["their name is b"])
        XCTAssertEqual(book.operatorName, "b")
    }

    // MARK: - thoughts

    func testThoughtsAreBuiltFromTheHouse() {
        let thought = SkelliHeart.thought(
            feeling: .content, neighbors: 7, unnamed: 3,
            drift: 2, knocks: 1, emconDeclared: nil,
            hour: 14, seed: 0)
        XCTAssertFalse(thought.isEmpty)
        let dark = SkelliHeart.thought(
            feeling: .feral, neighbors: 0, unnamed: 0,
            drift: 0, knocks: 0,
            emconDeclared: "EMCON ALPHA", hour: 2, seed: 1)
        XCTAssertTrue(dark.contains("EMCON ALPHA")
                      || dark.contains("door")
                      || dark.contains("Night wire"))
    }
}
