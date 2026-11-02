import XCTest
@testable import VitalsApp

final class SnoozeStoreTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return calendar
    }

    private let boot = Date(timeIntervalSince1970: 1_800_000_000)

    private func date(hour: Int, minute: Int = 0, day: Int = 2) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? Date()
    }

    func test_one_hour_snooze_expires() {
        let now = date(hour: 10)
        let snooze = SnoozeStore.snooze(rule: "load", for: .oneHour, now: now, bootTime: boot, calendar: calendar)
        XCTAssertTrue(SnoozeStore.isSnoozed(rule: "load", snoozes: [snooze], now: now.addingTimeInterval(3599), bootTime: boot))
        XCTAssertFalse(SnoozeStore.isSnoozed(rule: "load", snoozes: [snooze], now: now.addingTimeInterval(3600), bootTime: boot))
        XCTAssertFalse(SnoozeStore.isSnoozed(rule: "swap", snoozes: [snooze], now: now, bootTime: boot))
    }

    func test_today_snooze_ends_at_midnight() {
        let now = date(hour: 22, minute: 30)
        let snooze = SnoozeStore.snooze(rule: "load", for: .today, now: now, bootTime: boot, calendar: calendar)
        XCTAssertEqual(snooze.until, date(hour: 0, day: 3))
        XCTAssertTrue(SnoozeStore.isSnoozed(rule: "load", snoozes: [snooze], now: date(hour: 23, minute: 59), bootTime: boot))
        XCTAssertFalse(SnoozeStore.isSnoozed(rule: "load", snoozes: [snooze], now: date(hour: 0, day: 3), bootTime: boot))
    }

    func test_until_restart_expires_on_new_boot_time() {
        let now = date(hour: 10)
        let snooze = SnoozeStore.snooze(rule: "load", for: .untilRestart, now: now, bootTime: boot, calendar: calendar)
        XCTAssertNil(snooze.until)
        XCTAssertTrue(SnoozeStore.isSnoozed(rule: "load", snoozes: [snooze], now: now.addingTimeInterval(86_400 * 3), bootTime: boot))
        XCTAssertFalse(
            SnoozeStore.isSnoozed(rule: "load", snoozes: [snooze], now: now, bootTime: boot.addingTimeInterval(500))
        )
    }

    func test_store_round_trips_snoozes() {
        let name = "vitals.tests.snoozes"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        let store = SnoozeStore(defaults: defaults)
        let snooze = Snooze(rule: "load", until: nil, bootTime: boot)
        store.save([snooze])
        XCTAssertEqual(store.load(), [snooze])
    }
}
