import Foundation
import XCTest
@testable import nightjar

/// These tests also run against the production kernel alone with
/// tools/test-kernel.sh; no app, radio, model download, or Metal is needed.
final class KernelLifecycleTests: XCTestCase {
    private final class Counter {
        private let lock = NSLock()
        private var count = 0

        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }

    func testStopBeforeRunnerInstallsItsHookIsRemembered() {
        let stop = KernelKillSwitch()
        let calls = Counter()
        stop.fire()
        stop.install { calls.increment() }
        XCTAssertTrue(stop.isFired)
        XCTAssertEqual(calls.value, 1)
    }

    func testRepeatedStopInvokesAnInstalledHookOnlyOnce() {
        let stop = KernelKillSwitch()
        let calls = Counter()
        stop.install { calls.increment() }
        stop.fire()
        stop.fire()
        XCTAssertEqual(calls.value, 1)
    }

    func testHookCanInspectAndDetachItselfWithoutDeadlocking() {
        let stop = KernelKillSwitch()
        var observedStop = false
        stop.install {
            observedStop = stop.isFired
            stop.removeHandler()
        }
        stop.fire()
        XCTAssertTrue(observedStop)
    }

    func testInstallingAfterStopAlsoCallsOutsideTheLock() {
        let stop = KernelKillSwitch()
        stop.fire()
        var observedStop = false
        stop.install {
            observedStop = stop.isFired
            stop.removeHandler()
        }
        XCTAssertTrue(observedStop)
    }

    func testConcurrentInstallAndStopCannotLoseOrDuplicateCancellation() {
        for _ in 0..<200 {
            let stop = KernelKillSwitch()
            let calls = Counter()
            DispatchQueue.concurrentPerform(iterations: 2) { index in
                if index == 0 {
                    stop.install { calls.increment() }
                } else {
                    stop.fire()
                    stop.fire()
                }
            }
            XCTAssertEqual(calls.value, 1)
        }
    }

    func testFinishedRunnerCanReleaseItsCapturedContext() {
        final class Context {}
        let stop = KernelKillSwitch()
        weak var released: Context?
        do {
            let context = Context()
            released = context
            stop.install { withExtendedLifetime(context) {} }
        }
        XCTAssertNotNil(released)
        stop.removeHandler()
        XCTAssertNil(released)
        XCTAssertFalse(stop.isFired)
    }

    func testRemovingAHandlerDoesNotUndoCancellation() {
        let stop = KernelKillSwitch()
        stop.fire()
        stop.removeHandler()
        let calls = Counter()
        stop.install { calls.increment() }
        XCTAssertTrue(stop.isFired)
        XCTAssertEqual(calls.value, 1)
    }

    func testKilledProcessStaysKilledWhenItsQueuedRunnerFinishes() throws {
        let kernel = BlacksiteKernel()
        let process = try XCTUnwrap(kernel.admit(
            name: "queued.js", kind: .javascript,
            parent: 0, background: true).proc)
        let ended = expectation(description: "one terminal notification")
        ended.assertForOverFulfill = true
        kernel.onProcessEnd = { _ in ended.fulfill() }

        kernel.kill(process, reason: "operator stop")
        let calls = Counter()
        process.killSwitch.install { calls.increment() }
        kernel.finish(process, note: "late completion")
        kernel.kill(process, reason: "repeated stop")

        wait(for: [ended], timeout: 2)
        XCTAssertEqual(process.state, .killed)
        XCTAssertEqual(process.exitNote, "operator stop")
        XCTAssertTrue(process.cancel.isCancelled)
        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(kernel.liveCount, 0)
        XCTAssertFalse(kernel.accountOutput(process))
    }

    func testNormalCompletionRemainsDoneWhenStoppedLater() throws {
        let kernel = BlacksiteKernel()
        let process = try XCTUnwrap(kernel.admit(
            name: "finished.js", kind: .javascript,
            parent: 0, background: false).proc)
        kernel.finish(process, note: "done")
        kernel.kill(process, reason: "too late")
        XCTAssertEqual(process.state, .done)
        XCTAssertFalse(process.cancel.isCancelled)
        XCTAssertFalse(process.killSwitch.isFired)
        XCTAssertEqual(kernel.liveCount, 0)
    }
}
