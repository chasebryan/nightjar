import XCTest
@testable import nightjar

/// Her ear for tone: how a thing was typed is part
/// of what it said.
final class ToneReadTests: XCTestCase {

    func testShouts() {
        XCTAssertTrue(SkelliCenter.readsAsShout(
            "WHY IS THE SWEEP NOT RUNNING"))
        XCTAssertTrue(SkelliCenter.readsAsShout(
            "I SAID STOP EVERYTHING NOW"))
        XCTAssertTrue(SkelliCenter.readsAsShout(
            "WHAT DO YOU MEAN IT FAILED"))
    }

    func testNotShouts() {
        XCTAssertFalse(SkelliCenter.readsAsShout(
            "why is the sweep not running"))
        XCTAssertFalse(SkelliCenter.readsAsShout(
            "What is the MAC address of the AP"))
        XCTAssertFalse(SkelliCenter.readsAsShout("OK"))
        XCTAssertFalse(SkelliCenter.readsAsShout(
            "Run the Sweep please"))
        XCTAssertFalse(SkelliCenter.readsAsShout(""))
    }
}
