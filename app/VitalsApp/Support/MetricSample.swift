import Foundation

/// A single point-in-time snapshot of the three metrics shown as
/// sparklines. Pure/testable, unlike `AppState`'s rolling buffer itself
/// (which needs real timer-driven polling to be meaningful).
struct MetricSample: Equatable, Codable {
    let load: Double
    /// Classification at the time this sample was taken (reusing the
    /// same thresholds the metrics card's own "Elevated"/"Critical"
    /// label uses) — carried alongside the raw value so a sparkline can
    /// mark exactly which past points crossed into warn/critical,
    /// without needing to re-derive it from a core count that isn't
    /// otherwise stored per-sample.
    let loadStatus: LoadStatus
    let cpuUsedPercent: Double
    let memoryUsedPercent: Double
    /// Same rationale as `loadStatus`, using macOS's own memory pressure
    /// signal (§7: the real scarcity indicator, not raw percent) rather
    /// than inventing a separate threshold for the sparkline.
    let memoryPressure: PressureLevel
    /// When this sample was taken — the sparkline's X axis is hidden
    /// (kept compact, no room for tick labels), so this is what lets the
    /// hover tooltip and the history-span caption say how far back a
    /// point actually is instead of leaving that entirely unknowable.
    let timestamp: Date

    static func from(report: VitalsReport, timestamp: Date = Date()) -> MetricSample {
        MetricSample(
            load: report.system.load.m1,
            loadStatus: LoadStatus.evaluate(
                load1: report.system.load.m1,
                performanceCores: report.system.cores.performance
            ),
            cpuUsedPercent: 100 - report.system.cpu.idlePercent,
            memoryUsedPercent: Double(report.system.memory.usedPercent),
            memoryPressure: report.system.memory.pressureLevel,
            timestamp: timestamp
        )
    }
}

enum MetricHistory {
    /// Sparklines are meant as an at-a-glance recent trend, not a full
    /// history — capped so `AppState`'s buffer can't grow unbounded over
    /// a long-running session.
    static let maxSamples = 30

    /// How far back a restored sample may reach. History is persisted so
    /// a restart doesn't wipe the trend, but samples from a run that
    /// ended hours ago must not be drawn as if they connected straight to
    /// fresh ones — that would invent a trend across a gap when the app
    /// simply wasn't running.
    static let maxRestoredAge: TimeInterval = 3600

    static func appending(_ sample: MetricSample, to history: [MetricSample]) -> [MetricSample] {
        let updated = history + [sample]
        return updated.suffix(maxSamples).map { $0 }
    }

    static func pruning(
        _ history: [MetricSample],
        olderThan maxAge: TimeInterval,
        now: Date
    ) -> [MetricSample] {
        history.filter { now.timeIntervalSince($0.timestamp) <= maxAge }
    }
}
