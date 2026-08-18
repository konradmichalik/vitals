import Foundation

/// Mirrors cc-usage-bar's "only notify on transition into an elevated
/// state, never while it merely persists" pattern — adapted from a
/// single usage level to Vitals' potentially-*multiple* simultaneous
/// findings.
///
/// Tracks a severity per rule rather than plain set membership: warn is
/// worth notifying about (it's the stage where steering back is still
/// cheap), but a rule that later escalates warn → critical would already
/// be in a membership-only set and so would never fire a second, louder
/// notification. Info stays silent — it's advisory, not something to
/// interrupt for.
enum FindingAlertTransition {
    static func alertingSeverities(in findings: [Finding]) -> [String: Severity] {
        findings.reduce(into: [:]) { result, finding in
            guard finding.severity >= .warn else { return }
            result[finding.rule] = finding.severity
        }
    }

    /// Rules that just reached an alerting severity, or escalated beyond
    /// the one they were last seen at. A finding holding steady across
    /// the 10s alert-interval poll must not re-fire every time.
    static func newlyAlerting(
        previous: [String: Severity],
        current: [String: Severity]
    ) -> Set<String> {
        Set(
            current
                .filter { rule, severity in
                    guard let previousSeverity = previous[rule] else { return true }
                    return severity > previousSeverity
                }
                .keys
        )
    }

    /// Guards against a rule flapping right at its threshold (memory
    /// pressure hovering at the edge of "warn") re-firing a notification
    /// every time it crosses back over. `newlyAlerting` alone can't catch
    /// this: dropping below `.warn` removes the rule from `current`
    /// entirely, so its next crossing looks like a brand new alert rather
    /// than a repeat of one just seen moments ago.
    static func shouldNotify(
        rule: String,
        now: Date,
        lastNotifiedAt: [String: Date],
        cooldown: TimeInterval
    ) -> Bool {
        guard let last = lastNotifiedAt[rule] else { return true }
        return now.timeIntervalSince(last) >= cooldown
    }
}
