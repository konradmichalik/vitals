import Foundation

/// Turns two consecutive reports into the activity events between them.
enum ReportDiff {
    /// A missing side yields no events for that source: without a previous report
    /// everything would look new, and the log would start with a false burst.
    static func events(previous: VitalsReport?, current: VitalsReport, at date: Date) -> [ActivityEntry] {
        guard let previous else { return [] }
        return ddevEvents(previous: previous, current: current, at: date)
            + timeMachineEvents(previous: previous, current: current, at: date)
            + pressureEvents(previous: previous, current: current, at: date)
            + alertEvents(previous: previous, current: current, at: date)
    }

    private static func entry(_ title: String, at date: Date, severity: Severity? = nil) -> ActivityEntry {
        ActivityEntry(id: UUID(), date: date, kind: .event, title: title, note: nil, severity: severity)
    }

    private static func ddevEvents(previous: VitalsReport, current: VitalsReport, at date: Date) -> [ActivityEntry] {
        let before = Set(previous.ddev.running)
        let after = Set(current.ddev.running)
        let started = after.subtracting(before).sorted().map { entry("ddev start \($0)", at: date) }
        let stopped = before.subtracting(after).sorted().map { entry("ddev stop \($0)", at: date) }
        return started + stopped
    }

    private static func timeMachineEvents(previous: VitalsReport, current: VitalsReport, at date: Date) -> [ActivityEntry] {
        switch (previous.timeMachine.running, current.timeMachine.running) {
        case (false, true): return [entry("Time Machine began", at: date)]
        case (true, false): return [entry("Time Machine finished", at: date)]
        default: return []
        }
    }

    private static func pressureEvents(previous: VitalsReport, current: VitalsReport, at date: Date) -> [ActivityEntry] {
        let old = previous.system.memory.pressureLevel
        let new = current.system.memory.pressureLevel
        guard old != new else { return [] }
        return [entry("Memory pressure \(old.rawValue) to \(new.rawValue)", at: date)]
    }

    private static func alertEvents(previous: VitalsReport, current: VitalsReport, at date: Date) -> [ActivityEntry] {
        let rules = FindingAlertTransition.newlyAlerting(
            previous: FindingAlertTransition.alertingSeverities(in: previous.findings),
            current: FindingAlertTransition.alertingSeverities(in: current.findings)
        )
        return current.findings
            .filter { rules.contains($0.rule) }
            .map { entry($0.message, at: date, severity: $0.severity) }
    }
}
