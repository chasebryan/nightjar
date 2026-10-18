import XCTest
@testable import nightjar

/// The deterministic brain: stemming, negation and
/// ranked knowledge. These pin the routing rules —
/// the same sentence must always route the same way.
final class SkelliBrainTests: XCTestCase {

    func testStemmingFoldsInflections() {
        XCTAssertEqual(SkelliBrain.stem("sealing"), "seal")
        XCTAssertEqual(SkelliBrain.stem("sealed"), "seal")
        XCTAssertEqual(SkelliBrain.stem("seals"), "seal")
        XCTAssertEqual(SkelliBrain.stem("batteries"), "battery")
        XCTAssertEqual(SkelliBrain.stem("devices"), "device")
        XCTAssertEqual(SkelliBrain.stem("scans"), "scan")
        XCTAssertEqual(SkelliBrain.stem("stopped"), "stop")
        XCTAssertEqual(SkelliBrain.stem("classes"), "class")
    }

    func testNegationCatchesActionVerbs() {
        XCTAssertEqual(
            SkelliBrain.negatedAction("don't sweep the wire"),
            "sweep")
        XCTAssertEqual(
            SkelliBrain.negatedAction("never start serving"),
            "start")
        XCTAssertEqual(
            SkelliBrain.negatedAction("please do not scan me"),
            "scan")
    }

    func testNegationLeavesOtherSpeechAlone() {
        // "stop everything" is Vanish's sentence —
        // "everything" is no action verb.
        XCTAssertNil(SkelliBrain.negatedAction("stop everything"))
        XCTAssertNil(SkelliBrain.negatedAction("what is a sweep"))
        XCTAssertNil(SkelliBrain.negatedAction("sweep the wire"))
        XCTAssertNil(SkelliBrain.negatedAction(
            "how do I not get tracked"))
    }

    func testRankedKnowledgeFindsTheVault() {
        let all = SkelliKnowledge.entries
            + SkelliKnowledge.batches
        let hit = SkelliBrain.bestKnowledge(
            "seal this with a password", entries: all)
        XCTAssertNotNil(hit)
        let ranked = SkelliBrain.rankKnowledge(
            "how do I keep a secret safe", entries: all)
        XCTAssertFalse(ranked.isEmpty)
        XCTAssertGreaterThanOrEqual(ranked[0].score, 3)
    }

    func testLookupSecondTier() {
        // No keyword appears verbatim as the old
        // substring pass requires in this phrasing
        // order — the brain's tier still lands.
        XCTAssertNotNil(SkelliKnowledge.lookup(
            "sealing a note under a password"))
    }
}
