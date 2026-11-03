import Foundation

/// Mirrors `Consumer` in core/src/consumers.rs.
enum ConsumerKind: String, Codable {
    case ddevProject
    case claudeCli
    case app
    case process
    case orbstackOverhead
}

struct Consumer: Codable, Identifiable {
    let id: String
    let kind: ConsumerKind
    let label: String
    let detail: String?
    let cpuPercent: Double
    let memBytes: UInt64
    let children: [ConsumerChild]
    let action: SuggestedAction?
}

struct ConsumerChild: Codable {
    let label: String
    let detail: String?
    let cpuPercent: Double
    let memBytes: UInt64
    let action: SuggestedAction?
}
