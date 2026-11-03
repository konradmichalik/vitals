import Foundation

enum ActivityFilter: CaseIterable {
    case all
    case actions
    case events

    var label: String {
        switch self {
        case .all: return "All"
        case .actions: return "Actions"
        case .events: return "Events"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: return "No activity in the last 7 days."
        case .actions: return "No actions yet."
        case .events: return "No events yet."
        }
    }

    /// The store keeps entries oldest first, the screen reads newest first.
    func apply(_ entries: [ActivityEntry]) -> [ActivityEntry] {
        let kept: [ActivityEntry]
        switch self {
        case .all: kept = entries
        case .actions: kept = entries.filter { $0.kind == .action }
        case .events: kept = entries.filter { $0.kind == .event }
        }
        return kept.sorted { $0.date > $1.date }
    }
}
