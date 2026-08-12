import SwiftUI

@main
struct VitalsApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenubarView()
                .environmentObject(appState)
        } label: {
            Circle()
                .fill(TrafficLight.from(findings: appState.report?.findings ?? []).color)
                .frame(width: 10, height: 10)
        }
        .menuBarExtraStyle(.window)
    }
}
