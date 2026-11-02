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
            return "CPU \(Int((100 - report.system.cpu.idlePercent).rounded()))%"
        }
        if isCritical("memory_pressure") {
            return "Mem \(TileTone.pressureLabel(report.system.memory.pressureLevel))"
        }
        return nil
    }
}
