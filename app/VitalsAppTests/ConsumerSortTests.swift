import XCTest
@testable import VitalsApp

final class ConsumerSortTests: XCTestCase {
    private func consumer(_ id: String, cpu: Double, mem: UInt64) -> Consumer {
        Consumer(
            id: id, kind: .process, label: id, detail: nil,
            cpuPercent: cpu, memBytes: mem, children: [], action: nil
        )
    }

    private func finding(_ rule: String, _ severity: Severity) -> Finding {
        Finding(rule: rule, severity: severity, message: rule, actions: [])
    }

    func test_consumers_sort_by_cpu_and_memory() {
        let consumers = [
            consumer("a", cpu: 10, mem: 3_000),
            consumer("b", cpu: 90, mem: 1_000),
            consumer("c", cpu: 50, mem: 2_000),
        ]
        XCTAssertEqual(ConsumerSort.sorted(consumers, by: .cpu).map(\.id), ["b", "c", "a"])
        XCTAssertEqual(ConsumerSort.sorted(consumers, by: .memory).map(\.id), ["a", "c", "b"])
    }

    func test_ties_keep_report_order() {
        let consumers = [consumer("a", cpu: 5, mem: 1), consumer("b", cpu: 5, mem: 1)]
        XCTAssertEqual(ConsumerSort.sorted(consumers, by: .cpu).map(\.id), ["a", "b"])
        XCTAssertEqual(ConsumerSort.sorted(consumers, by: .memory).map(\.id), ["a", "b"])
    }

    func test_default_sort_is_memory_when_verdict_comes_from_memory_pressure() {
        XCTAssertEqual(ConsumerSort.defaultSort(for: [finding("memory_pressure", .warn)]), .memory)
        let mixed = [finding("load_status", .warn), finding("memory_pressure", .critical)]
        XCTAssertEqual(ConsumerSort.defaultSort(for: mixed), .memory)
    }

    func test_default_sort_is_cpu_otherwise() {
        XCTAssertEqual(ConsumerSort.defaultSort(for: []), .cpu)
        let tie = [finding("memory_pressure", .warn), finding("load_status", .warn)]
        XCTAssertEqual(ConsumerSort.defaultSort(for: tie), .cpu)
        XCTAssertEqual(ConsumerSort.defaultSort(for: [finding("memory_pressure", .info)]), .cpu)
    }
}
