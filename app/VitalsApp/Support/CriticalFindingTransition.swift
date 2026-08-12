import Foundation

/// Mirrors cc-usage-bar's "only notify on transition into an elevated
/// state, never while it merely persists" pattern — adapted from a
/// single usage level to Vitals' potentially-*multiple* simultaneous
/// critical findings, so a set of rule names replaces a single enum
/// value as the thing being diff'd between polls.
enum CriticalFindingTransition {
    static func criticalRuleNames(in findings: [Finding]) -> Set<String> {
        Set(findings.filter { $0.severity == .critical }.map(\.rule))
    }

    /// Rule names that are critical now but weren't previously — exactly
    /// what's worth a notification. A finding staying critical across
    /// repeated polls (the common case, since the alert-interval poll is
    /// 10s) must not re-fire every time. Takes the already-computed
    /// current set rather than `[Finding]` so callers that also need
    /// `criticalRuleNames` themselves (AppState does, to update its
    /// tracked state) don't filter the same findings twice.
    static func newlyCritical(previous: Set<String>, current: Set<String>) -> Set<String> {
        current.subtracting(previous)
    }
}
