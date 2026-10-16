import XCTest
@testable import nightjar

final class UpdateCheckerTests: XCTestCase {
    func testVersionComponents() {
        XCTAssertEqual(UpdateChecker.components("v2.1.0"), [2, 1, 0])
        XCTAssertEqual(UpdateChecker.components("2.0"), [2, 0])
        XCTAssertEqual(UpdateChecker.components("2.1.0-rc1"), [2, 1, 0])
        XCTAssertEqual(UpdateChecker.components("v1.2+build7"), [1, 2])
    }

    func testIsNewer() {
        XCTAssertTrue(UpdateChecker.isNewer("v2.1.0", than: "2.0"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0.1", than: "2.0"))
        XCTAssertTrue(UpdateChecker.isNewer("v3.0", than: "2.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("2.0", than: "2.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.9", than: "2.0"))
        XCTAssertFalse(UpdateChecker.isNewer("v2.0", than: "2.0"))
    }

    func testMalformedVersionComponentsAreRejected() {
        XCTAssertEqual(UpdateChecker.components(""), [])
        XCTAssertEqual(UpdateChecker.components("v"), [])
        XCTAssertEqual(UpdateChecker.components("3.oops"), [])
        XCTAssertEqual(UpdateChecker.components("3..0"), [])
        XCTAssertEqual(UpdateChecker.components("3."), [])
        XCTAssertEqual(UpdateChecker.components("3.0/other"), [])
        XCTAssertEqual(UpdateChecker.components("999999999999999999999999999999"), [])
        XCTAssertEqual(UpdateChecker.components("  v3.1.0\n"), [3, 1, 0])
    }

    func testMalformedVersionsNeverTriggerAnUpdate() {
        XCTAssertFalse(UpdateChecker.isNewer("3.oops", than: "2.6"))
        XCTAssertFalse(UpdateChecker.isNewer("v", than: "2.6"))
        XCTAssertFalse(UpdateChecker.isNewer("999999999999999999999999999999", than: "2.6"))
        XCTAssertFalse(UpdateChecker.isNewer("2.7", than: "2.invalid"))
        XCTAssertTrue(UpdateChecker.isNewer("3.0", than: "2.6"))
    }

    func testParseRejectsMalformedReleaseTag() {
        let json = """
        {"tag_name": "v3.bad", "html_url":
        "https://github.com/chasebryan/nightjar-hack/releases/tag/v3.bad",
        "draft": false, "prerelease": false}
        """.data(using: .utf8)!
        XCTAssertNil(UpdateChecker.parse(json, current: "2.6"))
    }

    func testParseNewerRelease() {
        let json = """
        {"tag_name": "v2.1.0", "name": "nightjar 2.1", "html_url": \
        "https://github.com/chasebryan/nightjar/releases/tag/v2.1.0", \
        "body": "Fusion.", "draft": false, "prerelease": false}
        """.data(using: .utf8)!
        let release = UpdateChecker.parse(json, current: "2.0")
        XCTAssertEqual(release?.tag, "v2.1.0")
        XCTAssertEqual(release?.name, "nightjar 2.1")
        XCTAssertEqual(release?.url.absoluteString,
                       "https://github.com/chasebryan/nightjar/releases/tag/v2.1.0")
    }

    func testParseIgnoresOlderDraftsAndPrereleases() {
        func body(tag: String, draft: Bool = false, pre: Bool = false) -> Data {
            """
            {"tag_name": "\(tag)", "name": "", "html_url": \
            "https://github.com/chasebryan/nightjar/releases/tag/\(tag)", \
            "draft": \(draft), "prerelease": \(pre)}
            """.data(using: .utf8)!
        }
        XCTAssertNil(UpdateChecker.parse(body(tag: "v1.9"), current: "2.0"))
        XCTAssertNil(UpdateChecker.parse(body(tag: "v2.0"), current: "2.0"))
        XCTAssertNil(UpdateChecker.parse(body(tag: "v2.1", draft: true), current: "2.0"))
        XCTAssertNil(UpdateChecker.parse(body(tag: "v2.1", pre: true), current: "2.0"))
        // A newer release with no explicit name falls back to the tag.
        XCTAssertEqual(UpdateChecker.parse(body(tag: "v2.1"), current: "2.0")?.name, "v2.1")
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(UpdateChecker.parse(Data("not json".utf8), current: "2.0"))
        XCTAssertNil(UpdateChecker.parse(Data("{}".utf8), current: "2.0"))
    }
}
