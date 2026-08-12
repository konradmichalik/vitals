import ServiceManagement

/// Wraps `SMAppService.mainApp` — the modern (macOS 13+) API for an app to
/// register itself as a login item directly, without a separate bundled
/// helper app. Not unit tested: it's a thin pass-through with real side
/// effects on the current user's actual login items, which a test suite
/// should never mutate.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
