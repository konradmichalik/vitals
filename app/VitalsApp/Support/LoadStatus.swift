import SwiftUI

/// Colors the live load figure the same way the rule engine judges it
/// (§5's `load_warn_factor`/`load_critical_factor`, defaulting to 1.0×/1.5×
/// performance cores) — an echo of that threshold for a quick glance, not
/// a second source of truth. If `~/.vitals.toml` overrides those factors,
/// the CLI's own findings remain authoritative; this is just a visual cue.
enum LoadStatus: Equatable {
    case normal
    case warn
    case critical

    static let warnFactor = 1.0
    static let criticalFactor = 1.5

    static func evaluate(load1: Double, performanceCores: UInt32) -> LoadStatus {
        guard performanceCores > 0 else { return .normal }
        let ratio = load1 / Double(performanceCores)
        if ratio > criticalFactor { return .critical }
        if ratio > warnFactor { return .warn }
        return .normal
    }

    var color: Color {
        switch self {
        case .normal: return .primary
        case .warn: return .yellow
        case .critical: return .red
        }
    }

    /// A plain-language word alongside the color, so severity isn't
    /// conveyed by color alone.
    var label: String {
        switch self {
        case .normal: return "Normal"
        case .warn: return "Elevated"
        case .critical: return "Critical"
        }
    }
}
