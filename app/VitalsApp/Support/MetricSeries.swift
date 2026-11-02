import Foundation

/// Turns stored samples into the numbers the detail chart plots and formats them for display.
enum MetricSeries {
    static let gib = 1024.0 * 1024.0 * 1024.0

    /// Load is stored raw per sample, so the P-core count has to come from the current report.
    static func values(_ kind: MetricKind, from samples: [MetricSample], performanceCores: UInt32) -> [Double] {
        let cores = Double(max(performanceCores, 1))
        return samples.map { sample in
            switch kind {
            case .cpu: return sample.cpuUsedPercent
            case .memory: return sample.memoryUsedPercent
            case .load: return sample.load / cores
            case .swap: return Double(sample.swapUsedBytes) / gib
            }
        }
    }

    static func format(_ kind: MetricKind, _ value: Double) -> String {
        switch kind {
        case .cpu, .memory: return "\(Int(value.rounded()))%"
        case .load: return String(format: "%.1f×", value)
        case .swap: return String(format: "%.1f GB", value)
        }
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / gib)
    }

    static func ago(from date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        return seconds < 45 ? "just now" : "\(Int((seconds / 60).rounded())) min ago"
    }
}
