import Foundation

/// One-line summaries for the parts of the report that drive rules but
/// had no representation in the UI at all: Time Machine (which one of
/// only two critical rules reacts to), the IDE's ACP agents, and
/// OrbStack. Kept as pure functions so the formatting is testable
/// without building a view, matching `TrafficLight`/`LoadStatus`.
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

    static func ideAgentsLabel(_ agents: [AcpAgent]) -> String? {
        guard !agents.isEmpty else { return nil }

        let orphaned = agents.filter(\.orphaned).count
        guard orphaned > 0 else { return "\(agents.count) agent(s)" }
        return "\(agents.count) agent(s) · \(orphaned) orphaned"
    }

    static func orbstackLabel(_ orbstack: OrbstackProcess?) -> String? {
        guard let orbstack else { return nil }

        let gigabytes = Double(orbstack.rssBytes) / 1024 / 1024 / 1024
        return String(format: "%.0f%% CPU · %.1f GB", orbstack.cpuPercent, gigabytes)
    }
}
