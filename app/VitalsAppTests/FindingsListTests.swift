import XCTest
@testable import VitalsApp

final class FindingsListTests: XCTestCase {
    private func finding(_ rule: String, _ severity: Severity) -> Finding {
        Finding(rule: rule, severity: severity, message: rule, actions: [])
    }

    private var all: [Finding] {
        [finding("load_status", .warn), finding("memory_pressure", .warn), finding("stale_claude_sessions", .info)]
    }

    func test_list_leaves_out_the_finding_the_verdict_already_states() {
        let listed = FindingsList.listed(all: all, visible: all)
        XCTAssertEqual(listed.shown.map(\.rule), ["memory_pressure", "stale_claude_sessions"])
        XCTAssertEqual(listed.snoozed, 0)
    }

    func test_snoozed_findings_are_counted_not_listed() {
        let visible = all.filter { $0.rule != "memory_pressure" }
        let listed = FindingsList.listed(all: all, visible: visible)
        XCTAssertEqual(listed.shown.map(\.rule), ["stale_claude_sessions"])
        XCTAssertEqual(listed.snoozed, 1)
    }

    func test_a_lone_verdict_finding_leaves_an_empty_list_without_a_snooze() {
        let only = [finding("load_status", .critical)]
        let listed = FindingsList.listed(all: only, visible: only)
        XCTAssertTrue(listed.shown.isEmpty)
        XCTAssertEqual(listed.snoozed, 0)
    }

    func test_without_a_verdict_every_finding_is_listed() {
        let calm = [finding("stale_claude_sessions", .info)]
        let listed = FindingsList.listed(all: calm, visible: calm)
        XCTAssertEqual(listed.shown.map(\.rule), ["stale_claude_sessions"])
    }
}
