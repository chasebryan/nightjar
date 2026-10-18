import XCTest
@testable import nightjar

/// The sanitizer's contract: a mind's scaffolding
/// never reaches the transcript — think blocks go
/// whole, a reply that is ONLY thinking is no
/// reply, and plain speech passes untouched.
final class MindSanitizerTests: XCTestCase {

    func testClosedThinkBlockIsStripped() {
        let raw = "<think>The user is greeting me. "
            + "I should be friendly.</think>"
            + "Up. Watching the wire."
        XCTAssertEqual(SkelliMindSanitizer.clean(raw),
                       "Up. Watching the wire.")
    }

    func testReasoningBeforeLoneCloseTagIsStripped() {
        // The chat template pre-fills the opening
        // tag in the prompt, so the stream can open
        // mid-thought and emit only the close.
        let raw = "Okay, the user is asking a "
            + "greeting. Let me be concise.</think>"
            + "Hey. What do you need?"
        XCTAssertEqual(SkelliMindSanitizer.clean(raw),
                       "Hey. What do you need?")
    }

    func testUnclosedThinkLeavesNoReply() {
        // The token budget died inside the thought:
        // there is no answer to salvage.
        let raw = "<think>The user asked what's up. "
            + "I need to respond in a friendly and "
            + "professional manner. Since the user"
        XCTAssertNil(SkelliMindSanitizer.clean(raw))
    }

    func testThinkOnlyReplyIsNoReply() {
        XCTAssertNil(SkelliMindSanitizer.clean(
            "<think>Just thinking.</think>"))
        XCTAssertNil(SkelliMindSanitizer.clean(""))
        XCTAssertNil(SkelliMindSanitizer.clean("  \n "))
    }

    func testWholeReplyQuotesAreUnwrapped() {
        XCTAssertEqual(
            SkelliMindSanitizer.clean(
                "\"Hey there! How's the wire?\""),
            "Hey there! How's the wire?")
    }

    func testPlainSpeechPassesUntouched() {
        let raw = "Two hosts on the wire. One's new."
        XCTAssertEqual(SkelliMindSanitizer.clean(raw), raw)
        let quoted = "She said \"hold position\" twice."
        XCTAssertEqual(SkelliMindSanitizer.clean(quoted),
                       quoted)
    }
}
