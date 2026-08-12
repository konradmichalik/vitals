import SwiftUI

struct SettingsView: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @AppStorage(CriticalFindingNotifier.storageKey) private var notifyOnCritical = true

    var body: some View {
        Form {
            Toggle("Launch Vitals at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        try LaunchAtLogin.setEnabled(newValue)
                    } catch {
                        // Revert to what's actually registered rather than
                        // showing a toggle state that didn't take effect
                        // (e.g. registration can fail for an ad-hoc-signed
                        // debug build run outside /Applications).
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                }
            Toggle("Notify when a finding becomes critical", isOn: $notifyOnCritical)
                .onChange(of: notifyOnCritical) { _, newValue in
                    if newValue {
                        CriticalFindingNotifier.requestPermission()
                    }
                }
        }
        .padding(20)
        .frame(width: 320)
    }
}
