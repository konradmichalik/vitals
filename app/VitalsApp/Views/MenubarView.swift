import SwiftUI

/// The overview screen. Every action offered on it runs through the shared `.confirmingActions` alert.
struct MenubarView: View {
    @EnvironmentObject private var appState: AppState
    let navigate: (PopoverScreen) -> Void

    @State private var pending: PendingAction?

    var body: some View {
        content.confirmingActions($pending)
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

    private func reportView(_ report: VitalsReport) -> some View {
        let isRunning = appState.outcome.isRunning
        return VStack(alignment: .leading, spacing: 12) {
            VerdictHero(
                verdict: report.verdict,
                focus: VerdictHero.focus(for: report.findings),
                outcome: appState.outcome,
                onAction: request,
                onWhy: { navigate(.detail($0)) }
            )
            MetricTiles(report: report, history: appState.history) { navigate(.detail($0)) }
            FindingsList(
                findings: appState.visibleFindings,
                reportHasFindings: !report.findings.isEmpty,
                isRunning: isRunning,
                onAction: { request($0, culpritLabel: nil) },
                onSnooze: { appState.snooze(rule: $0, for: $1) }
            )
            ConsumersList(
                consumers: report.consumers,
                culpritID: report.verdict.culprit?.id,
                defaultSort: ConsumerSort.defaultSort(for: report.findings),
                isRunning: isRunning,
                onAction: request
            )
            ToolchainChips(report: report) { navigate(.toolchain($0)) }
        }
        .padding(12)
    }

    private func request(_ action: SuggestedAction, culpritLabel: String?) {
        pending = PendingAction(action, culpritLabel: culpritLabel)
    }

    private func message(for error: VitalsCollectError) -> String {
        switch error {
        case .nullPointer, .invalidUTF8, .malformed:
            return "vitals-ffi returned an unexpected response."
        case .reported(let message):
            return message
        }
    }
}
