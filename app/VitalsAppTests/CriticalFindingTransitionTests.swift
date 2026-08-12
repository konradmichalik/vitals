import XCTest
@testable import VitalsApp

final class CriticalFindingTransitionTests: XCTestCase {
    private func finding(_ rule: String, _ severity: Severity) -> Finding {
        Finding(rule: rule, severity: severity, message: "test", actions: [])
    }

    func testCriticalRuleNamesIgnoresNonCriticalFindings() {
        let findings = [finding("uptime_ballast", .info), finding("disk_pressure", .critical)]
        XCTAssertEqual(CriticalFindingTransition.criticalRuleNames(in: findings), ["disk_pressure"])
    }

    func testNoNewlyCriticalWhenNothingIsCriticalNow() {
        let result = CriticalFindingTransition.newlyCritical(previous: [], current: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testNewlyCriticalWhenRuleBecomesCriticalForTheFirstTime() {
        let result = CriticalFindingTransition.newlyCritical(previous: [], current: ["disk_pressure"])
        XCTAssertEqual(result, ["disk_pressure"])
    }

    func testNotNewlyCriticalWhenRuleWasAlreadyCritical() {
        let result = CriticalFindingTransition.newlyCritical(previous: ["disk_pressure"], current: ["disk_pressure"])
        XCTAssertTrue(result.isEmpty)
    }

    func testOnlyReportsTheRuleThatActuallyBecameNewlyCritical() {
        let current: Set<String> = ["disk_pressure", "orphaned_agents"]
        let result = CriticalFindingTransition.newlyCritical(previous: ["disk_pressure"], current: current)
        XCTAssertEqual(result, ["orphaned_agents"])
    }
}
