import Foundation

enum SnoozeDuration {
    case oneHour, today, untilRestart
}

struct Snooze: Codable, Equatable {
    let rule: String
    /// nil for `untilRestart`, which expires through `bootTime` instead.
    let until: Date?
    let bootTime: Date?
}

/// Persists per-finding snoozes in `UserDefaults`, like `MetricHistoryStore`.
struct SnoozeStore {
    static let storageKey = "snoozes"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [Snooze] {
        guard let data = defaults.data(forKey: Self.storageKey),
              // A schema change must not crash the launch; losing snoozes is fine.
              let decoded = try? JSONDecoder().decode([Snooze].self, from: data)
        else {
            return []
        }
        return decoded
    }

    func save(_ snoozes: [Snooze]) {
        guard let data = try? JSONEncoder().encode(snoozes) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    static func isSnoozed(rule: String, snoozes: [Snooze], now: Date, bootTime: Date) -> Bool {
        snoozes.contains { $0.rule == rule && isActive($0, now: now, bootTime: bootTime) }
    }

    static func active(_ snoozes: [Snooze], now: Date, bootTime: Date) -> [Snooze] {
        snoozes.filter { isActive($0, now: now, bootTime: bootTime) }
    }

    static func isActive(_ snooze: Snooze, now: Date, bootTime: Date) -> Bool {
        if let until = snooze.until {
            return now < until
        }
        return snooze.bootTime == bootTime
    }

    static func snooze(
        rule: String, for duration: SnoozeDuration, now: Date, bootTime: Date, calendar: Calendar
    ) -> Snooze {
        switch duration {
        case .oneHour:
            return Snooze(rule: rule, until: now.addingTimeInterval(3600), bootTime: nil)
        case .today:
            let midnight = calendar.nextDate(
                after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime
            )
            return Snooze(rule: rule, until: midnight ?? now.addingTimeInterval(24 * 3600), bootTime: nil)
        case .untilRestart:
            return Snooze(rule: rule, until: nil, bootTime: bootTime)
        }
    }

    /// Kept out of the pure functions so tests pass boot times explicitly.
    static func currentBootTime() -> Date {
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else {
            return Date(timeIntervalSince1970: 0)
        }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec))
    }
}
