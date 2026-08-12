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
}
