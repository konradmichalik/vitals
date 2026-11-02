import SwiftUI

@main
struct VitalsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The status item and popover are managed by AppDelegate. SwiftUI's App
        // lifecycle still requires one scene, so this one stays empty.
        Settings {
            EmptyView()
        }
        // Without this the empty scene still adds "Settings…" (Cmd+,) and opens a blank window.
        .commands {
            CommandGroup(replacing: .appSettings) {}
        }
    }
}
