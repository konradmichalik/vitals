import XCTest
@testable import VitalsApp

final class SeverityTests: XCTestCase {
    func testInfoIsLessThanWarn() {
        XCTAssertLessThan(Severity.info, Severity.warn)
    }

    func testWarnIsLessThanCritical() {
        XCTAssertLessThan(Severity.warn, Severity.critical)
    }

    func testInfoIsLessThanCritical() {
        XCTAssertLessThan(Severity.info, Severity.critical)
    }

    func testMaxOfMixedSeveritiesIsCritical() {
        let severities: [Severity] = [.info, .critical, .warn]
        XCTAssertEqual(severities.max(), .critical)
    }

    func testMaxOfEmptyIsNil() {
        let severities: [Severity] = []
        XCTAssertNil(severities.max())
    }
}
