import SwiftUI

/// The menubar traffic light, derived from the highest-severity firing
/// rule (§5: "not a number. If nothing fires: green"). Info-only findings
/// count as green too — there's nothing to act on, and each one still
/// shows its own blue `info` badge in the findings list (`SeverityBadge`),
/// so the detail isn't lost. Only warn/critical actually escalate the
/// overall badge away from green.
enum TrafficLight: Equatable {
    case green
    case yellow
    case red

    static func from(findings: [Finding]) -> TrafficLight {
        guard let highest = findings.map(\.severity).max() else { return .green }
        switch highest {
        case .critical: return .red
        case .warn: return .yellow
        case .info: return .green
        }
    }

    var color: Color {
        switch self {
        case .green: return .green
        // Same contrast fix as LoadStatus: plain yellow is illegible as
        // text (the status pill) and washes out as a small menu bar dot.
        case .yellow: return .orange
        case .red: return .red
        }
    }

    /// The badge dot's meaning wasn't explained anywhere — this becomes
    /// the menu bar icon's hover tooltip, so the answer is discoverable
    /// in the UI itself, not just in a chat message.
    static func tooltip(for findings: [Finding]) -> String {
        guard !findings.isEmpty else { return "Vitals — all clear" }

        let highest: String
        switch findings.map(\.severity).max() {
        case .critical: highest = "critical"
        case .warn: highest = "warning"
        case .info, nil: highest = "info"
        }

        return "Vitals — \(findings.count) finding(s), highest: \(highest)"
    }

    /// A short header pill (next to "Vitals" in the dropdown title,
    /// mirroring Spark's plan-name pill next to its app name).
    static func statusLabel(for findings: [Finding]) -> String {
        guard !findings.isEmpty else { return "All clear" }
        return "\(findings.count) finding\(findings.count == 1 ? "" : "s")"
    }
}
