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

extension [Finding] {
    /// Mirrors `pick_finding` in core/src/verdict.rs, because the verdict does not carry its rule.
    var verdictFinding: Finding? {
        let priority: (String) -> Int = { rule in
            switch rule {
            case "load_status": return 3
            case "runaway_processes": return 2
            case "memory_pressure": return 1
            default: return 0
            }
        }
        return filter { $0.severity >= .warn }
            .max { lhs, rhs in
                lhs.severity != rhs.severity ? lhs.severity < rhs.severity : priority(lhs.rule) < priority(rhs.rule)
            }
    }
}
