import XCTest
@testable import VitalsApp

final class ServiceSummaryTests: XCTestCase {
    private func timeMachine(
        running: Bool,
        phase: String? = nil,
        changedItemCount: UInt64? = nil
    ) -> TimeMachineInfo {
        TimeMachineInfo(
            running: running,
            phase: phase,
            changedItemCount: changedItemCount,
            exclusions: []
        )
    }

    // MARK: - Time Machine

    func testTimeMachineReadsAsIdleWhenNotRunning() {
        XCTAssertEqual(ServiceSummary.timeMachineLabel(timeMachine(running: false)), "Idle")
    }

    /// Time Machine scanning container data is one of only two critical
    /// rules, yet its state was nowhere in the UI — so a user could see
    /// the finding without any way to watch what it was reacting to.
    func testTimeMachineNamesItsPhaseAndChangedItemsWhileRunning() {
        let label = ServiceSummary.timeMachineLabel(
            timeMachine(running: true, phase: "Copying", changedItemCount: 51_234),
            locale: Locale(identifier: "en_US")
        )
        XCTAssertTrue(label.contains("Copying"), "got: \(label)")
        XCTAssertTrue(label.contains("51,234"), "got: \(label)")
    }

    func testTimeMachineFallsBackWhenPhaseIsUnknown() {
        let label = ServiceSummary.timeMachineLabel(timeMachine(running: true))
        XCTAssertFalse(label.isEmpty)
        XCTAssertNotEqual(label, "Idle")
    }
}
