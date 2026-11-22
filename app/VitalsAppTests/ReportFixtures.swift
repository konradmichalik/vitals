@testable import VitalsApp

/// Shared report builder for the tests of the overview logic.
enum ReportFixtures {
    static func report(
        pressure: PressureLevel = .normal,
        idlePercent: Double = 80,
        available: UInt64? = 6_442_450_944,
        swap: UInt64 = 0,
        findings: [Finding] = [],
        consumers: [ConsumerGroup]? = nil
    ) -> VitalsReport {
        var memory = MemoryInfo(
            pressureLevel: pressure, freePercent: 10, usedPercent: 75, pageSizeBytes: 16384,
            compressorBytes: 0, swapUsedBytes: swap, pageouts: 0
        )
        memory.totalBytes = 25_769_803_776
        memory.availableBytes = available
        var report = VitalsReport(
            schemaVersion: 4,
            timestamp: "2026-11-20T09:00:00Z",
            system: SystemInfo(
                uptimeSeconds: 100,
                load: LoadAverage(m1: 1, m5: 1, m15: 1),
                cores: CoreCount(performance: 10, efficiency: 4, total: 14),
                memory: memory,
                cpu: CpuUsage(userPercent: 10, systemPercent: 10, idlePercent: idlePercent)
            ),
            timeMachine: TimeMachineInfo(running: false, phase: nil, changedItemCount: nil, exclusions: []),
            ddev: DdevInfo(running: [], problems: [], pausedCount: 0, stoppedCount: 0),
            docker: DockerInfo(containers: []),
            processes: ProcessesInfo(
                claudeSessions: [], acpAgents: [], orbstack: nil,
                topByCpu: [TopProcess(pid: 1, name: "node", cpuPercent: 700)]
            ),
            findings: findings
        )
        report.consumers = consumers
        return report
    }

    static func group(id: String, idle: UInt64) -> ConsumerGroup {
        ConsumerGroup(id: id, name: id, memBytes: idle + 1_000, cpuPercent: 1, idleBytes: idle, items: [])
    }
}
