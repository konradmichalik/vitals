import XCTest
@testable import VitalsApp

final class ActivityLogStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func store() -> ActivityLogStore {
        ActivityLogStore(url: directory.appendingPathComponent("activity.json"))
    }

    private func entry(_ title: String, ageSeconds: TimeInterval = 0) -> ActivityEntry {
        ActivityEntry(
            id: UUID(), date: now.addingTimeInterval(-ageSeconds), kind: .event, title: title, note: nil, severity: nil
        )
    }

    func testStoreRoundTripsAndCreatesDirectory() {
        let kept = entry("a")
        store().append([kept], now: now)
        XCTAssertEqual(store().load(), [kept])
    }

    func testStoreDropsEntriesOlderThan7Days() {
        let old = entry("old", ageSeconds: ActivityLogStore.maxAge + 1)
        let fresh = entry("fresh", ageSeconds: ActivityLogStore.maxAge - 1)
        store().append([old, fresh], now: now)
        XCTAssertEqual(store().load().map(\.title), ["fresh"])
    }

    func testStoreCapsAt500() {
        let entries = (0..<510).map { entry("e\($0)") }
        store().append(entries, now: now)
        let loaded = store().load()
        XCTAssertEqual(loaded.count, 500)
        XCTAssertEqual(loaded.first?.title, "e10")
        XCTAssertEqual(loaded.last?.title, "e509")
    }

    func testCorruptFileLoadsEmpty() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("activity.json"))
        XCTAssertEqual(store().load(), [])
    }
}
