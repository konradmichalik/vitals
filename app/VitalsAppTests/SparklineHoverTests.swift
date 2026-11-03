import XCTest
@testable import VitalsApp

final class SparklineHoverTests: XCTestCase {
    func testIndexPastAShrunkWindowIsDropped() {
        XCTAssertNil(SparklineHover.validIndex(5, count: 3))
        XCTAssertNil(SparklineHover.validIndex(3, count: 3))
        XCTAssertNil(SparklineHover.validIndex(0, count: 0))
    }

    func testIndexInsideTheWindowIsKept() {
        XCTAssertEqual(SparklineHover.validIndex(2, count: 3), 2)
        XCTAssertEqual(SparklineHover.validIndex(0, count: 3), 0)
    }

    func testMissingOrNegativeIndexIsNil() {
        XCTAssertNil(SparklineHover.validIndex(nil, count: 3))
        XCTAssertNil(SparklineHover.validIndex(-1, count: 3))
    }
}
