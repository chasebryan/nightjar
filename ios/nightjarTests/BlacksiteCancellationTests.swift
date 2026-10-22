import XCTest
@testable import nightjar

final class BlacksiteCancellationTests: XCTestCase {
    func testJobStoppedWhileQueuedCannotRunItsScript() {
        let name = UUID().uuidString
        let script = "/tmp/cancel-\(name).js"
        let marker = "/tmp/cancel-\(name).txt"
        XCTAssertTrue(BlacksiteFS.writeText(
            script, text: "write('\(marker)', 'should not run');"))
        defer {
            try? FileManager.default.removeItem(at: BlacksiteFS.url(forVirtual: script))
            try? FileManager.default.removeItem(at: BlacksiteFS.url(forVirtual: marker))
        }

        let stop = KernelKillSwitch()
        stop.fire()
        let finished = expectation(description: "queued job stopped")
        finished.assertForOverFulfill = true
        let engine = BlacksiteJS()
        engine.runFile(script, args: [], killSwitch: stop) { error in
            XCTAssertEqual(error, "stopped")
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
        XCTAssertFalse(BlacksiteFS.exists(marker))
        withExtendedLifetime(engine) {}
    }

    func testUncancelledJobStillExecutesAndCompletes() {
        let name = UUID().uuidString
        let script = "/tmp/normal-\(name).js"
        let marker = "/tmp/normal-\(name).txt"
        XCTAssertTrue(BlacksiteFS.writeText(
            script, text: "write('\(marker)', 'done');"))
        defer {
            try? FileManager.default.removeItem(at: BlacksiteFS.url(forVirtual: script))
            try? FileManager.default.removeItem(at: BlacksiteFS.url(forVirtual: marker))
        }

        let stop = KernelKillSwitch()
        let finished = expectation(description: "normal job finished")
        finished.assertForOverFulfill = true
        let engine = BlacksiteJS()
        engine.runFile(script, args: [], killSwitch: stop) { error in
            XCTAssertNil(error)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(BlacksiteFS.readText(marker), "done")
        XCTAssertFalse(stop.isFired)
        withExtendedLifetime(engine) {}
    }
}
