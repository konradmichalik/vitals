import SwiftUI

@main
struct VitalsApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenubarView()
                .environmentObject(appState)
        } label: {
            // Plain SwiftUI shapes (not an SF Symbol `Image`) so macOS
            // doesn't auto-tint everything to monochrome "template" style
            // — that would silently defeat the color-coded severity badge.
            // The mark itself uses `.primary` so it still reads as a
            // normal black/white menu bar icon in both appearances; only
            // the small corner badge carries color.
            ZStack(alignment: .topTrailing) {
                VitalsMark()
                    .fill(.primary, style: FillStyle(eoFill: true))
                    .frame(width: 16, height: 16)
                Circle()
                    .fill(TrafficLight.from(findings: appState.report?.findings ?? []).color)
                    .frame(width: 7, height: 7)
                    .offset(x: 2, y: -2)
            }
            .frame(width: 20, height: 18)
        }
        .menuBarExtraStyle(.window)
    }
}
