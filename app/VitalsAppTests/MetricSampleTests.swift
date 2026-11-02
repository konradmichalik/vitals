import XCTest
@testable import VitalsApp

final class MetricSampleTests: XCTestCase {
    private func report(
        load1: Double,
        idlePercent: Double,
        memoryUsedPercent: UInt8,
        pressureLevel: PressureLevel = .normal,
        swapUsedBytes: UInt64 = 0
    ) -> VitalsReport {
        VitalsReport(
            schemaVersion: 1,
            timestamp: "2026-08-12T09:52:00Z",
            system: SystemInfo(
                uptimeSeconds: 100,
                load: LoadAverage(m1: load1, m5: load1, m15: load1),
                cores: CoreCount(performance: 10, efficiency: 4, total: 14),
                memory: MemoryInfo(
                    pressureLevel: pressureLevel,
                    freePercent: 0,
                    usedPercent: memoryUsedPercent,
                    pageSizeBytes: 16384,
                    compressorBytes: 0,
                    swapUsedBytes: swapUsedBytes,
                    pageouts: 0
                ),
                cpu: CpuUsage(userPercent: 0, systemPercent: 0, idlePercent: idlePercent)
            ),
            timeMachine: TimeMachineInfo(running: false, phase: nil, changedItemCount: nil, exclusions: []),
            ddev: DdevInfo(running: [], problems: [], pausedCount: 0, stoppedCount: 0, projects: []),
            docker: DockerInfo(containers: []),
            processes: ProcessesInfo(claudeSessions: [], acpAgents: [], orbstack: nil, topByCpu: [], topByMemory: []),
            findings: [],
            consumers: [],
            verdict: Verdict(severity: nil, headline: "All calm", detail: "", culprit: nil, action: nil)
        )
    }

    private func sample(
        load: Double = 0,
        cpuUsedPercent: Double = 0,
        memoryUsedPercent: Double = 0,
        loadStatus: LoadStatus = .normal,
        memoryPressure: PressureLevel = .normal,
        swapUsedBytes: UInt64 = 0,
        timestamp: Date = Date(timeIntervalSince1970: 0)
    ) -> MetricSample {
        MetricSample(
            load: load,
            loadStatus: loadStatus,
            cpuUsedPercent: cpuUsedPercent,
            memoryUsedPercent: memoryUsedPercent,
            memoryPressure: memoryPressure,
            swapUsedBytes: swapUsedBytes,
            timestamp: timestamp
        )
    }

    func testFromReportExtractsLoadCpuAndMemory() {
        let extracted = MetricSample.from(report: report(load1: 13.5, idlePercent: 30, memoryUsedPercent: 78))
        XCTAssertEqual(extracted.load, 13.5)
        XCTAssertEqual(extracted.cpuUsedPercent, 70)
        XCTAssertEqual(extracted.memoryUsedPercent, 78)
    }

    func testFromReportCarriesTheGivenTimestamp() {
        let fixedDate = Date(timeIntervalSince1970: 1_723_000_000)
        let extracted = MetricSample.from(
            report: report(load1: 1, idlePercent: 90, memoryUsedPercent: 50),
            timestamp: fixedDate
        )
        XCTAssertEqual(extracted.timestamp, fixedDate)
    }

    func testFromReportClassifiesLoadStatusAgainstPerformanceCores() {
        // 16.0 vs 10 performance cores is > the 1.5x critical factor.
        let extracted = MetricSample.from(report: report(load1: 16.0, idlePercent: 30, memoryUsedPercent: 78))
        XCTAssertEqual(extracted.loadStatus, .critical)
    }

    func testFromReportCarriesMemoryPressureLevel() {
        let extracted = MetricSample.from(
            report: report(load1: 1, idlePercent: 90, memoryUsedPercent: 50, pressureLevel: .warn)
        )
        XCTAssertEqual(extracted.memoryPressure, .warn)
    }

    func testAppendingAddsToEmptyHistory() {
        let point = sample(load: 1, cpuUsedPercent: 2, memoryUsedPercent: 3)
        XCTAssertEqual(MetricHistory.appending(point, to: []), [point])
    }

    func testAppendingKeepsHistoryBelowMaxSamples() {
        let existing = (0..<MetricHistory.maxSamples).map { sample(load: Double($0)) }
        let newest = sample(load: 999)

        let result = MetricHistory.appending(newest, to: existing)

        XCTAssertEqual(result.count, MetricHistory.maxSamples)
        XCTAssertEqual(result.last, newest)
        XCTAssertEqual(result.first, existing[1])
    }

    func testFromReportCarriesSwapUsedBytes() {
        let extracted = MetricSample.from(
            report: report(load1: 1, idlePercent: 90, memoryUsedPercent: 50, swapUsedBytes: 2_048)
        )
        XCTAssertEqual(extracted.swapUsedBytes, 2_048)
    }

    func testAppendingCapsAt360() {
        XCTAssertEqual(MetricHistory.maxSamples, 360)
        let existing = (0..<360).map { sample(load: Double($0)) }
        let result = MetricHistory.appending(sample(load: 999), to: existing)
        XCTAssertEqual(result.count, 360)
        XCTAssertEqual(result.first?.load, 1)
        XCTAssertEqual(result.last?.load, 999)
    }

    func testWindowKeepsOnlySamplesInsideRange() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let history = [1200.0, 600, 60].map { sample(load: $0, timestamp: now.addingTimeInterval(-$0)) }
        let kept = MetricHistory.window(history, range: .fifteenMinutes, now: now)
        XCTAssertEqual(kept.map(\.load), [600, 60])
        XCTAssertEqual(MetricHistory.window(history, range: .oneHour, now: now).count, 3)
    }

    func testHistoryRangeSecondsAndLabels() {
        XCTAssertEqual(HistoryRange.allCases.map(\.seconds), [900, 3600])
        XCTAssertEqual(HistoryRange.allCases.map(\.label), ["15m", "1h"])
    }
}
