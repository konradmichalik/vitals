import SwiftUI

/// The four vital signs shown as tiles and in the history screen.
enum Metric: String, CaseIterable, Identifiable {
    case memory
    case cpu
    case swap
    case disk

    var id: String { rawValue }

    var label: String {
        switch self {
        case .memory: return "Memory"
        case .cpu: return "CPU"
        case .swap: return "Swap"
        case .disk: return "Disk"
        }
    }

    var symbol: String {
        switch self {
        case .memory: return "memorychip"
        case .cpu: return "cpu"
        case .swap: return "arrow.left.arrow.right"
        case .disk: return "internaldrive"
        }
    }

    /// One value per history sample; `nil` where the sample cannot say.
    func values(_ history: [MetricSample]) -> [Double?] {
        switch self {
        case .memory: return history.map { $0.memoryUsedPercent }
        case .cpu: return history.map { $0.cpuUsedPercent }
        case .swap: return history.map { $0.swapUsedBytes.map { Double($0) / 1_073_741_824 } }
        case .disk: return MetricHistory.diskRates(history)
        }
    }

    func format(_ value: Double?) -> (number: String, unit: String) {
        guard let value else { return ("–", "") }
        switch self {
        case .memory, .cpu: return ("\(Int(value.rounded()))", "%")
        case .swap: return (String(format: "%.1f", value), "GB")
        case .disk: return (value < 10 ? String(format: "%.1f", value) : "\(Int(value.rounded()))", "MB/s")
        }
    }

    /// Only the metric that is actually the bottleneck gets a color.
    func tint(report: VitalsReport, summary: HealthSummary?, diskBusy: Bool) -> Color? {
        let pressure = report.system.memory.pressureLevel
        switch self {
        case .memory, .swap:
            return pressure == .normal ? nil : Theme.color(for: pressure)
        case .cpu:
            return summary?.focus == .cpu ? .red : nil
        case .disk:
            return diskBusy ? .orange : nil
        }
    }
}
