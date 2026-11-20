import SwiftUI

struct SettingsScreen: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case guardTab = "Guard"
        case alerts = "Alerts"
        case general = "General"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .guardTab

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch tab {
            case .guardTab: GuardSettings()
            case .alerts: AlertSettings()
            case .general: GeneralSettings()
            }
        }
    }
}

/// A titled card of settings rows.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title)
            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
    }
}

struct SettingsToggle: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .frame(minHeight: 44)
    }
}

struct SettingsPicker<Value: Hashable>: View {
    let title: String
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { index in
                    Text(options[index].1).tag(options[index].0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
        }
        .frame(minHeight: 44)
    }
}

struct GuardSettings: View {
    @AppStorage(AppSettings.Key.guardEnabled) private var enabled = false
    @AppStorage(AppSettings.Key.guardLevel) private var level = PressureLevel.critical.rawValue
    @AppStorage(AppSettings.Key.guardDdev) private var ddev = true
    @AppStorage(AppSettings.Key.guardAgents) private var agents = true
    @AppStorage(AppSettings.Key.guardOrphans) private var orphans = true
    @AppStorage(AppSettings.Key.idleMinutes) private var idleMinutes = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection(title: "Guard") {
                SettingsToggle(title: "Free idle items automatically", subtitle: "Acts on the memory pressure macOS reports", isOn: $enabled)
                Divider()
                SettingsToggle(title: "Stop idle DDEV projects", isOn: $ddev).disabled(!enabled)
                SettingsToggle(title: "End idle agent sessions", isOn: $agents).disabled(!enabled)
                SettingsToggle(title: "Quit orphaned agents", isOn: $orphans).disabled(!enabled)
            }
            Text("Guard never touches protected items or anything still active. Every step lands in Activity.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.horizontal, 2)
            SettingsSection(title: "When") {
                SettingsPicker(
                    title: "Step in at pressure",
                    options: [(PressureLevel.warn.rawValue, "Warning"), (PressureLevel.critical.rawValue, "Critical")],
                    selection: $level
                )
                Divider()
                SettingsPicker(
                    title: "Idle after",
                    options: AppSettings.idleChoices.map { ($0, Format.duration(UInt64($0 * 60))) },
                    selection: $idleMinutes
                )
            }
            ProtectedList()
        }
    }
}

struct ProtectedList: View {
    @EnvironmentObject private var appState: AppState
    @State private var items: [String] = AppSettings.protectedItems()
    @State private var draft = ""

    private struct Entry: Identifiable {
        let value: String
        var id: String { value }
    }

    /// Running projects and session folders not yet protected, offered as
    /// one-click suggestions.
    private var suggestions: [String] {
        let report = appState.report
        let projects = report?.ddev.projects?.filter { $0.status == "running" }.map(\.name) ?? []
        let sessions = report?.processes.claudeSessions.compactMap(\.workingDirectory) ?? []
        return Array((projects + sessions).filter { !items.contains($0) }.prefix(2))
    }

    var body: some View {
        SettingsSection(title: "Never touch") {
            if items.isEmpty {
                Text("Nothing is protected.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }
            ForEach(items.map(Entry.init)) { entry in
                HStack {
                    Text(entry.value).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    RowButton(title: "Remove") { update(items.filter { $0 != entry.value }) }
                }
                .frame(minHeight: 40)
            }
            ForEach(suggestions.map(Entry.init)) { entry in
                Button("Protect \(entry.value)") { update(items + [entry.value]) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.reclaim)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            }
            HStack {
                TextField("Project name or folder", text: $draft)
                    .textFieldStyle(.plain)
                    .onSubmit(add)
                RowButton(title: "Add", action: add).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .frame(minHeight: 40)
        }
    }

    private func add() {
        let value = draft.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !items.contains(value) else { return }
        update(items + [value])
        draft = ""
    }

    private func update(_ new: [String]) {
        items = new
        AppSettings.setProtectedItems(new)
        Task { await appState.refresh() }
    }
}

struct AlertSettings: View {
    @AppStorage(AppNotifier.alertStorageKey) private var notify = true
    @AppStorage(AppSettings.Key.warnLevel) private var warnLevel = PressureLevel.warn.rawValue
    @AppStorage(AppSettings.Key.cpuMinutes) private var cpuMinutes = 5
    @AppStorage(AppSettings.Key.diskMinutes) private var diskMinutes = 10
    @AppStorage(AppSettings.Key.quietHours) private var quietHours = false
    @AppStorage(AppSettings.Key.breakThrough) private var breakThrough = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection(title: "Warn me") {
                SettingsToggle(title: "Warn me early", subtitle: "With a button that frees idle items", isOn: $notify)
                    .onChange(of: notify) { _, newValue in
                        if newValue { AppNotifier.requestPermission() }
                    }
                Divider()
                SettingsPicker(
                    title: "Memory pressure at",
                    options: [(PressureLevel.warn.rawValue, "Warning"), (PressureLevel.critical.rawValue, "Critical")],
                    selection: $warnLevel
                )
                Divider()
                Stepper("CPU above 90% for \(cpuMinutes) min", value: $cpuMinutes, in: 1...30)
                    .font(.system(size: 13, weight: .medium)).frame(minHeight: 44)
                Divider()
                Stepper("Disk above 150 MB/s for \(diskMinutes) min", value: $diskMinutes, in: 5...60, step: 5)
                    .font(.system(size: 13, weight: .medium)).frame(minHeight: 44)
            }
            .disabled(!notify)
            SettingsSection(title: "Quiet hours") {
                SettingsToggle(title: "No banners 19:00 to 08:00", subtitle: "Guard keeps working", isOn: $quietHours)
                Divider()
                SettingsToggle(title: "Critical alerts break through", isOn: $breakThrough).disabled(!quietHours)
            }
        }
    }
}

struct GeneralSettings: View {
    @AppStorage(AppSettings.Key.menuBarMode) private var menuBarMode = MenuBarMode.gaugeAndValue.rawValue
    @AppStorage(AppSettings.Key.refreshSeconds) private var refreshSeconds = 10
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var configError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection(title: "Menu bar") {
                SettingsPicker(
                    title: "Show",
                    options: MenuBarMode.allCases.map { ($0.rawValue, $0.label) },
                    selection: $menuBarMode
                )
            }
            SettingsSection(title: "Behavior") {
                SettingsPicker(
                    title: "Refresh when busy",
                    options: AppSettings.refreshChoices.map { ($0, "\($0) s") },
                    selection: $refreshSeconds
                )
                Divider()
                SettingsToggle(title: "Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            try LaunchAtLogin.setEnabled(newValue)
                        } catch {
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
            }
            footer
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Thresholds and rules: ~/.vitals.toml").font(.system(size: 11.5)).foregroundStyle(.secondary)
                Spacer()
                RowButton(title: "Open config") { openConfiguration() }
                RowButton(title: "Quit") { NSApplication.shared.terminate(nil) }
            }
            if let configError {
                Text(configError).font(.caption).foregroundStyle(.red)
            }
        }
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
