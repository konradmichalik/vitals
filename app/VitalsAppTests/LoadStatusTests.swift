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

    func testNormalLabelIsHumanReadable() {
        XCTAssertEqual(LoadStatus.normal.label, "Normal")
    }

    func testWarnLabelIsHumanReadable() {
        XCTAssertEqual(LoadStatus.warn.label, "Elevated")
    }

    func testCriticalLabelIsHumanReadable() {
        XCTAssertEqual(LoadStatus.critical.label, "Critical")
    }

    func testProgressFractionAtZeroLoadIsZero() {
        XCTAssertEqual(LoadStatus.progressFraction(load1: 0, performanceCores: 10), 0, accuracy: 0.001)
    }

    func testProgressFractionAtHalfOfCriticalIsHalf() {
        // criticalFactor is 1.5, so 1.5 * 10 / 2 = 7.5 is the halfway point.
        XCTAssertEqual(LoadStatus.progressFraction(load1: 7.5, performanceCores: 10), 0.5, accuracy: 0.001)
    }

    func testProgressFractionAtCriticalThresholdIsFull() {
        XCTAssertEqual(LoadStatus.progressFraction(load1: 15, performanceCores: 10), 1.0, accuracy: 0.001)
    }

    func testProgressFractionCapsAtOneWellAboveCritical() {
        XCTAssertEqual(LoadStatus.progressFraction(load1: 100, performanceCores: 10), 1.0, accuracy: 0.001)
    }

    func testProgressFractionIsZeroWithNoPerformanceCores() {
        XCTAssertEqual(LoadStatus.progressFraction(load1: 100, performanceCores: 0), 0, accuracy: 0.001)
    }
}
