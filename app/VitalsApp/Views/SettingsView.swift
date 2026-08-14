import SwiftUI

/// Tabbed layout (General + About) mirrors cc-usage-bar/Spark's Settings
/// window structure — Vitals just doesn't have enough settings yet to
/// justify Spark's full six-tab spread (Menu Bar/Display/Connection/
/// Notifications/Status), so General absorbs everything Spark would
/// split across several of those.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 360, height: 300)
    }
}

struct GeneralTab: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var configError: String?
    @AppStorage(AppNotifier.alertStorageKey) private var notifyOnAlerts = true

    private func openConfiguration() {
        do {
            NSWorkspace.shared.open(try ConfigTemplate.ensureExists())
            configError = nil
        } catch {
            configError = "Couldn't create the config file: \(error.localizedDescription)"
        }
    }

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
            Toggle("Notify on new warnings and critical findings", isOn: $notifyOnAlerts)
                .onChange(of: notifyOnAlerts) { _, newValue in
                    if newValue {
                        AppNotifier.requestPermission()
                    }
                }

            // Thresholds and the rule ignore list live in TOML that the
            // Rust core reads. Mirroring each one as a native control
            // would mean writing that file back out from Swift and
            // destroying the user's own comments, so this opens it
            // instead — seeding a fully commented template on first use.
            LabeledContent("Rules & thresholds") {
                VStack(alignment: .leading, spacing: 4) {
                    Button("Edit ~/.vitals.toml…") { openConfiguration() }
                    if let configError {
                        Text(configError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(20)
    }
}

struct AboutTab: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.green)

            Text("Vitals")
                .font(.title2.weight(.semibold))

            Text("Version \(appVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Vital signs of your local dev stack.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                if let url = URL(string: "https://github.com/konradmichalik/vitals") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("GitHub", systemImage: "link")
            }
            .buttonStyle(.bordered)

            Spacer()

            Text("© 2026 Konrad Michalik")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
