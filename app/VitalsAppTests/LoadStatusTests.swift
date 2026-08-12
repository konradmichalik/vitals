import XCTest
@testable import VitalsApp

final class LoadStatusTests: XCTestCase {
    func testNormalWhenWellBelowCoreCount() {
        XCTAssertEqual(LoadStatus.evaluate(load1: 2.0, performanceCores: 10), .normal)
    }

    func testWarnWhenAboveWarnFactor() {
        XCTAssertEqual(LoadStatus.evaluate(load1: 11.0, performanceCores: 10), .warn)
    }

    func testCriticalWhenAboveCriticalFactor() {
        XCTAssertEqual(LoadStatus.evaluate(load1: 16.0, performanceCores: 10), .critical)
    }

    func testNormalWhenNoPerformanceCoresReported() {
        XCTAssertEqual(LoadStatus.evaluate(load1: 100.0, performanceCores: 0), .normal)
    }

    func testBoundaryAtExactlyWarnFactorIsStillNormal() {
        XCTAssertEqual(LoadStatus.evaluate(load1: 10.0, performanceCores: 10), .normal)
    }

    func testBoundaryAtExactlyCriticalFactorIsStillWarn() {
        XCTAssertEqual(LoadStatus.evaluate(load1: 15.0, performanceCores: 10), .warn)
    }
}
