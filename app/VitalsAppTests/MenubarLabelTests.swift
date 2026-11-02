import XCTest
@testable import VitalsApp

final class MenubarLabelTests: XCTestCase {
    private func report(_ findings: [Finding], idle: Double = 8, pressure: PressureLevel = .critical) -> VitalsReport {
        VitalsReport(
            schemaVersion: 1,
            timestamp: "2026-08-12T09:52:00Z",
            system: SystemInfo(
                uptimeSeconds: 100,
                load: LoadAverage(m1: 1, m5: 1, m15: 1),
                cores: CoreCount(performance: 10, efficiency: 4, total: 14),
                memory: MemoryInfo(
                    pressureLevel: pressure, freePercent: 5, usedPercent: 95,
                    pageSizeBytes: 16384, compressorBytes: 0, swapUsedBytes: 0, pageouts: 0
                ),
                cpu: CpuUsage(userPercent: 80, systemPercent: 12, idlePercent: idle)
            ),
            timeMachine: TimeMachineInfo(running: false, phase: nil, changedItemCount: nil, exclusions: []),
            ddev: DdevInfo(running: [], problems: [], pausedCount: 0, stoppedCount: 0, projects: []),
            docker: DockerInfo(containers: []),
            processes: ProcessesInfo(claudeSessions: [], acpAgents: [], orbstack: nil, topByCpu: [], topByMemory: []),
            findings: findings,
            consumers: [],
            verdict: Verdict(severity: nil, headline: "", detail: "", culprit: nil, action: nil)
        )
    }

    private func finding(_ rule: String, _ severity: Severity) -> Finding {
        Finding(rule: rule, severity: severity, message: "m", actions: [])
    }

    func testLabelOnlyWhenCriticalAndEnabled() {
        let critical = report([finding("load_status", .critical)])
        XCTAssertEqual(MenubarLabel.text(for: critical, enabled: true), "CPU 92%")
        XCTAssertNil(MenubarLabel.text(for: critical, enabled: false))
        XCTAssertNil(MenubarLabel.text(for: report([finding("load_status", .warn)]), enabled: true))
        XCTAssertNil(MenubarLabel.text(for: report([finding("ddev_problems", .critical)]), enabled: true))
    }

    func testMemoryCriticalLabel() {
        let memory = report([finding("memory_pressure", .critical)])
        XCTAssertEqual(MenubarLabel.text(for: memory, enabled: true), "Mem Critical")
    }

    func testLoadWinsWhenBothAreCritical() {
        let both = report([finding("memory_pressure", .critical), finding("load_status", .critical)])
        XCTAssertEqual(MenubarLabel.text(for: both, enabled: true), "CPU 92%")
    }

    func testCpuLabelRoundsInsteadOfTruncating() {
        let rounded = report([finding("load_status", .critical)], idle: 7.4)
        XCTAssertEqual(MenubarLabel.text(for: rounded, enabled: true), "CPU 93%")
    }

    func testMemoryLabelFollowsPressureLevel() {
        let high = report([finding("memory_pressure", .critical)], pressure: .warn)
        XCTAssertEqual(MenubarLabel.text(for: high, enabled: true), "Mem High")
    }
}
