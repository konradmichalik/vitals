import Foundation

/// Time Machine status line for the Backup tab, a pure function so the formatting is testable without a view.
enum ServiceSummary {
    /// `locale` is injectable purely so the grouped-thousands formatting
    /// can be asserted against a fixed locale — users still get their own.
    static func timeMachineLabel(
        _ timeMachine: TimeMachineInfo,
        locale: Locale = .current
    ) -> String {
        guard timeMachine.running else { return "Idle" }

        let phase = timeMachine.phase ?? "Running"
        guard let changed = timeMachine.changedItemCount else { return phase }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        let formatted = formatter.string(from: NSNumber(value: changed)) ?? "\(changed)"
        return "\(phase) — \(formatted) changed items"
    }
}
