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
}
