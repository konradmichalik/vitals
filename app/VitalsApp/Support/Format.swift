import Foundation

/// One place for how numbers read in the UI, so every screen says
/// "2.6 GB" and "3 h" the same way.
enum Format {
    static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    static func megabytesPerSecond(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f MB/s", value) : String(format: "%.0f MB/s", value)
    }

    /// Mirrors `consumers::human_duration` in the core.
    static func duration(_ seconds: UInt64) -> String {
        switch seconds {
        case ..<3600: return "\(max(seconds / 60, 1)) min"
        case ..<(2 * 86400): return "\(seconds / 3600) h"
        default: return "\(seconds / 86400) days"
        }
    }

    /// 24-hour "HH:mm" without a shared formatter: `DateFormatter` is not
    /// `Sendable`, so a static one would not pass strict concurrency.
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
