import SwiftUI

struct BackupTab: View {
    let timeMachine: TimeMachineInfo
    let isRunning: Bool
    let onAction: ActionRequest

    private var unexcluded: [TmExclusion] { timeMachine.exclusions.filter { !$0.excluded } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolchainRow(
                title: "Time Machine",
                detail: ServiceSummary.timeMachineLabel(timeMachine),
                symbol: timeMachine.running ? "arrow.triangle.2.circlepath" : "checkmark.circle",
                button: timeMachine.running ? button("stop_backup", label: "Stop backup", target: "Time Machine") : nil
            )
            if !unexcluded.isEmpty {
                exclusions
            }
        }
    }

    private var exclusions: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolchainSummaryText(text: "Not excluded from backups:")
            ForEach(unexcluded, id: \.path) { ToolchainRow(title: $0.path, symbol: "folder") }
            button("add_exclusions", label: "Exclude", target: "listed paths")
        }
    }

    private func button(_ name: String, label: String, target: String) -> ToolchainButton {
        ToolchainButton(
            action: SuggestedAction(action: name, target: nil, label: label, estimate: nil),
            targetName: target, isRunning: isRunning, onAction: onAction
        )
    }
}
