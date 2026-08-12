import SwiftUI

struct MenubarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var pendingAction: PendingAction?
    @State private var lastActionMessage: String?

    private struct PendingAction: Identifiable {
        let action: String
        var id: String { action }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            if let lastActionMessage {
                Divider()
                Text(lastActionMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
            Divider()
            footer
        }
        .frame(width: 380)
        .alert(item: $pendingAction) { pending in
            Alert(
                title: Text("Run “\(pending.action)”?"),
                message: Text("This runs `vitals --fix \(pending.action)`."),
                primaryButton: .destructive(Text("Run")) { runAction(pending.action) },
                secondaryButton: .cancel()
            )
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
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

    /// A single bordered "card" for the at-a-glance numbers — load
    /// average (the one figure worth a bigger, bolder treatment, plus a
    /// progress bar against the same critical threshold the rule engine
    /// uses) and the docker/DDEV counts as a second row, rather than the
    /// counts floating unattached between the card and the findings list.
    /// The background tint alone barely showed up against the window's
    /// own vibrancy material, so a matching-color border makes the
    /// boundary actually visible.
    private func metricsSection(_ report: VitalsReport) -> some View {
        let load = report.system.load
        let cores = report.system.cores
        let status = LoadStatus.evaluate(load1: load.m1, performanceCores: cores.performance)
        let fraction = LoadStatus.progressFraction(load1: load.m1, performanceCores: cores.performance)

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    sectionHeader("gauge.medium", "Load average")
                    Spacer()
                    Text(status.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.color)
                }
                ProgressView(value: fraction)
                    .tint(status.color)
                // htop-style single label rather than per-number labels
                // — the 1/5/15m order is well-established and per-number
                // labels just add noise. The caption below explains what
                // the raw Unix convention actually means — the numbers
                // alone don't.
                Text(String(format: "%.2f · %.2f · %.2f", load.m1, load.m5, load.m15))
                    .font(.callout.weight(.bold))
                    .foregroundStyle(status.color)
                Text(
                    "1/5/15 min avg — processes waiting for a CPU core, " +
                    "relative to \(cores.performance) performance cores"
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                sectionHeader("shippingbox", "Docker & DDEV")
                Text("\(report.docker.containers.count) container(s) · \(report.ddev.running.count) DDEV project(s) running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(status.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(status.color.opacity(0.25), lineWidth: 1)
        )
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
                    ForEach(Array(report.findings.enumerated()), id: \.element.id) { index, finding in
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

    private func runAction(_ action: String) {
        Task.detached(priority: .userInitiated) {
            let result = ActionRunner.run(action: action, target: nil)
            await MainActor.run {
                switch result {
                case .success(let output):
                    lastActionMessage = output.isEmpty ? "Done: \(action)" : output
                case .failure(let error):
                    lastActionMessage = "Failed: \(error)"
                }
            }
            await appState.refresh()
        }
    }
}
