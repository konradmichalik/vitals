import SwiftUI

struct MenubarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var pendingAction: PendingAction?

    private struct PendingAction: Identifiable {
        let action: String
        var target: String?
        var id: String { target.map { "\(action)-\($0)" } ?? action }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 380)
        .alert(item: $pendingAction) { pending in
            let command = pending.target.map { "\(pending.action) --target \($0)" } ?? pending.action
            return Alert(
                title: Text("Run “\(pending.action)”?"),
                message: Text("This runs `vitals --fix \(command)`."),
                primaryButton: .destructive(Text("Run")) { runAction(pending.action, target: pending.target) },
                secondaryButton: .cancel()
            )
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image("VitalsIcon")
                .resizable()
                .renderingMode(.template)
                .frame(width: 16, height: 16)
                .foregroundStyle(.secondary)
            Text("Vitals")
                .font(.headline)
            if let report = appState.report {
                statusPill(report.findings)
            }
            Spacer()
            // MenuBarExtra apps have no app menu of their own, so there's
            // no automatic Cmd+, path to Settings the way a normal app
            // gets one for free — SettingsLink is the explicit opener.
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    /// Mirrors a plan/status pill next to an app's name (a pattern several
    /// menu bar apps use) — an at-a-glance summary before you even open
    /// the sections below.
    private func statusPill(_ findings: [Finding]) -> some View {
        let light = TrafficLight.from(findings: findings)
        return Text(TrafficLight.statusLabel(for: findings))
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(light.color.opacity(0.15))
            .foregroundStyle(light.color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var content: some View {
        if let error = appState.lastError {
            Text(message(for: error))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(12)
        } else if let report = appState.report {
            reportView(report)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(24)
        }
    }

    private func message(for error: VitalsCollectError) -> String {
        switch error {
        case .nullPointer, .invalidUTF8, .malformed:
            return "vitals-ffi returned an unexpected response."
        case .reported(let message):
            return message
        }
    }

    private func reportView(_ report: VitalsReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            metricsSection(report)
            findingsSection(report)
        }
        .padding(12)
    }

    private func sectionHeader(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
    }

    /// Two bordered "cards" rather than one: the load card's tint reflects
    /// `LoadStatus`, which only ever evaluates load average — wrapping
    /// CPU/RAM and the DDEV list in that same colored border implied they
    /// shared that severity too, when they've got no relation to it at
    /// all. The second card groups them under a neutral, severity-free
    /// border instead.
    private func metricsSection(_ report: VitalsReport) -> some View {
        let status = LoadStatus.evaluate(load1: report.system.load.m1, performanceCores: report.system.cores.performance)

        return VStack(alignment: .leading, spacing: 10) {
            card(color: status.color) {
                loadSection(report, status: status)
            }

            card(color: .secondary) {
                cpuMemorySection(report)

                Divider()

                DdevProjectsSection(report: report) { project in
                    pendingAction = PendingAction(action: "stop_project", target: project)
                }

                if !report.processes.claudeSessions.isEmpty {
                    Divider()
                    ClaudeSessionsSection(sessions: report.processes.claudeSessions)
                }
            }
        }
    }

    /// The background tint alone barely showed up against the window's
    /// own vibrancy material, so a matching-color border makes the
    /// boundary actually visible.
    private func card(color: Color, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(10)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color.opacity(0.25), lineWidth: 1)
        )
    }

    private func loadSection(_ report: VitalsReport, status: LoadStatus) -> some View {
        let load = report.system.load
        let cores = report.system.cores
        let fraction = LoadStatus.progressFraction(load1: load.m1, performanceCores: cores.performance)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                sectionHeader("gauge.medium", "Load average")
                Spacer()
                Text(status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.color)
            }
            ProgressView(value: fraction)
                .tint(status.color)
            // htop-style single label rather than per-number labels — the
            // 1/5/15m order is well-established and per-number labels
            // just add noise. The caption below explains what the raw
            // Unix convention actually means — the numbers alone don't.
            Text(String(format: "%.2f · %.2f · %.2f", load.m1, load.m5, load.m15))
                .font(.callout.weight(.bold))
                .foregroundStyle(status.color)
            Sparkline(values: appState.history.map(\.load), color: status.color) { index in
                let sample = appState.history[index]
                return "\(String(format: "%.2f", sample.load)) · \(sample.loadStatus.label) · \(relativeTime(sample.timestamp))"
            }
            Text(
                "1/5/15 min avg — processes waiting for a CPU core, " +
                "relative to \(cores.performance) performance cores"
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            TopProcessesSection(processes: report.processes.topByCpu) { pid in
                pendingAction = PendingAction(action: "kill_session", target: String(pid))
            }
        }
    }

    private func cpuMemorySection(_ report: VitalsReport) -> some View {
        let cpuUsedPercent = Int((100 - report.system.cpu.idlePercent).rounded())
        let memColor = memoryColor(report.system.memory.pressureLevel)

        return VStack(alignment: .leading, spacing: 6) {
            sectionHeader("cpu", "CPU & Memory")
            HStack {
                Text("\(cpuUsedPercent)% CPU")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("· \(report.system.memory.usedPercent)% RAM used")
                    .font(.caption)
                    .foregroundStyle(memColor)
            }
            DualSparkline(
                primaryValues: appState.history.map(\.cpuUsedPercent),
                primaryColor: .secondary,
                secondaryValues: appState.history.map(\.memoryUsedPercent),
                secondaryColor: memColor
            ) { index in
                let sample = appState.history[index]
                return "\(Int(sample.cpuUsedPercent))% CPU · \(Int(sample.memoryUsedPercent))% RAM "
                    + "(\(sample.memoryPressure.rawValue)) · \(relativeTime(sample.timestamp))"
            }
            if let caption = historySpanCaption(appState.history) {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Sparklines hide their X axis to stay compact, so without this
    /// there'd be no way to tell whether the trend covers the last 5
    /// minutes or the last 15 — it varies with `AppState`'s adaptive poll
    /// interval (§4: 30s green, 10s once something's firing).
    private static let relativeTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private func relativeTime(_ date: Date) -> String {
        Self.relativeTimeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func historySpanCaption(_ history: [MetricSample]) -> String? {
        guard let oldest = history.first?.timestamp else { return nil }
        let seconds = Date().timeIntervalSince(oldest)
        guard seconds >= 30 else { return nil }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        guard let formatted = formatter.string(from: seconds) else { return nil }
        return "Trend: last ~\(formatted)"
    }

    /// Mirrors `LoadStatus`/`TrafficLight`'s color language for the
    /// warn/critical escalation, but `.normal` gets its own blue (not
    /// `.secondary`) — the CPU line right next to it in the combined
    /// sparkline is already `.secondary`, and both being gray made the
    /// two lines indistinguishable whenever memory pressure was normal.
    private func memoryColor(_ level: PressureLevel) -> Color {
        switch level {
        case .normal: return .blue
        case .warn: return .orange
        case .critical: return .red
        }
    }

    @ViewBuilder
    private func findingsSection(_ report: VitalsReport) -> some View {
        if report.findings.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("All vital signs normal.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("exclamationmark.triangle", "Findings")
                // A Divider between rows (not around the whole group) so
                // the list reads as one connected block instead of
                // findings running into each other with only padding
                // between them.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(report.findings.sortedBySeverity().enumerated()), id: \.element.id) { index, finding in
                        if index > 0 {
                            Divider()
                        }
                        FindingRow(finding: finding) { action in
                            pendingAction = PendingAction(action: action)
                        }
                    }
                }
            }
        }
    }

    /// Mirrors a common menu bar app footer pattern: refresh + "updated
    /// Xs/m ago" on the left (so it's clear the data is live, not stale),
    /// quit on the right.
    private var footer: some View {
        HStack {
            Button {
                Task { await appState.refresh() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    if let lastUpdated = appState.lastUpdated {
                        Text("Updated ").font(.caption) + Text(lastUpdated, style: .relative).font(.caption)
                    } else {
                        Text("Updating…").font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quit Vitals")
        }
        .padding(12)
    }

    private func runAction(_ action: String, target: String? = nil) {
        Task.detached(priority: .userInitiated) {
            let result = ActionRunner.run(action: action, target: target)
            let message: String
            switch result {
            case .success(let output):
                message = output.isEmpty ? "Done: \(action)" : output
            case .failure(let error):
                message = "Failed: \(error)"
            }
            // A system notification rather than inline text in the
            // dropdown — actions run detached and the dropdown is very
            // likely closed by the time a `stop_project`/similar action
            // actually finishes, so an inline result alone would go
            // unseen.
            AppNotifier.notify(id: "action-\(action)", title: "Vitals", body: message)
            await appState.refresh()
        }
    }
}
