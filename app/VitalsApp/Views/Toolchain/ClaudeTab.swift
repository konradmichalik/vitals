import SwiftUI

struct ClaudeTab: View {
    let consumers: [Consumer]
    let isRunning: Bool
    let onAction: ActionRequest

    var body: some View {
        if let group = consumers.first(where: { $0.kind == .claudeCli }) {
            VStack(alignment: .leading, spacing: 8) {
                ToolchainSummaryText(text: group.detail ?? "")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(group.children.enumerated()), id: \.offset) { _, child in
                        Divider()
                        row(child)
                    }
                }
            }
        } else {
            ToolchainEmptyText(text: "No Claude sessions.")
        }
    }

    private func row(_ child: ConsumerChild) -> some View {
        ToolchainRow(
            title: child.label,
            detail: "\(Int(child.cpuPercent.rounded()))% CPU",
            symbol: "terminal",
            button: child.action.map {
                ToolchainButton(action: $0, targetName: child.label, culpritLabel: child.label, isRunning: isRunning, onAction: onAction)
            }
        )
    }
}
