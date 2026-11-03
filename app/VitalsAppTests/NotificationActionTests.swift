import UserNotifications
import XCTest
@testable import VitalsApp

final class NotificationActionTests: XCTestCase {
    private let info: [AnyHashable: Any] = ["rule": "swap_pressure"]
    private let defaultTap = UNNotificationDefaultActionIdentifier

    func test_parse_show_action() {
        XCTAssertEqual(NotificationResponse.parse(actionIdentifier: "show", userInfo: info), .show(rule: "swap_pressure"))
    }

    func test_parse_snooze_action() {
        XCTAssertEqual(NotificationResponse.parse(actionIdentifier: "snooze1h", userInfo: info), .snooze(rule: "swap_pressure"))
    }

    func test_parse_default_tap_is_show() {
        XCTAssertEqual(NotificationResponse.parse(actionIdentifier: defaultTap, userInfo: info), .show(rule: "swap_pressure"))
    }

    func test_missing_rule_is_ignored() {
        XCTAssertEqual(NotificationResponse.parse(actionIdentifier: "show", userInfo: [:]), .ignore)
        XCTAssertEqual(NotificationResponse.parse(actionIdentifier: "show", userInfo: ["rule": 3]), .ignore)
    }

    func test_dismiss_and_unknown_actions_are_ignored() {
        let dismiss = "com.apple.UNNotificationDismissActionIdentifier"
        XCTAssertEqual(NotificationResponse.parse(actionIdentifier: dismiss, userInfo: info), .ignore)
        XCTAssertEqual(NotificationResponse.parse(actionIdentifier: "other", userInfo: info), .ignore)
    }
}
