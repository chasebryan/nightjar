import XCTest
@testable import nightjar

/// The Drip's pure arithmetic: pulse bucketing.
/// The view only lays out what this produces.
final class DripTests: XCTestCase {

    func testEmptyPulseIsFlat() {
        let buckets = DripView.pulseBuckets(events: [], now: Date())
        XCTAssertEqual(buckets.count, 24)
        XCTAssertEqual(buckets, Array(repeating: 0, count: 24))
    }

    func testNewestEventLandsOnTheRight() {
        let now = Date()
        let event = NightEvent(
            id: UUID().uuidString,
            when: now.addingTimeInterval(-3),
            module: "test",
            kind: "note",
            text: "just now")
        let buckets = DripView.pulseBuckets(events: [event], now: now)
        // Age 3s → bucket 0, then reversed → index 23
        XCTAssertEqual(buckets[23], 1)
        XCTAssertEqual(buckets[0..<23].reduce(0, +), 0)
    }

    func testFourMinuteBoundary() {
        let now = Date()
        let inside = NightEvent(
            id: UUID().uuidString,
            when: now.addingTimeInterval(-239),
            module: "test",
            kind: "note",
            text: "inside")
        let outside = NightEvent(
            id: UUID().uuidString,
            when: now.addingTimeInterval(-240),
            module: "test",
            kind: "note",
            text: "outside")
        let buckets = DripView.pulseBuckets(events: [inside, outside], now: now)
        // 239s → bucket 23, reversed → index 0
        XCTAssertEqual(buckets[0], 1)
        XCTAssertEqual(buckets.reduce(0, +), 1)
    }

    func testMultipleEventsInSameBucket() {
        let now = Date()
        let events = (0..<5).map { i in
            NightEvent(
                id: UUID().uuidString,
                when: now.addingTimeInterval(-15 - Double(i)),
                module: "test",
                kind: "note",
                text: "same window")
        }
        let buckets = DripView.pulseBuckets(events: events, now: now)
        // Ages ~15–19s → bucket 1, reversed → index 22
        XCTAssertEqual(buckets[22], 5)
    }

    func testFutureEventsAreIgnored() {
        let now = Date()
        let future = NightEvent(
            id: UUID().uuidString,
            when: now.addingTimeInterval(10),
            module: "test",
            kind: "note",
            text: "future")
        let buckets = DripView.pulseBuckets(events: [future], now: now)
        XCTAssertEqual(buckets.reduce(0, +), 0)
    }
}
