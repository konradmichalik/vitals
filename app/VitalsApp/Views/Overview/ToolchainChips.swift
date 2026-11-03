import SwiftUI

/// One neutral chip per toolchain tab with a short count, opening that tab.
struct ToolchainChips: View {
    let report: VitalsReport
    let onSelect: (ToolTab) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ToolTab.allCases, id: \.self) { tab in
                Button { onSelect(tab) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title(tab))
                            .font(.caption.weight(.medium))
                        Text(status(tab))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title(tab)), \(status(tab))")
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func title(_ tab: ToolTab) -> String {
        switch tab {
        case .ddev: return "DDEV"
        case .docker: return "Docker"
        case .claude: return "Claude"
        case .backup: return "Backup"
        }
    }

    /// The report carries no installed flag per tool, so every chip stays visible.
    private func status(_ tab: ToolTab) -> String {
        switch tab {
        case .ddev: return "\(report.ddev.running.count) running"
        case .docker: return "\(report.docker.containers.count) running"
        case .claude:
            let count = report.processes.claudeSessions.count
            return "\(count) \(count == 1 ? "session" : "sessions")"
        case .backup: return report.timeMachine.running ? "Running" : "Idle"
        }
    }
}
