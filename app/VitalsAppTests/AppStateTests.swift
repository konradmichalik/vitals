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
                    usedPercent: 50,
                    pageSizeBytes: 16384,
                    compressorBytes: 0,
                    swapUsedBytes: 0,
                    pageouts: 0
                ),
                cpu: CpuUsage(userPercent: 10, systemPercent: 5, idlePercent: 85)
            ),
            timeMachine: TimeMachineInfo(running: false, phase: nil, changedItemCount: nil, exclusions: []),
            ddev: DdevInfo(running: [], problems: [], pausedCount: 0, stoppedCount: 0),
            docker: DockerInfo(containers: []),
            processes: ProcessesInfo(claudeSessions: [], acpAgents: [], orbstack: nil, topByCpu: []),
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

    /// Info findings are advisory and often permanent (uptime ballast,
    /// unmanaged containers) — treating their mere existence as an alert
    /// pinned the app to the 10s interval indefinitely while the menu bar
    /// icon stayed green.
    func testUsesGreenIntervalWhenOnlyInfoFindingsFired() {
        let finding = Finding(rule: "uptime_ballast", severity: .info, message: "ballast", actions: [])
        let report = makeReport(findings: [finding])
        XCTAssertEqual(AppState.pollInterval(for: report), AppState.greenInterval)
    }

    func testUsesAlertIntervalWhenAWarnFindingFired() {
        let finding = Finding(rule: "memory_pressure", severity: .warn, message: "swap", actions: [])
        let report = makeReport(findings: [finding])
        XCTAssertEqual(AppState.pollInterval(for: report), AppState.alertInterval)
    }

    func testUsesAlertIntervalWhenACriticalFindingFired() {
        let finding = Finding(rule: "load_status", severity: .critical, message: "load", actions: [])
        let report = makeReport(findings: [finding])
        XCTAssertEqual(AppState.pollInterval(for: report), AppState.alertInterval)
    }

    func testUsesAlertIntervalWhenInfoAndWarnFindingsMix() {
        let report = makeReport(findings: [
            Finding(rule: "uptime_ballast", severity: .info, message: "ballast", actions: []),
            Finding(rule: "memory_pressure", severity: .warn, message: "swap", actions: []),
        ])
        XCTAssertEqual(AppState.pollInterval(for: report), AppState.alertInterval)
    }
}
