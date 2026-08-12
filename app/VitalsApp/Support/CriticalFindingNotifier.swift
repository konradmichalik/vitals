import UserNotifications

/// Posts a system notification when a finding newly enters critical
/// severity. Not unit tested: it's a thin pass-through to
/// `UNUserNotificationCenter` with real side effects (actual banners,
/// actual permission prompts), matching `LaunchAtLogin`'s rationale.
enum CriticalFindingNotifier {
    /// Single source of truth for the `@AppStorage` key shared by
    /// `AppDelegate`, `AppState`, and `SettingsView` — declaring it three
    /// times independently would let a typo in one silently desync it
    /// from the others.
    static let storageKey = "notifyOnCritical"

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func notify(rule: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Vitals — critical"
        content.body = message
        content.sound = .default

        // Reusing the rule name as the identifier means a second
        // notification for the same still-critical rule replaces the
        // first instead of piling up — moot today since AppState only
        // calls this for newly-critical rules, but cheap to get right.
        let request = UNNotificationRequest(identifier: rule, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
