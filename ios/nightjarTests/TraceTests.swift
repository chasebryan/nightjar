import XCTest
@testable import nightjar

/// The Network Trace's small sharp pieces: rule parsing,
/// endpoint extraction, and the reply analyzer's service
/// hints. The engine itself needs a network; these don't.
final class TraceTests: XCTestCase {

    // MARK: Rules

    func testFollowupRuleParses() {
        let rules = TraceRule.parse(
            "contains Redis => followup Redis PING (RESP)")
        XCTAssertEqual(rules.count, 1)
        guard case .followup(let name)? = rules.first?.action
        else { return XCTFail("expected a followup rule") }
        XCTAssertEqual(name, "Redis PING (RESP)")
    }

    func testTagAndStopRulesParse() {
        let rules = TraceRule.parse("""
            contains nginx => tag web
            contains login => stop
            """)
        XCTAssertEqual(rules.count, 2)
        guard case .tag(let label) = rules[0].action
        else { return XCTFail("expected a tag rule") }
        XCTAssertEqual(label, "web")
        guard case .stop = rules[1].action
        else { return XCTFail("expected a stop rule") }
    }

    func testPortRuleParsesAndMatches() {
        let rules = TraceRule.parse("port 6379 => tag redis")
        XCTAssertEqual(rules.count, 1)
        XCTAssertTrue(rules[0].matches(text: "anything", port: 6379))
        XCTAssertFalse(rules[0].matches(text: "anything", port: 22))
    }

    func testCommentsBlanksAndGarbageAreIgnored() {
        let rules = TraceRule.parse("""
            # a comment

            contains ssh => tag shell
            this line is not a rule
            contains => followup
            port 99999 => tag nope
            """)
        XCTAssertEqual(rules.count, 1)
    }

    func testContainsMatchingIsCaseInsensitive() {
        let rules = TraceRule.parse("contains OpenSSH => tag shell")
        XCTAssertEqual(rules.count, 1)
        XCTAssertTrue(rules[0].matches(
            text: "SSH-2.0-openssh_9.3", port: 22))
        XCTAssertFalse(rules[0].matches(
            text: "SSH-2.0-dropbear", port: 22))
    }

    // MARK: Reference extraction

    func testExtractsIPv4WithPort() {
        let refs = TraceAnalyzer.references(
            in: "moved to 192.168.2.15:8080 for now")
        XCTAssertEqual(refs, [TraceReference(
            host: "192.168.2.15", port: 8080,
            source: "192.168.2.15:8080")])
    }

    func testExtractsURLs() {
        let refs = TraceAnalyzer.references(
            in: "see http://192.168.2.20:8080/x and "
              + "https://example.com/path")
        XCTAssertTrue(refs.contains(TraceReference(
            host: "192.168.2.20", port: 8080,
            source: "http://192.168.2.20:8080/x")))
        XCTAssertTrue(refs.contains(TraceReference(
            host: "example.com", port: nil,
            source: "https://example.com/path")))
        // The URL's IP is not double-counted by the bare pass.
        XCTAssertEqual(refs.count, 2)
    }

    func testRejectsInvalidAddresses() {
        let refs = TraceAnalyzer.references(
            in: "version 999.1.1.1 and 10.0.0.256 are not hosts, "
              + "but 10.0.0.9 is")
        XCTAssertEqual(refs.map { $0.host }, ["10.0.0.9"])
    }

    // MARK: Analyzer

    func testHTTPHintsAndNotes() {
        let data = Data(("HTTP/1.1 200 OK\r\n"
            + "Server: nginx/1.24.0\r\n"
            + "Content-Type: text/html\r\n\r\n"
            + "<html><head><title>Router</title></head></html>")
            .utf8)
        let analysis = TraceAnalyzer.analyze(
            data: data, host: "192.168.2.1", port: 80)
        XCTAssertEqual(analysis.serviceHint, "HTTP")
        XCTAssertTrue(analysis.firstLine.hasPrefix("HTTP/1.1 200"))
        XCTAssertTrue(analysis.notes.contains("Server: nginx/1.24.0"))
        XCTAssertTrue(analysis.notes.contains("Title: Router"))
        XCTAssertEqual(analysis.signature.count, 64)
    }

    func testSSHHint() {
        let analysis = TraceAnalyzer.analyze(
            data: Data("SSH-2.0-OpenSSH_9.3\r\n".utf8),
            host: "192.168.2.5", port: 22)
        XCTAssertEqual(analysis.serviceHint, "SSH")
        XCTAssertEqual(analysis.firstLine, "SSH-2.0-OpenSSH_9.3")
    }

    func testRedisHints() {
        let pong = TraceAnalyzer.analyze(
            data: Data("+PONG\r\n".utf8),
            host: "192.168.2.5", port: 6379)
        XCTAssertEqual(pong.serviceHint, "Redis")
        let noauth = TraceAnalyzer.analyze(
            data: Data("-NOAUTH Authentication required.\r\n".utf8),
            host: "192.168.2.5", port: 6379)
        XCTAssertEqual(noauth.serviceHint, "Redis")
    }

    func testSignatureIsStable() {
        let data = Data("hello".utf8)
        let a = TraceAnalyzer.analyze(data: data, host: "h", port: 1)
        let b = TraceAnalyzer.analyze(data: data, host: "h", port: 1)
        XCTAssertEqual(a.signature, b.signature)
        let c = TraceAnalyzer.analyze(
            data: Data("hello!".utf8), host: "h", port: 1)
        XCTAssertNotEqual(a.signature, c.signature)
    }
}
