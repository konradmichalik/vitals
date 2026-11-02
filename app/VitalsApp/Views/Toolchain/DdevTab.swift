import SwiftUI

struct DdevTab: View {
    let ddev: DdevInfo
    let isRunning: Bool
    let onAction: ActionRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if ddev.projects.isEmpty {
                ToolchainEmptyText(text: "No DDEV projects.")
            } else {
                ToolchainSummaryText(text: ToolchainSummary.ddev(ddev))
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.sorted(ddev.projects), id: \.name) { project in
                        Divider()
                        row(project)
                    }
                }
                if !ddev.running.isEmpty {
                    poweroff
                }
            }
        }
    }

    private func row(_ project: DdevProjectStatus) -> some View {
        ToolchainRow(
            title: project.name,
            detail: project.status.capitalized,
            symbol: Self.symbol(project.status),
            button: Self.action(for: project).map {
                ToolchainButton(action: $0, targetName: project.name, isRunning: isRunning, onAction: onAction)
            }
        )
    }

    private var poweroff: some View {
        let action = SuggestedAction(action: "poweroff", target: nil, label: "Power off all projects", estimate: nil)
        return ToolchainButton(action: action, targetName: "all projects", isRunning: isRunning, onAction: onAction)
    }

    static func sorted(_ projects: [DdevProjectStatus]) -> [DdevProjectStatus] {
        projects.sorted { lhs, rhs in
            let lhsRunning = lhs.status == "running"
            let rhsRunning = rhs.status == "running"
            return lhsRunning != rhsRunning ? lhsRunning : lhs.name < rhs.name
        }
    }

    /// Other states such as "restarting" are in flux, so no action is offered.
    private static func action(for project: DdevProjectStatus) -> SuggestedAction? {
        switch project.status {
        case "running":
            return SuggestedAction(action: "stop_project", target: project.name, label: "Stop", estimate: nil)
        case "stopped", "paused":
            return SuggestedAction(action: "start_project", target: project.name, label: "Start", estimate: nil)
        default:
            return nil
        }
    }

    private static func symbol(_ status: String) -> String {
        switch status {
        case "running": return "play.circle.fill"
        case "paused": return "pause.circle"
        case "stopped": return "stop.circle"
        default: return "questionmark.circle"
        }
    }
}
