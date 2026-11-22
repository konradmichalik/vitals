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
    // Added with the history screen. Optional so history persisted by an
    // older build still decodes.
    var availableBytes: UInt64?
    var swapUsedBytes: UInt64?
    /// Running total from `iostat -I`; a rate needs the previous sample.
    var diskTotalBytes: UInt64?

    static func from(report: VitalsReport, timestamp: Date = Date()) -> MetricSample {
        let memory = report.system.memory
        var sample = MetricSample(
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
        sample.availableBytes = memory.availableBytes
        sample.swapUsedBytes = memory.swapUsedBytes
        sample.diskTotalBytes = report.disk?.totalBytes
        return sample
    }
}

enum MetricHistory {
    /// Sparklines are meant as an at-a-glance recent trend, not a full
    /// history — capped so `AppState`'s buffer can't grow unbounded over
    /// a long-running session.
    /// One hour at the fastest refresh (5 s), the longest range the
    /// history screen offers.
    static let maxSamples = 720

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

    /// MB/s between each sample and the one before it; `nil` where either
    /// sample lacks a disk total, the gap is non-positive, or the total
    /// went backwards (a reboot resets it).
    static func diskRates(_ history: [MetricSample]) -> [Double?] {
        guard !history.isEmpty else { return [] }
        return history.indices.map { index in
            guard index > 0,
                  let now = history[index].diskTotalBytes,
                  let before = history[index - 1].diskTotalBytes,
                  now >= before
            else { return nil }
            let seconds = history[index].timestamp.timeIntervalSince(history[index - 1].timestamp)
            guard seconds > 0 else { return nil }
            return Double(now - before) / 1_048_576 / seconds
        }
    }

    /// At most `count` points for a small sparkline, each the peak of its
    /// stretch of samples: peaks are what a trend line is read for, and a
    /// tile has no room for 360 separate points.
    static func downsampled(_ values: [Double?], to count: Int) -> [Double] {
        guard count > 0, values.count > count else { return values.map { $0 ?? 0 } }
        let size = Int((Double(values.count) / Double(count)).rounded(.up))
        return stride(from: 0, to: values.count, by: size).map { start in
            values[start..<min(start + size, values.count)].compactMap { $0 }.max() ?? 0
        }
    }

    static func pruning(
        _ history: [MetricSample],
        olderThan maxAge: TimeInterval,
        now: Date
    ) -> [MetricSample] {
        history.filter { now.timeIntervalSince($0.timestamp) <= maxAge }
    }
}
