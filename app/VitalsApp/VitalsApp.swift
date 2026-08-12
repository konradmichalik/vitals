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
            // bar icon). Only the badge below needs to stay colored,
            // and it's a plain Shape — those are never auto-templated.
            ZStack(alignment: .topTrailing) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 14, weight: .semibold))
                Circle()
                    .fill(TrafficLight.from(findings: appState.report?.findings ?? []).color)
                    .frame(width: 8, height: 8)
                    .offset(x: 4, y: -4)
            }
            .frame(width: 22, height: 18)
            // The badge's meaning wasn't explained anywhere — hovering
            // now answers "what does this indicate?" directly.
            .help(TrafficLight.tooltip(for: appState.report?.findings ?? []))
        }
        .menuBarExtraStyle(.window)
    }
}
