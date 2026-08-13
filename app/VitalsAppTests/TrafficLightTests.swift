import XCTest
@testable import VitalsApp

final class TrafficLightTests: XCTestCase {
    private func finding(_ severity: Severity) -> Finding {
        Finding(rule: "test_rule", severity: severity, message: "test", actions: [])
    }

    func testGreenWhenNoFindings() {
        XCTAssertEqual(TrafficLight.from(findings: []), .green)
    }

    func testYellowWhenHighestFindingIsWarn() {
        let findings = [finding(.info), finding(.warn)]
        XCTAssertEqual(TrafficLight.from(findings: findings), .yellow)
    }

    func testRedWhenAnyFindingIsCritical() {
        let findings = [finding(.info), finding(.warn), finding(.critical)]
        XCTAssertEqual(TrafficLight.from(findings: findings), .red)
    }

    /// Info-only findings count as "nothing to act on" for the overall
    /// badge — only warn/critical actually escalate it away from green.
    /// The findings list itself still shows each one with its own blue
    /// `info` badge (SeverityBadge), so the detail isn't lost — this is
    /// specifically about the at-a-glance summary color.
    func testGreenWhenOnlyInfoFindings() {
        let findings = [finding(.info), finding(.info)]
        XCTAssertEqual(TrafficLight.from(findings: findings), .green)
    }

    func testTooltipForNoFindings() {
        XCTAssertEqual(TrafficLight.tooltip(for: []), "Vitals — all clear")
    }

    func testTooltipCountsFindingsAndNamesHighestSeverity() {
        let findings = [finding(.info), finding(.warn)]
        XCTAssertEqual(TrafficLight.tooltip(for: findings), "Vitals — 2 finding(s), highest: warning")
    }

    func testTooltipNamesCriticalAsHighest() {
        let findings = [finding(.info), finding(.critical)]
        XCTAssertEqual(TrafficLight.tooltip(for: findings), "Vitals — 2 finding(s), highest: critical")
    }

    func testTooltipNamesInfoAsHighestWhenOnlyInfoFindings() {
        let findings = [finding(.info)]
        XCTAssertEqual(TrafficLight.tooltip(for: findings), "Vitals — 1 finding(s), highest: info")
    }

    func testStatusLabelForNoFindings() {
        XCTAssertEqual(TrafficLight.statusLabel(for: []), "All clear")
    }

    func testStatusLabelForOneFinding() {
        XCTAssertEqual(TrafficLight.statusLabel(for: [finding(.warn)]), "1 finding")
    }

    func testStatusLabelForMultipleFindingsIsPlural() {
        XCTAssertEqual(TrafficLight.statusLabel(for: [finding(.warn), finding(.info)]), "2 findings")
    }
}
