import Foundation

/// Decides when Guard frees idle items on its own. Pure, so the rules are
/// testable: only at or above the configured macOS pressure level, only
/// when something idle is there to free, and at most once per cooldown so
/// a pressure level hovering at the edge cannot loop.
enum GuardPolicy {
    static let cooldown: TimeInterval = 5 * 60

    struct Input {
        let enabled: Bool
        let pressure: PressureLevel
        let threshold: PressureLevel
        let idleBytes: UInt64
        let scopes: [String]
    }

    static func shouldRun(_ input: Input, lastRun: Date?, now: Date) -> Bool {
        guard input.enabled,
              !input.scopes.isEmpty,
              input.idleBytes > 0,
              input.pressure != .normal,
              input.pressure.rank >= input.threshold.rank
        else { return false }
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= cooldown
    }
}

/// Whether one metric has stayed above a limit for a whole window, from
/// the newest sample backwards. Used for the "CPU saturated for N min"
/// and "disk busy for N min" warnings, which macOS does not report itself.
enum SustainedCheck {
    struct Point {
        let date: Date
        let value: Double?
    }

    /// Samples further apart than this mean the app was not running or
    /// the Mac was asleep, so the stretch in between was never observed.
    static let maxGap: TimeInterval = 120

    static func isSustained(_ points: [Point], above limit: Double, for window: TimeInterval, now: Date) -> Bool {
        let recent = points.filter { now.timeIntervalSince($0.date) <= window }
        guard let oldest = recent.first?.date, now.timeIntervalSince(oldest) >= window * 0.9 else {
            return false
        }
        let dates = recent.map(\.date) + [now]
        let observedContinuously = zip(dates, dates.dropFirst()).allSatisfy { $1.timeIntervalSince($0) <= maxGap }
        return observedContinuously && recent.allSatisfy { ($0.value ?? 0) >= limit }
    }
}
