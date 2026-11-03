import XCTest
@testable import VitalsApp

final class ActivityFilterTests: XCTestCase {
    private func entry(_ kind: ActivityEntry.Kind, at seconds: TimeInterval) -> ActivityEntry {
        ActivityEntry(
            id: UUID(), date: Date(timeIntervalSince1970: seconds), kind: kind, title: "t", note: nil, severity: nil
        )
    }

    private var entries: [ActivityEntry] {
        [entry(.event, at: 1), entry(.action, at: 2), entry(.event, at: 3)]
    }

    func test_actions_filter_keeps_only_actions() {
        XCTAssertEqual(ActivityFilter.actions.apply(entries).map(\.kind), [.action])
    }

    func test_events_filter_keeps_only_events() {
        XCTAssertEqual(ActivityFilter.events.apply(entries).map(\.kind), [.event, .event])
    }

    func test_all_filter_is_newest_first() {
        XCTAssertEqual(ActivityFilter.all.apply(entries).map(\.date.timeIntervalSince1970), [3, 2, 1])
    }

    func test_filters_sort_newest_first() {
        XCTAssertEqual(ActivityFilter.events.apply(entries).map(\.date.timeIntervalSince1970), [3, 1])
    }

    func test_empty_messages_per_filter() {
        XCTAssertEqual(ActivityFilter.all.emptyMessage, "No activity in the last 7 days.")
        XCTAssertEqual(ActivityFilter.actions.emptyMessage, "No actions yet.")
        XCTAssertEqual(ActivityFilter.events.emptyMessage, "No events yet.")
    }
}
