import XCTest
@testable import VitalsApp

final class MetricHistoryStoreTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(ageSeconds: TimeInterval, load: Double = 1) -> MetricSample {
        MetricSample(
            load: load,
            loadStatus: .normal,
            cpuUsedPercent: 10,
            memoryUsedPercent: 50,
            memoryPressure: .normal,
            timestamp: reference.addingTimeInterval(-ageSeconds)
        )
    }

    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "vitals.tests.\(name)")!
        defaults.removePersistentDomain(forName: "vitals.tests.\(name)")
        return defaults
    }

    // MARK: - Pruning

    /// Restoring hour-old samples would draw them as if they connected
    /// straight to fresh ones, inventing a trend across a gap when the
    /// app simply wasn't running.
    func testPruningDropsSamplesOlderThanTheMaxAge() {
        let history = [sample(ageSeconds: 7200), sample(ageSeconds: 60)]
        let pruned = MetricHistory.pruning(history, olderThan: 3600, now: reference)
        XCTAssertEqual(pruned.count, 1)
        XCTAssertEqual(pruned.first?.timestamp, reference.addingTimeInterval(-60))
    }

    func testPruningKeepsEverythingWithinTheMaxAge() {
        let history = [sample(ageSeconds: 300), sample(ageSeconds: 60)]
        XCTAssertEqual(MetricHistory.pruning(history, olderThan: 3600, now: reference).count, 2)
    }

    func testPruningPreservesChronologicalOrder() {
        let history = [sample(ageSeconds: 300, load: 1), sample(ageSeconds: 60, load: 2)]
        let pruned = MetricHistory.pruning(history, olderThan: 3600, now: reference)
        XCTAssertEqual(pruned.map(\.load), [1, 2])
    }

    // MARK: - Round trip

    func testLoadReturnsEmptyWhenNothingWasEverSaved() {
        let store = MetricHistoryStore(defaults: makeDefaults())
        XCTAssertTrue(store.load(now: reference).isEmpty)
    }

    func testSavedHistorySurvivesAReload() {
        let defaults = makeDefaults()
        let history = [sample(ageSeconds: 120, load: 3.5)]

        MetricHistoryStore(defaults: defaults).save(history)
        let restored = MetricHistoryStore(defaults: defaults).load(now: reference)

        XCTAssertEqual(restored, history)
    }

    func testLoadDropsStaleSamplesFromAPreviousRun() {
        let defaults = makeDefaults()
        MetricHistoryStore(defaults: defaults).save([sample(ageSeconds: 86_400)])

        XCTAssertTrue(MetricHistoryStore(defaults: defaults).load(now: reference).isEmpty)
    }

    func testLoadReturnsEmptyOnCorruptedData() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: MetricHistoryStore.storageKey)

        XCTAssertTrue(MetricHistoryStore(defaults: defaults).load(now: reference).isEmpty)
    }
}
