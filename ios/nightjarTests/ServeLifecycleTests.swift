import UserNotifications
import XCTest
@testable import nightjar

final class ServeLifecycleTests: XCTestCase {
    @MainActor
    private func drainPublications() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    /// Exercise the real service lifecycle. Disable radio restoration and
    /// announcements, and restore every shared setting/delegate afterwards.
    @MainActor
    private func withMouth(
        _ body: @MainActor (Mouth) async throws -> Void
    ) async rethrows {
        let defaults = UserDefaults.standard
        let keys = ["gattArm.on", "flare.on", "stealthMode",
                    "emcon.condition", "emconActive"]
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        let originalMouth = Mouth.shared
        let notifications = UNUserNotificationCenter.current()
        let originalDelegate = notifications.delegate
        defaults.set(false, forKey: "gattArm.on")
        defaults.set(false, forKey: "flare.on")
        defaults.set(true, forKey: "stealthMode")
        EmconCondition.store(.open)
        let mouth = Mouth()
        defer {
            mouth.stopServe()
            Mouth.shared = originalMouth
            notifications.delegate = originalDelegate
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        try await body(mouth)
        await drainPublications()
    }

    @MainActor
    private func start(_ mouth: Mouth) throws -> Int {
        // No discovery or outbound traffic. Each test uses an unlisted
        // listener; the lifecycle, not a remote peer, is under test.
        try XCTUnwrap(mouth.startServe(
            tcpPort: Int.random(in: 49152...65535),
            udpPort: nil, httpPort: nil, reply: "ack", framing: "raw"))
    }

    @MainActor
    func testOldAutomaticStopCannotStopAManuallyStartedReplacement() async throws {
        try await withMouth { mouth in
            let original = try start(mouth)
            await drainPublications()
            XCTAssertTrue(mouth.serveRunning)
            mouth.stopServe()
            let replacement = try start(mouth)
            await drainPublications()

            XCTAssertFalse(mouth.stopServe(ifGeneration: original))
            await drainPublications()
            XCTAssertTrue(mouth.serveRunning)
            XCTAssertTrue(mouth.stopServe(ifGeneration: replacement))
            await drainPublications()
            XCTAssertFalse(mouth.serveRunning)
        }
    }

    @MainActor
    func testStopBeforeStartPublicationCannotResurrectServe() async throws {
        try await withMouth { mouth in
            let generation = try start(mouth)
            XCTAssertTrue(mouth.stopServe(ifGeneration: generation))
            await drainPublications()
            XCTAssertFalse(mouth.serveRunning)
            XCTAssertFalse(mouth.stopServe(ifGeneration: generation))
        }
    }

    @MainActor
    func testRapidRestartKeepsOnlyTheLatestRunningState() async throws {
        try await withMouth { mouth in
            let original = try start(mouth)
            mouth.stopServe()
            _ = try start(mouth)
            XCTAssertFalse(mouth.stopServe(ifGeneration: original))
            await drainPublications()
            XCTAssertTrue(mouth.serveRunning)
        }
    }

    @MainActor
    func testNoListenerDoesNotIssueAShutdownToken() async {
        await withMouth { mouth in
            XCTAssertNil(mouth.startServe(
                tcpPort: nil, udpPort: nil, httpPort: nil,
                reply: "ack", framing: "raw"))
            await drainPublications()
            XCTAssertFalse(mouth.serveRunning)
            XCTAssertNotNil(mouth.serveError)
        }
    }

    @MainActor
    func testEmconRefusalDoesNotIssueAShutdownToken() async {
        await withMouth { mouth in
            EmconCondition.store(.bravo)
            XCTAssertNil(mouth.startServe(
                tcpPort: 9000, udpPort: nil, httpPort: nil,
                reply: "ack", framing: "raw"))
            await drainPublications()
            XCTAssertFalse(mouth.serveRunning)
            XCTAssertNotNil(mouth.serveError)
        }
    }
}
