import XCTest
@testable import VitalsApp

final class MetricSeriesTests: XCTestCase {
    private func sample(load: Double = 1, memory: Double = 50, swap: UInt64 = 0, cpu: Double = 10) -> MetricSample {
        MetricSample(
            load: load,
            loadStatus: .normal,
            cpuUsedPercent: cpu,
            memoryUsedPercent: memory,
            memoryPressure: .normal,
            swapUsedBytes: swap,
            timestamp: Date(timeIntervalSince1970: 0)
        )
    }

    func test_swap_values_are_gigabytes() {
        let gib: UInt64 = 1024 * 1024 * 1024
        let values = MetricSeries.values(.swap, from: [sample(swap: 3 * gib), sample(swap: gib / 2)], performanceCores: 1)
        XCTAssertEqual(values, [3.0, 0.5])
        XCTAssertEqual(MetricSeries.format(.swap, 3.04), "3.0 GB")
    }

    func test_load_format_has_times_sign() {
        XCTAssertEqual(MetricSeries.format(.load, 1.26), "1.3×")
        XCTAssertEqual(MetricSeries.values(.load, from: [sample(load: 15)], performanceCores: 10), [1.5])
    }

    func test_memory_values_come_from_used_percent() {
        XCTAssertEqual(MetricSeries.values(.memory, from: [sample(memory: 81), sample(memory: 64)], performanceCores: 1), [81, 64])
        XCTAssertEqual(MetricSeries.format(.memory, 80.6), "81%")
        XCTAssertEqual(MetricSeries.values(.cpu, from: [sample(cpu: 42)], performanceCores: 1), [42])
        XCTAssertEqual(MetricSeries.format(.cpu, 41.5), "42%")
    }

    func test_ago_is_whole_minutes() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(MetricSeries.ago(from: now.addingTimeInterval(-180), now: now), "3 min ago")
        XCTAssertEqual(MetricSeries.ago(from: now.addingTimeInterval(-10), now: now), "just now")
    }
}
