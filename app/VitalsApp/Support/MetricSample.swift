import Foundation

/// A single point-in-time snapshot of the three metrics shown as
/// sparklines. Pure/testable, unlike `AppState`'s rolling buffer itself
/// (which needs real timer-driven polling to be meaningful).
struct MetricSample: Equatable {
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

    static func from(report: VitalsReport) -> MetricSample {
        MetricSample(
            load: report.system.load.m1,
            loadStatus: LoadStatus.evaluate(
                load1: report.system.load.m1,
                performanceCores: report.system.cores.performance
            ),
            cpuUsedPercent: 100 - report.system.cpu.idlePercent,
            memoryUsedPercent: Double(report.system.memory.usedPercent),
            memoryPressure: report.system.memory.pressureLevel
        )
    }
}

enum MetricHistory {
    /// Sparklines are meant as an at-a-glance recent trend, not a full
    /// history — capped so `AppState`'s buffer can't grow unbounded over
    /// a long-running session.
    static let maxSamples = 30

    static func appending(_ sample: MetricSample, to history: [MetricSample]) -> [MetricSample] {
        let updated = history + [sample]
        return updated.suffix(maxSamples).map { $0 }
    }
}
