import SwiftUI

@main
struct VitalsApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenubarView()
                .environmentObject(appState)
        } label: {
            // The custom pulse mark (VitalsMark) turned out unreadable at
            // menu bar size — its cutout details are too fine and just
            // looked like a plain dot. An SF Symbol is the right tool
            // here: it's designed to stay legible this small, and macOS
            // auto-tinting it to monochrome "template" style is exactly
            // what we want for the base glyph (matches every other menu
            // bar icon). Only the badge needs to stay colored, and it's
            // a plain Shape — those are never auto-templated.
            //
            // Side-by-side, not overlaid: a ZStack badge positioned via
            // .offset() outside the icon's own bounds was invisible in
            // practice — NSStatusItem almost certainly clips content to
            // the icon's exact frame, unlike an ordinary SwiftUI window
            // where overflow just stays visible. Placing the dot next to
            // the icon instead means nothing ever needs to render outside
            // the label's natural bounding box.
            HStack(spacing: 3) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 14, weight: .semibold))
                Circle()
                    .fill(TrafficLight.from(findings: appState.report?.findings ?? []).color)
                    .frame(width: 7, height: 7)
            }
            // The badge's meaning wasn't explained anywhere — hovering
            // now answers "what does this indicate?" directly.
            .help(TrafficLight.tooltip(for: appState.report?.findings ?? []))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
