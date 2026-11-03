import Foundation

enum QuietHours {
    static let start = 19
    static let end = 8
    static let storageKey = "quietHours"
    static let menubarValueKey = "menubarValue"

    static func isQuiet(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= start || hour < end
    }
}
