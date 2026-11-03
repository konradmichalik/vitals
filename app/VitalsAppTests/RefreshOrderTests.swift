import XCTest
@testable import VitalsApp

final class RefreshOrderTests: XCTestCase {
    func testOlderRefreshLandingAfterANewerOneIsDropped() {
        var order = RefreshOrder()
        let first = order.begin()
        let second = order.begin()
        XCTAssertTrue(order.accept(second))
        XCTAssertFalse(order.accept(first))
    }

    /// The wall-clock rule dropped every refresh that started after the clock stepped back.
    func testClockStepBackDoesNotChangeTheDecision() {
        var order = RefreshOrder()
        XCTAssertTrue(order.accept(order.begin()))
        // The next refresh may start at an earlier Date; it still started later and applies.
        XCTAssertTrue(order.accept(order.begin()))
    }

    func testOlderSuccessCannotOverrideANewerFailure() {
        var order = RefreshOrder()
        let olderSuccess = order.begin()
        let newerFailure = order.begin()
        XCTAssertTrue(order.accept(newerFailure))
        XCTAssertFalse(order.accept(olderSuccess))
    }
}
