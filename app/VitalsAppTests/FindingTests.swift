import XCTest
@testable import VitalsApp

final class FindingTests: XCTestCase {
    private func finding(_ rule: String, _ severity: Severity) -> Finding {
        Finding(rule: rule, severity: severity, message: rule, actions: [])
    }

    func testSortedBySeverityPutsCriticalBeforeWarnBeforeInfo() {
        let findings = [finding("a", .info), finding("b", .critical), finding("c", .warn)]
        let sorted = findings.sortedBySeverity()
        XCTAssertEqual(sorted.map(\.rule), ["b", "c", "a"])
    }

    func testSortedBySeverityPreservesOrderWithinTheSameSeverity() {
        let findings = [finding("a", .info), finding("b", .info), finding("c", .warn)]
        let sorted = findings.sortedBySeverity()
        XCTAssertEqual(sorted.map(\.rule), ["c", "a", "b"])
    }
}
