import XCTest
@testable import LidAwakeCore

final class TerminationGateTests: XCTestCase {
    func testQuitDuringUninstallWaitsForItsOutcomeThenRuns() {
        var gate = TerminationGate()
        XCTAssertTrue(gate.beginUninstall())
        XCTAssertEqual(gate.requestQuit(), .afterUninstall)
        // Not terminating yet, so the uninstall's completion is still delivered and acted on.
        XCTAssertFalse(gate.terminating)
        XCTAssertEqual(gate.requestQuit(), .afterUninstall)
        XCTAssertTrue(gate.endUninstall())
        XCTAssertTrue(gate.terminating)
        XCTAssertEqual(gate.requestQuit(), .alreadyTerminating)
    }

    func testUninstallWithoutQuitRequestEndsWithoutQuitting() {
        var gate = TerminationGate()
        XCTAssertTrue(gate.beginUninstall())
        XCTAssertFalse(gate.beginUninstall())
        XCTAssertFalse(gate.endUninstall())
        XCTAssertFalse(gate.terminating)
        XCTAssertEqual(gate.requestQuit(), .start)
    }

    func testUninstallCannotStartOnceQuitHasStartedAndStayOpenAllowsIt() {
        var gate = TerminationGate()
        XCTAssertEqual(gate.requestQuit(), .start)
        XCTAssertEqual(gate.requestQuit(), .alreadyTerminating)
        XCTAssertFalse(gate.beginUninstall())
        gate.cancelQuit()
        XCTAssertTrue(gate.beginUninstall())
    }

    func testMenuActionsStayLockedFromUninstallStartUntilItsOutcome() {
        var gate = TerminationGate()
        XCTAssertFalse(gate.locksMenuActions)
        XCTAssertTrue(gate.beginUninstall())
        XCTAssertTrue(gate.locksMenuActions)
        XCTAssertEqual(gate.requestQuit(), .afterUninstall)
        XCTAssertTrue(gate.locksMenuActions)
        XCTAssertTrue(gate.endUninstall())
        XCTAssertTrue(gate.locksMenuActions)  // quit now runs
        gate.cancelQuit()
        XCTAssertFalse(gate.locksMenuActions)

        var plain = TerminationGate()
        XCTAssertTrue(plain.beginUninstall())
        XCTAssertFalse(plain.endUninstall())
        XCTAssertFalse(plain.locksMenuActions)
    }

    func testQuitAfterSuccessfulUninstallTerminatesWithoutRestore() {
        var gate = TerminationGate()
        XCTAssertTrue(gate.beginUninstall())
        XCTAssertFalse(gate.endUninstall(succeeded: true))  // no quit was requested meanwhile
        // The uninstall already restored sleep; a restore round-trip here would deadlock the
        // main queue (its reply is delivered by a main-queue block the caller is still inside).
        XCTAssertEqual(gate.requestQuit(), .terminateNow)
        XCTAssertTrue(gate.terminating)
        XCTAssertEqual(gate.requestQuit(), .alreadyTerminating)
    }

    func testQuitDeferredDuringSuccessfulUninstallStillRepliesAfterIt() {
        var gate = TerminationGate()
        XCTAssertTrue(gate.beginUninstall())
        XCTAssertEqual(gate.requestQuit(), .afterUninstall)
        XCTAssertTrue(gate.endUninstall(succeeded: true))
        XCTAssertEqual(gate.requestQuit(), .alreadyTerminating)
    }

    func testQuitStillRestoresSleepUnlessAnUninstallSucceeded() {
        var plain = TerminationGate()
        XCTAssertEqual(plain.requestQuit(), .start)

        var failed = TerminationGate()
        XCTAssertTrue(failed.beginUninstall())
        XCTAssertFalse(failed.endUninstall())  // failed or canceled uninstall
        XCTAssertEqual(failed.requestQuit(), .start)

        var failedThenStayOpen = TerminationGate()
        XCTAssertTrue(failedThenStayOpen.beginUninstall())
        XCTAssertFalse(failedThenStayOpen.endUninstall())
        XCTAssertTrue(failedThenStayOpen.beginUninstall())
        XCTAssertFalse(failedThenStayOpen.endUninstall())
        XCTAssertEqual(failedThenStayOpen.requestQuit(), .start)
    }
}
