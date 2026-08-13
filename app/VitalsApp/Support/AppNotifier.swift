import UserNotifications

/// Posts a system notification — used both for a finding newly entering
/// critical severity, and for the result of a "Run"/"Stop" action
/// (§9: the app's own confirmation already gates the run; the
/// notification is just reliable feedback once it's done, since the
/// dropdown may well be closed by then). Not unit tested: it's a thin
/// pass-through to `UNUserNotificationCenter` with real side effects
/// (actual banners, actual permission prompts), matching
/// `LaunchAtLogin`'s rationale.
enum AppNotifier {
    /// Single source of truth for the `@AppStorage` key shared by
    /// `AppDelegate`, `AppState`, and `SettingsView` — declaring it three
    /// times independently would let a typo in one silently desync it
    /// from the others. Only gates critical-finding notifications; a
    /// user-triggered action's own result always notifies regardless,
    /// since they explicitly asked for that action to run.
    static let criticalFindingStorageKey = "notifyOnCritical"

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func notify(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Reusing a stable identifier means a second notification for
        // the same id (e.g. the same still-critical rule) replaces the
        // first instead of piling up.
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
