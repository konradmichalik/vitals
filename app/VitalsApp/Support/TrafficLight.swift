import SwiftUI

/// The menubar traffic light, derived from the highest-severity firing
/// rule (§5: "not a number. If nothing fires: green"). Green is reserved
/// for that literal case — zero findings. An info-only finding still
/// gets its own color (blue, matching `SeverityBadge`'s `.info` color in
/// the dropdown) rather than being folded into green, which would claim
/// "all clear" while the dropdown shows something real underneath it.
enum TrafficLight: Equatable {
    case green
    case blue
    case yellow
    case red

    static func from(findings: [Finding]) -> TrafficLight {
        guard let highest = findings.map(\.severity).max() else { return .green }
        switch highest {
        case .critical: return .red
        case .warn: return .yellow
        case .info: return .blue
        }
    }

    var color: Color {
        switch self {
        case .green: return .green
        case .blue: return .blue
        case .yellow: return .yellow
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
