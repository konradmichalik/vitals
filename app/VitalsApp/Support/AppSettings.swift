import Foundation

/// The app's own settings, kept in `UserDefaults`. The ones the Rust core
/// needs (idle threshold, protected items) travel to it as overrides on
/// every collect and as flags on every CLI action, so `~/.vitals.toml` is
/// never written back from Swift.
enum AppSettings {
    enum Key {
        static let guardEnabled = "guardEnabled"
        static let guardLevel = "guardLevel"
        static let guardDdev = "guardScopeDdev"
        static let guardAgents = "guardScopeAgents"
        static let guardOrphans = "guardScopeOrphans"
        static let idleMinutes = "idleMinutes"
        static let protected = "protectedItems"
        static let warnLevel = "warnLevel"
        static let cpuMinutes = "cpuSaturatedMinutes"
        static let diskMinutes = "diskBusyMinutes"
        static let quietHours = "quietHours"
        static let breakThrough = "criticalBreaksThrough"
        static let menuBarMode = "menuBarMode"
        static let refreshSeconds = "refreshSeconds"
    }

    static let idleChoices: [Int] = [60, 120, 240, 1440]
    static let refreshChoices: [Int] = [5, 10, 30]

    static func register(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            Key.guardEnabled: false,
            Key.guardLevel: PressureLevel.critical.rawValue,
            Key.guardDdev: true,
            Key.guardAgents: true,
            Key.guardOrphans: true,
            Key.idleMinutes: 120,
            Key.warnLevel: PressureLevel.warn.rawValue,
            Key.cpuMinutes: 5,
            Key.diskMinutes: 10,
            Key.quietHours: false,
            Key.breakThrough: true,
            Key.menuBarMode: MenuBarMode.gaugeAndValue.rawValue,
            Key.refreshSeconds: 10,
        ])
    }

    static func protectedItems(in defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: Key.protected) ?? []
    }

    static func setProtectedItems(_ items: [String], in defaults: UserDefaults = .standard) {
        defaults.set(items, forKey: Key.protected)
    }

    static func idleMinutes(in defaults: UserDefaults = .standard) -> Int {
        max(defaults.integer(forKey: Key.idleMinutes), 1)
    }

    /// What `vitals_collect_with` expects (see `config::Overrides`).
    static func overridesJSON(idleMinutes: Int, protected: [String]) -> String {
        let payload: [String: Any] = ["idleAfterMinutes": idleMinutes, "protected": protected]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else { return "{}" }
        return json
    }

    /// The same overrides as CLI flags, appended to every `--fix` call so
    /// the CLI judges "idle" exactly as the report the user looked at did.
    static func cliArguments(idleMinutes: Int, protected: [String]) -> [String] {
        var args = ["--idle-minutes", String(idleMinutes)]
        if !protected.isEmpty {
            args += ["--protect", protected.joined(separator: ",")]
        }
        return args
    }

    static func guardScopes(ddev: Bool, agents: Bool, orphans: Bool) -> [String] {
        [(ddev, "ddev"), (agents, "agents"), (orphans, "orphans")].filter(\.0).map(\.1)
    }

    /// Quiet hours run from 19:00 to 08:00 local time.
    static func isQuietTime(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= 19 || hour < 8
    }
}

enum MenuBarMode: String, CaseIterable {
    case icon
    case gauge
    case gaugeAndValue

    var label: String {
        switch self {
        case .icon: return "Icon"
        case .gauge: return "Gauge"
        case .gaugeAndValue: return "Gauge + value"
        }
    }
}

extension PressureLevel {
    var rank: Int {
        switch self {
        case .normal: return 0
        case .warn: return 1
        case .critical: return 2
        }
    }

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .warn: return "Warning"
        case .critical: return "Critical"
        }
    }
}
