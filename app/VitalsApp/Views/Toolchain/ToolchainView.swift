import SwiftUI

/// The screen behind a toolchain chip. A tab picker switches the shell's screen, like the metric picker does.
struct ToolchainView: View {
    @EnvironmentObject private var appState: AppState
    let tab: ToolTab
    let onSelect: (ToolTab) -> Void

    @State private var pending: PendingAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Tool", selection: Binding(get: { tab }, set: onSelect)) {
                ForEach(ToolTab.allCases, id: \.self) { Text(Self.title($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if let report = appState.report {
                tabContent(report)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(24)
            }
        }
        .padding(12)
        .confirmingActions($pending)
    }

    @ViewBuilder
    private func tabContent(_ report: VitalsReport) -> some View {
        let isRunning = appState.outcome.isRunning
        let request: ActionRequest = { pending = PendingAction($0, culpritLabel: $1) }
        switch tab {
        case .ddev: DdevTab(ddev: report.ddev, isRunning: isRunning, onAction: request)
        case .docker: DockerTab(docker: report.docker)
        case .claude: ClaudeTab(consumers: report.consumers, isRunning: isRunning, onAction: request)
        case .backup: BackupTab(timeMachine: report.timeMachine, isRunning: isRunning, onAction: request)
        }
    }

    private static func title(_ tab: ToolTab) -> String {
        switch tab {
        case .ddev: return "DDEV"
        case .docker: return "Docker"
        case .claude: return "Claude"
        case .backup: return "Backup"
        }
    }
}
