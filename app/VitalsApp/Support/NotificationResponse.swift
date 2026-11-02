import Foundation

/// What a tap on a finding banner or one of its buttons should do. Pure so
/// the mapping is testable without a notification center.
enum NotificationResponse: Sendable, Equatable {
    case show(rule: String)
    case snooze(rule: String)
    case ignore

    static let showAction = "show"
    static let snoozeAction = "snooze1h"
    // Same value as UNNotificationDefaultActionIdentifier, kept literal to avoid importing UserNotifications here.
    static let defaultTapAction = "com.apple.UNNotificationDefaultActionIdentifier"

    static func parse(actionIdentifier: String, userInfo: [AnyHashable: Any]) -> NotificationResponse {
        guard let rule = userInfo["rule"] as? String else { return .ignore }
        switch actionIdentifier {
        case showAction, defaultTapAction: return .show(rule: rule)
        case snoozeAction: return .snooze(rule: rule)
        default: return .ignore
        }
    }
}
