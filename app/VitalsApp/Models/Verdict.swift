import Foundation

/// Mirrors `Verdict` and `Culprit` in core/src/verdict.rs. A nil
/// `severity` means all calm.
struct Verdict: Codable {
    let severity: Severity?
    let headline: String
    let detail: String
    let culprit: Culprit?
    let action: SuggestedAction?
}

struct Culprit: Codable {
    let id: String
    let label: String
    let reason: String
}
