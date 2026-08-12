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
        .frame(width: 360)
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
        HStack {
            Text("Vitals")
                .font(.headline)
            Spacer()
            if let lastUpdated = appState.lastUpdated {
                Text(lastUpdated, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await appState.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
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
        VStack(alignment: .leading, spacing: 8) {
            metricsSummary(report)
            if report.findings.isEmpty {
                Text("No findings — all vital signs normal.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(report.findings) { finding in
                    FindingRow(finding: finding) { action in
                        pendingAction = PendingAction(action: action)
                    }
                }
            }
        }
        .padding(12)
    }

    private func metricsSummary(_ report: VitalsReport) -> some View {
        let load = report.system.load
        let cores = report.system.cores
        let status = LoadStatus.evaluate(load1: load.m1, performanceCores: cores.performance)

        return VStack(alignment: .leading, spacing: 2) {
            // htop-style single "Load average:" label rather than
            // per-number labels — the 1/5/15m order is well-established
            // and per-number labels just add noise. Color mirrors the
            // rule engine's own load thresholds (§5); weight changes too
            // so severity isn't conveyed by color alone.
            HStack(spacing: 4) {
                Text("Load average:")
                Text(String(format: "%.2f · %.2f · %.2f", load.m1, load.m5, load.m15))
                    .fontWeight(status == .normal ? .regular : .semibold)
                    .foregroundStyle(status.color)
                Text("(\(cores.performance)P/\(cores.efficiency)E)")
                    .foregroundStyle(.tertiary)
            }
            Text("\(report.docker.containers.count) container(s), \(report.ddev.running.count) DDEV project(s) running")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
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
