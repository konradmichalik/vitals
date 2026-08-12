import SwiftUI

struct FindingRow: View {
    let finding: Finding
    let onRun: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                SeverityBadge(severity: finding.severity)
                Text(finding.rule)
                    .font(.subheadline.weight(.medium))
            }
            // Without fixedSize, Text inside this MenuBarExtra .window
            // panel truncates to one line instead of wrapping — cutting
            // off exactly the detail (project names, GB figures) that
            // made the message worth reading in the first place.
            Text(finding.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !finding.actions.isEmpty {
                actionRow
            }
        }
        .padding(.vertical, 4)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            ForEach(finding.actions, id: \.self) { action in
                if ActionRunner.runnableActions.contains(action) {
                    Button(action) { onRun(action) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Text(action)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
