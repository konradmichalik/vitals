import SwiftUI

@main
struct VitalsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The status item and its dropdown are managed directly by
        // AppDelegate (see its doc comment) rather than via MenuBarExtra
        // — only the Settings scene still goes through SwiftUI's App
        // lifecycle.
        Settings {
            SettingsView()
        }
    }
}
