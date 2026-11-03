import XCTest
@testable import VitalsApp

final class PopoverScreenTests: XCTestCase {
    func test_toggling_activity_twice_returns_to_overview() {
        let once = PopoverScreen.overview.toggled(.activity)
        XCTAssertEqual(once, .activity)
        XCTAssertEqual(once.toggled(.activity), .overview)
    }

    func test_toggling_settings_on_settings_returns_to_overview() {
        XCTAssertEqual(PopoverScreen.settings.toggled(.settings), .overview)
    }

    func test_toggling_other_screen_switches_to_it() {
        XCTAssertEqual(PopoverScreen.activity.toggled(.settings), .settings)
    }

    func test_toggling_detail_on_itself_keeps_detail() {
        XCTAssertEqual(PopoverScreen.detail(.cpu).toggled(.detail(.cpu)), .detail(.cpu))
    }

    func test_detail_title_is_details() {
        XCTAssertEqual(PopoverScreen.detail(.memory).title, "Details")
    }

    func test_titles() {
        XCTAssertEqual(PopoverScreen.overview.title, "Vitals")
        XCTAssertEqual(PopoverScreen.toolchain(.ddev).title, "Toolchain")
        XCTAssertEqual(PopoverScreen.activity.title, "Activity")
        XCTAssertEqual(PopoverScreen.settings.title, "Settings")
    }
}
