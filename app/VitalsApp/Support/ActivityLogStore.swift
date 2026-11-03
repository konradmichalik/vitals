import Foundation

struct ActivityEntry: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case event
        case action
    }

    let id: UUID
    let date: Date
    let kind: Kind
    let title: String
    let note: String?
    let severity: Severity?
}

extension ActivityEntry {
    static func action(
        for action: SuggestedAction,
        result: Result<String, ActionRunnerError>,
        at date: Date
    ) -> ActivityEntry {
        var title = ActionConfirmation.make(for: action, culpritLabel: nil).title
        if title.hasSuffix("?") { title.removeLast() }
        var note: String?
        if case .failure(let error) = result { note = error.activityNote }
        return ActivityEntry(id: UUID(), date: date, kind: .action, title: title, note: note, severity: nil)
    }
}

/// Persists the activity log as one JSON file. Callers run it off the main actor.
struct ActivityLogStore: Sendable {
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60
    static let maxEntries = 500

    let url: URL

    init(url: URL = ActivityLogStore.defaultURL) {
        self.url = url
    }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Vitals/activity.json")
    }

    /// Entries are stored oldest first, so the cap keeps the tail.
    static func pruned(_ entries: [ActivityEntry], now: Date) -> [ActivityEntry] {
        let cutoff = now.addingTimeInterval(-maxAge)
        return Array(entries.filter { $0.date >= cutoff }.suffix(maxEntries))
    }

    /// A corrupt file loads as empty, so a bad write can never block launch.
    func load() -> [ActivityEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ActivityEntry].self, from: data)) ?? []
    }

    func append(_ entries: [ActivityEntry], now: Date) {
        let merged = Self.pruned(load() + entries, now: now)
        guard let data = try? JSONEncoder().encode(merged) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }
}
