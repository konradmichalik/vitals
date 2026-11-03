import XCTest
@testable import VitalsApp

final class ActionOutcomeTests: XCTestCase {
    private let action = SuggestedAction(action: "poweroff", target: nil, label: "Stop DDEV", estimate: nil)
    private let finish = Date(timeIntervalSince1970: 1_000)

    private func checking() -> ActionOutcome {
        ActionOutcome.reduce(
            ActionOutcome.reduce(.idle, .started(action)),
            .finished(.success("ok"), at: finish)
        )
    }

    private func failed() -> ActionOutcome {
        ActionOutcome.reduce(
            ActionOutcome.reduce(.idle, .started(action)),
            .finished(.failure(.nonZeroExit("boom\n")), at: finish)
        )
    }

    func testSuccessMovesRunningToChecking() {
        XCTAssertEqual(checking(), .checking(action, since: finish))
    }

    func testFailureMovesRunningToFailedWithMessageAndTime() {
        XCTAssertEqual(failed(), .failed(action, message: "boom", at: finish))
    }

    func testReportAfterFinishClearsChecking() {
        let state = ActionOutcome.reduce(checking(), .reportArrived(timestamp: finish.addingTimeInterval(1)))
        XCTAssertEqual(state, .idle)
    }

    func testReportFromBeforeFinishKeepsChecking() {
        let state = ActionOutcome.reduce(checking(), .reportArrived(timestamp: finish.addingTimeInterval(-1)))
        XCTAssertEqual(state, .checking(action, since: finish))
    }

    func testCheckingClearsAfter60SecondsWithoutReport() {
        let early = ActionOutcome.reduce(checking(), .tick(now: finish.addingTimeInterval(59)))
        XCTAssertEqual(early, .checking(action, since: finish))
        let late = ActionOutcome.reduce(checking(), .tick(now: finish.addingTimeInterval(60)))
        XCTAssertEqual(late, .idle)
    }

    func testFailedClearsAfter60Seconds() {
        let early = ActionOutcome.reduce(failed(), .tick(now: finish.addingTimeInterval(59)))
        XCTAssertEqual(early, .failed(action, message: "boom", at: finish))
        let late = ActionOutcome.reduce(failed(), .tick(now: finish.addingTimeInterval(60)))
        XCTAssertEqual(late, .idle)
    }

    func testReportDoesNotHideAFailure() {
        let state = ActionOutcome.reduce(failed(), .reportArrived(timestamp: finish.addingTimeInterval(1)))
        XCTAssertEqual(state, .failed(action, message: "boom", at: finish))
    }

    func testStartedWhileFailedOrCheckingMovesToRunning() {
        XCTAssertEqual(ActionOutcome.reduce(failed(), .started(action)), .running(action))
        XCTAssertEqual(ActionOutcome.reduce(checking(), .started(action)), .running(action))
    }

    func testIdleIgnoresReportAndTick() {
        XCTAssertEqual(ActionOutcome.reduce(.idle, .reportArrived(timestamp: finish)), .idle)
        XCTAssertEqual(ActionOutcome.reduce(.idle, .tick(now: finish.addingTimeInterval(600))), .idle)
    }

    func testIsRunningOnlyWhileRunning() {
        XCTAssertTrue(ActionOutcome.reduce(.idle, .started(action)).isRunning)
        XCTAssertFalse(ActionOutcome.idle.isRunning)
        XCTAssertFalse(checking().isRunning)
        XCTAssertFalse(failed().isRunning)
    }

    func testClockSteppingBackExpiresCheckingAndFailed() {
        let earlier = finish.addingTimeInterval(-5)
        XCTAssertEqual(ActionOutcome.reduce(checking(), .tick(now: earlier)), .idle)
        XCTAssertEqual(ActionOutcome.reduce(failed(), .tick(now: earlier)), .idle)
        XCTAssertEqual(ActionOutcome.reduce(failed(), .tick(now: finish)), .failed(action, message: "boom", at: finish))
    }
}
