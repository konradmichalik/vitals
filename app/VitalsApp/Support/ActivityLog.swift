import Foundation

/// What happened, newest first: actions the user or Guard ran, and
/// pressure changes the app noticed. Incidents are not stored here; they
/// come fresh from the JetsamEvent reports in every collect.
struct ActivityEntry: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case action
        case event
    }

    enum Tone: String, Codable {
        case good
        case neutral
        case warning
        case critical
    }

    var id = UUID()
    let date: Date
    let kind: Kind
    let tone: Tone
    let title: String
    let note: String
}

struct ActivityLogStore {
    static let storageKey = "activityLog"
    static let maxEntries = 200

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [ActivityEntry] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([ActivityEntry].self, from: data)
        else { return [] }
        return decoded
    }

    func save(_ entries: [ActivityEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    static func prepending(_ entry: ActivityEntry, to entries: [ActivityEntry]) -> [ActivityEntry] {
        Array(([entry] + entries).prefix(maxEntries))
    }
}
