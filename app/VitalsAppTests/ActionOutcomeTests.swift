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

    func testSuccessMovesRunningToChecking() {
        XCTAssertEqual(checking(), .checking(action, since: finish))
    }

    func testFailureMovesRunningToFailedWithMessage() {
        let running = ActionOutcome.reduce(.idle, .started(action))
        let state = ActionOutcome.reduce(running, .finished(.failure(.nonZeroExit("boom\n")), at: finish))
        XCTAssertEqual(state, .failed(action, message: "boom"))
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
}
