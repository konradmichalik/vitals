import Foundation

/// One-line summaries for the parts of the report that drive rules but
/// had no representation in the UI at all: Time Machine (which one of
/// only two critical rules reacts to). Kept as pure functions so the
/// formatting is testable without building a view, matching `TrafficLight`/`LoadStatus`.
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
