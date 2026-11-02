import Foundation

/// The optional value next to the menubar icon. Only a critical finding
/// earns the extra width, so a calm menu bar stays icon-only.
enum MenubarLabel {
    static func text(for report: VitalsReport, enabled: Bool) -> String? {
        guard enabled else { return nil }
        func isCritical(_ rule: String) -> Bool {
            report.findings.contains { $0.rule == rule && $0.severity == .critical }
        }
        // Load wins when both fire, matching the verdict precedence.
        if isCritical("load_status") {
            return "CPU \(Int(report.system.cpu.usedPercent.rounded()))%"
        }
        if isCritical("memory_pressure") {
            return "Mem \(TileTone.pressureLabel(report.system.memory.pressureLevel))"
        }
        return nil
    }

    /// The badge's color and shape are invisible to VoiceOver, so the status goes into the label.
    static func accessibilityLabel(findings: [Finding], text: String?) -> String {
        let status: String?
        switch TrafficLight.from(findings: findings) {
        case .green: status = nil
        case .yellow: status = "warning"
        case .red: status = "critical"
        }
        return (["Vitals"] + [status, text].compactMap { $0 }).joined(separator: ", ")
    }
}
