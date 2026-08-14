import SwiftUI

/// Time Machine and the IDE's ACP agents were collected, drove rules —
/// `backup_scanning_container_data` is one of only two critical rules —
/// and yet appeared nowhere in the UI, so a user could read "Time Machine
/// is scanning container data" with no way to watch the state it reacted
/// to. Deliberately two plain rows rather than expandable groups: there's
/// one number each worth showing, and the popover is already tall.
struct ServicesSection: View {
    let timeMachine: TimeMachineInfo
    let agents: [AcpAgent]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            row(
                "Time Machine",
                ServiceSummary.timeMachineLabel(timeMachine),
                // Running backups compete for the same disk the
                // containers use, so it's worth drawing the eye.
                color: timeMachine.running ? .orange : .secondary
            )
            if let agentsLabel = ServiceSummary.ideAgentsLabel(agents) {
                row(
                    "IDE agents",
                    agentsLabel,
                    color: agents.contains(where: \.orphaned) ? .orange : .secondary
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "gearshape.2")
                .foregroundStyle(.secondary)
            Text("System services")
                .font(.subheadline.weight(.semibold))
        }
    }

    private func row(_ name: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(name)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(color)
        }
    }
}
