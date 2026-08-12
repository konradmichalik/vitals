import SwiftUI

/// The menubar traffic light, derived from the highest-severity firing
/// rule (§5: "not a number. If nothing fires: green").
enum TrafficLight: Equatable {
    case green
    case yellow
    case red

    static func from(findings: [Finding]) -> TrafficLight {
        switch findings.map(\.severity).max() {
        case .critical: return .red
        case .warn: return .yellow
        case .info, nil: return .green
        }
    }

    var color: Color {
        switch self {
        case .green: return .green
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
}
