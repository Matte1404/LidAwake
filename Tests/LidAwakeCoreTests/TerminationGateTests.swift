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
}
