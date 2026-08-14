import XCTest
@testable import VitalsApp

final class FindingAlertTransitionTests: XCTestCase {
    private func finding(_ rule: String, _ severity: Severity) -> Finding {
        Finding(rule: rule, severity: severity, message: "test", actions: [])
    }

    func testAlertingSeveritiesIgnoresInfoFindings() {
        let findings = [
            finding("uptime_ballast", .info),
            finding("memory_pressure", .warn),
            finding("disk_pressure", .critical),
        ]
        XCTAssertEqual(
            FindingAlertTransition.alertingSeverities(in: findings),
            ["memory_pressure": .warn, "disk_pressure": .critical]
        )
    }

    func testNoNewlyAlertingWhenNothingAlerts() {
        XCTAssertTrue(FindingAlertTransition.newlyAlerting(previous: [:], current: [:]).isEmpty)
    }

    /// The gap this replaces: a warn-level finding never notified at all,
    /// so the cheap-to-fix stage stayed invisible with the dropdown shut.
    func testNewlyAlertingWhenRuleBecomesWarnForTheFirstTime() {
        let result = FindingAlertTransition.newlyAlerting(
            previous: [:],
            current: ["memory_pressure": .warn]
        )
        XCTAssertEqual(result, ["memory_pressure"])
    }

    func testNewlyAlertingWhenRuleBecomesCriticalForTheFirstTime() {
        let result = FindingAlertTransition.newlyAlerting(
            previous: [:],
            current: ["disk_pressure": .critical]
        )
        XCTAssertEqual(result, ["disk_pressure"])
    }

    func testNotNewlyAlertingWhenRuleStaysAtTheSameSeverity() {
        let result = FindingAlertTransition.newlyAlerting(
            previous: ["disk_pressure": .critical],
            current: ["disk_pressure": .critical]
        )
        XCTAssertTrue(result.isEmpty)
    }

    /// Tracking mere membership would swallow this — the rule is already
    /// in the previous set, so escalation to critical would never notify.
    func testNewlyAlertingWhenRuleEscalatesFromWarnToCritical() {
        let result = FindingAlertTransition.newlyAlerting(
            previous: ["memory_pressure": .warn],
            current: ["memory_pressure": .critical]
        )
        XCTAssertEqual(result, ["memory_pressure"])
    }

    func testNotNewlyAlertingWhenRuleDeescalatesFromCriticalToWarn() {
        let result = FindingAlertTransition.newlyAlerting(
            previous: ["memory_pressure": .critical],
            current: ["memory_pressure": .warn]
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testOnlyReportsTheRuleThatActuallyChanged() {
        let result = FindingAlertTransition.newlyAlerting(
            previous: ["disk_pressure": .critical],
            current: ["disk_pressure": .critical, "memory_pressure": .warn]
        )
        XCTAssertEqual(result, ["memory_pressure"])
    }
}
