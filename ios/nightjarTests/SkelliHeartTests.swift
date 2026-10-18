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
        XCTAssertEqual(
            SkelliHeart.pride(
                lastTriumph: hoursAgo(5), now: now),
            40, accuracy: 0.01)
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
                         quiet: Double = 1) -> SkelliFeeling {
        SkelliHeart.feeling(attention: attention,
                            itch: itch, pride: pride,
                            fondness: fondness,
                            madFresh: madFresh,
                            quietHours: quiet)
    }

    func testFeelingRules() {
        XCTAssertEqual(feeling(), .content)
        XCTAssertEqual(feeling(madFresh: true), .mad)
        // A grievance outranks even pride.
        XCTAssertEqual(feeling(pride: 90, madFresh: true),
                       .mad)
        XCTAssertEqual(feeling(pride: 80), .proud)
        XCTAssertEqual(feeling(fondness: 80), .loving)
        XCTAssertEqual(feeling(fondness: 80, attention: 30,
                               itch: 40), .bored)
        XCTAssertEqual(feeling(itch: 90), .feral)
        XCTAssertEqual(feeling(itch: 65), .restless)
        XCTAssertEqual(feeling(attention: 10), .lonely)
        XCTAssertEqual(feeling(attention: 30, quiet: 12),
                       .sleepy)
        XCTAssertEqual(feeling(attention: 60, itch: 40,
                               fondness: 50), .happy)
        XCTAssertEqual(feeling(itch: 40), .eager)
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
