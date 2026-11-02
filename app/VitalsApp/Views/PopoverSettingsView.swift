import SwiftUI

struct PopoverSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var configError: String?
    @AppStorage(AppNotifier.alertStorageKey) private var notifyOnAlerts = true
    @AppStorage(QuietHours.storageKey) private var quietHours = false
    @AppStorage(QuietHours.menubarValueKey) private var menubarValue = true

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            generalSection
            notificationsSection
            snoozedSection
            configSection
            Text("Vitals \(appVersion)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(icon: "gearshape", title: "General")
            Toggle("Launch Vitals at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        try LaunchAtLogin.setEnabled(newValue)
                    } catch {
                        // Registration can fail for an ad-hoc-signed build run outside /Applications.
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                }
            Toggle("Show value in menu bar", isOn: $menubarValue)
            subtitle("Only while something is critical")
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(icon: "bell", title: "Notifications")
            Toggle("Notify on new warnings and critical findings", isOn: $notifyOnAlerts)
                .onChange(of: notifyOnAlerts) { _, newValue in
                    if newValue {
                        AppNotifier.requestPermission()
                    }
                }
            Toggle("Quiet hours", isOn: $quietHours)
            subtitle("No banners 19:00 to 08:00")
        }
    }

    private var snoozedSection: some View {
        // Expired snoozes are only pruned on the next refresh, so they are filtered here as well.
        let snoozes = SnoozeStore.active(appState.snoozes, now: Date(), bootTime: SnoozeStore.currentBootTime())
        return VStack(alignment: .leading, spacing: 6) {
            SectionHeader(icon: "bell.slash", title: "Snoozed findings")
            if snoozes.isEmpty {
                subtitle("Nothing snoozed.")
            }
            ForEach(snoozes, id: \.rule) { snooze in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(RuleTitle.title(for: snooze.rule)).font(.callout)
                        subtitle(endText(for: snooze))
                    }
                    Spacer()
                    Button("Unsnooze") { appState.unsnooze(rule: snooze.rule) }
                        .accessibilityLabel("Unsnooze \(RuleTitle.title(for: snooze.rule))")
                }
            }
        }
    }

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(icon: "doc.text", title: "Config")
            // Thresholds live in TOML read by the Rust core. Writing it back from Swift
            // would destroy the user's comments, so the file is opened, seeded if missing.
            Button("Open ~/.vitals.toml") { openConfiguration() }
            if let configError {
                Text(configError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func subtitle(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func endText(for snooze: Snooze) -> String {
        guard let until = snooze.until else { return "Until restart" }
        return "Until \(until.formatted(date: .omitted, time: .shortened))"
    }

    private func openConfiguration() {
        do {
            NSWorkspace.shared.open(try ConfigTemplate.ensureExists())
            configError = nil
        } catch {
            configError = "Couldn't create the config file: \(error.localizedDescription)"
        }
    }
}
