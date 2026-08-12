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
}
