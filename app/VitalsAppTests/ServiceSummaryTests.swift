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

    private func agent(orphaned: Bool) -> AcpAgent {
        AcpAgent(pid: 1, etimeSeconds: 60, ideVersion: "2025.1", orphaned: orphaned)
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

    // MARK: - IDE agents

    func testIdeAgentsLabelIsNilWhenNoneRun() {
        XCTAssertNil(ServiceSummary.ideAgentsLabel([]))
    }

    func testIdeAgentsLabelCountsAgents() {
        let label = ServiceSummary.ideAgentsLabel([agent(orphaned: false), agent(orphaned: false)])
        XCTAssertEqual(label, "2 agent(s)")
    }

    func testIdeAgentsLabelCallsOutOrphans() {
        let label = ServiceSummary.ideAgentsLabel([agent(orphaned: true), agent(orphaned: false)])
        XCTAssertTrue(label?.contains("1 orphaned") == true, "got: \(label ?? "nil")")
    }

    // MARK: - OrbStack

    func testOrbstackLabelIsNilWhenNotRunning() {
        XCTAssertNil(ServiceSummary.orbstackLabel(nil))
    }

    func testOrbstackLabelNamesCpuAndMemory() {
        let process = OrbstackProcess(pid: 1, cpuPercent: 254.6, rssBytes: 3_221_225_472)
        let label = ServiceSummary.orbstackLabel(process)
        XCTAssertTrue(label?.contains("255% CPU") == true, "got: \(label ?? "nil")")
        XCTAssertTrue(label?.contains("3.0 GB") == true, "got: \(label ?? "nil")")
    }
}
