import SwiftUI

enum Tone: Equatable {
    case neutral, ok, warn, critical

    /// Color appears only at deviation, so a calm overview stays gray.
    var color: Color {
        switch self {
        case .neutral: return .secondary
        case .ok: return .green
        case .warn: return .orange
        case .critical: return .red
        }
    }

    /// Paired with the color so a tile never signals by color alone.
    var symbol: String? {
        switch self {
        case .neutral, .ok: return nil
        case .warn: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
}

enum TileTone {
    static func tone(for kind: MetricKind, report: VitalsReport) -> Tone {
        switch kind {
        case .memory, .swap:
            // Pressure is the real scarcity signal, a high used percent alone is normal on macOS.
            return tone(for: report.system.memory.pressureLevel)
        case .load:
            let status = LoadStatus.evaluate(load1: report.system.load.m1, performanceCores: report.system.cores.performance)
            switch status {
            case .normal: return .neutral
            case .warn: return .warn
            case .critical: return .critical
            }
        case .cpu:
            if report.findings.contains(where: { $0.rule == "load_status" && $0.severity == .critical }) {
                return .critical
            }
            return report.findings.contains(where: { $0.rule == "runaway_processes" }) ? .warn : .neutral
        }
    }

    static func pressureLabel(_ level: PressureLevel) -> String {
        switch level {
        case .normal: return "Normal"
        case .warn: return "High"
        case .critical: return "Critical"
        }
    }

    private static func tone(for level: PressureLevel) -> Tone {
        switch level {
        case .normal: return .neutral
        case .warn: return .warn
        case .critical: return .critical
        }
    }
}
