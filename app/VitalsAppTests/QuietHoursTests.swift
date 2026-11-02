import XCTest
@testable import VitalsApp

final class QuietHoursTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return calendar
    }

    private func date(hour: Int) -> Date {
        let components = DateComponents(year: 2026, month: 11, day: 2, hour: hour, minute: 30)
        return calendar.date(from: components) ?? Date()
    }

    func test_quiet_at_23_and_7_not_at_8_or_18() {
        XCTAssertTrue(QuietHours.isQuiet(date(hour: 23), calendar: calendar))
        XCTAssertTrue(QuietHours.isQuiet(date(hour: 7), calendar: calendar))
        XCTAssertTrue(QuietHours.isQuiet(date(hour: 19), calendar: calendar))
        XCTAssertFalse(QuietHours.isQuiet(date(hour: 8), calendar: calendar))
        XCTAssertFalse(QuietHours.isQuiet(date(hour: 18), calendar: calendar))
    }
}
