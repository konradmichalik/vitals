import Foundation

/// Persists the sparkline history so quitting the app (or a reboot)
/// doesn't erase the trend — previously the buffer lived only in
/// `AppState`, so every restart started from a blank chart and the app
/// could never answer "has this been bad for a while, or did it just
/// spike?".
///
/// `UserDefaults` rather than a file in Application Support: the payload
/// is 30 small structs, it needs no migration story of its own, and it
/// keeps the read synchronous enough to happen during `AppState.init`
/// without a loading state.
struct MetricHistoryStore {
    static let storageKey = "metricHistory"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(now: Date = Date()) -> [MetricSample] {
        guard let data = defaults.data(forKey: Self.storageKey),
              // Decoding can fail across a schema change to MetricSample;
              // a blank chart is a fine outcome, a crash on launch is not.
              let decoded = try? JSONDecoder().decode([MetricSample].self, from: data)
        else {
            return []
        }

        return MetricHistory.pruning(decoded, olderThan: MetricHistory.maxRestoredAge, now: now)
    }

    func save(_ history: [MetricSample]) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
