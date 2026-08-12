import XCTest
@testable import VitalsApp

final class AppStateTests: XCTestCase {
    private func makeReport(findings: [Finding]) -> VitalsReport {
        VitalsReport(
            schemaVersion: 1,
            timestamp: "2026-08-12T09:52:00Z",
            system: SystemInfo(
                uptimeSeconds: 100,
                load: LoadAverage(m1: 1, m5: 1, m15: 1),
                cores: CoreCount(performance: 10, efficiency: 4, total: 14),
                memory: MemoryInfo(
                    pressureLevel: .normal,
                    freePercent: 50,
                    pageSizeBytes: 16384,
                    compressorBytes: 0,
                    swapUsedBytes: 0,
                    pageouts: 0
                )
            ),
            timeMachine: TimeMachineInfo(running: false, phase: nil, changedItemCount: nil, exclusions: []),
            ddev: DdevInfo(running: [], problems: [], pausedCount: 0, stoppedCount: 0),
            docker: DockerInfo(containers: []),
            processes: ProcessesInfo(claudeSessions: [], acpAgents: [], orbstack: nil),
            findings: findings
        )
    }

    func testUsesGreenIntervalWhenNoReportYet() {
        XCTAssertEqual(AppState.pollInterval(for: nil), AppState.greenInterval)
    }

    func testUsesGreenIntervalWhenNoFindings() {
        let report = makeReport(findings: [])
        XCTAssertEqual(AppState.pollInterval(for: report), AppState.greenInterval)
    }

    func testUsesAlertIntervalWhenAFindingFired() {
        let finding = Finding(rule: "uptime_ballast", severity: .info, message: "ballast", actions: [])
        let report = makeReport(findings: [finding])
        XCTAssertEqual(AppState.pollInterval(for: report), AppState.alertInterval)
    }
}
