import XCTest
@testable import VitalsApp

final class TileToneTests: XCTestCase {
    private func makeReport(
        pressure: PressureLevel = .normal,
        usedPercent: UInt8 = 50,
        swapUsedBytes: UInt64 = 0,
        load1: Double = 1,
        findings: [Finding] = []
    ) -> VitalsReport {
        VitalsReport(
            schemaVersion: 4,
            timestamp: "2026-11-02T09:00:00Z",
            system: SystemInfo(
                uptimeSeconds: 100,
                load: LoadAverage(m1: load1, m5: load1, m15: load1),
                cores: CoreCount(performance: 10, efficiency: 4, total: 14),
                memory: MemoryInfo(
                    pressureLevel: pressure,
                    freePercent: 100 - usedPercent,
                    usedPercent: usedPercent,
                    pageSizeBytes: 16384,
                    compressorBytes: 0,
                    swapUsedBytes: swapUsedBytes,
                    pageouts: 0
                ),
                cpu: CpuUsage(userPercent: 10, systemPercent: 5, idlePercent: 85)
            ),
            timeMachine: TimeMachineInfo(running: false, phase: nil, changedItemCount: nil, exclusions: []),
            ddev: DdevInfo(running: [], problems: [], pausedCount: 0, stoppedCount: 0, projects: []),
            docker: DockerInfo(containers: []),
            processes: ProcessesInfo(claudeSessions: [], acpAgents: [], orbstack: nil, topByCpu: [], topByMemory: []),
            findings: findings,
            consumers: [],
            verdict: Verdict(severity: nil, headline: "All calm", detail: "", culprit: nil, action: nil)
        )
    }

    private func finding(_ rule: String, _ severity: Severity) -> Finding {
        Finding(rule: rule, severity: severity, message: rule, actions: [])
    }

    func test_memory_tile_warns_on_pressure_not_percent() {
        XCTAssertEqual(TileTone.tone(for: .memory, report: makeReport(pressure: .normal, usedPercent: 95)), .neutral)
        XCTAssertEqual(TileTone.tone(for: .memory, report: makeReport(pressure: .warn, usedPercent: 40)), .warn)
        XCTAssertEqual(TileTone.tone(for: .memory, report: makeReport(pressure: .critical)), .critical)
    }

    func test_swap_tile_follows_pressure() {
        let bigSwap: UInt64 = 20 * 1024 * 1024 * 1024
        XCTAssertEqual(TileTone.tone(for: .swap, report: makeReport(pressure: .normal, swapUsedBytes: bigSwap)), .neutral)
        XCTAssertEqual(TileTone.tone(for: .swap, report: makeReport(pressure: .warn)), .warn)
        XCTAssertEqual(TileTone.tone(for: .swap, report: makeReport(pressure: .critical)), .critical)
    }

    func test_cpu_tile_critical_with_load_critical() {
        let critical = makeReport(findings: [finding("load_status", .critical)])
        XCTAssertEqual(TileTone.tone(for: .cpu, report: critical), .critical)
        let runaway = makeReport(findings: [finding("runaway_processes", .warn)])
        XCTAssertEqual(TileTone.tone(for: .cpu, report: runaway), .warn)
        let loadWarn = makeReport(findings: [finding("load_status", .warn)])
        XCTAssertEqual(TileTone.tone(for: .cpu, report: loadWarn), .neutral)
        XCTAssertEqual(TileTone.tone(for: .cpu, report: makeReport()), .neutral)
    }

    func test_load_tile_follows_load_status() {
        XCTAssertEqual(TileTone.tone(for: .load, report: makeReport(load1: 5)), .neutral)
        XCTAssertEqual(TileTone.tone(for: .load, report: makeReport(load1: 11)), .warn)
        XCTAssertEqual(TileTone.tone(for: .load, report: makeReport(load1: 16)), .critical)
    }

    func test_pressure_label_copy() {
        XCTAssertEqual(TileTone.pressureLabel(.normal), "Normal")
        XCTAssertEqual(TileTone.pressureLabel(.warn), "High")
        XCTAssertEqual(TileTone.pressureLabel(.critical), "Critical")
    }
}
