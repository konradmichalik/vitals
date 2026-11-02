import SwiftUI

/// The rule findings not covered by a snooze, each with its first runnable action and a snooze menu.
struct FindingsList: View {
    let findings: [Finding]
    let reportHasFindings: Bool
    let isRunning: Bool
    let onAction: (SuggestedAction) -> Void
    let onSnooze: (String, SnoozeDuration) -> Void

    var body: some View {
        if findings.isEmpty && reportHasFindings {
            // The pill still reflects snoozed findings, so "normal" here would contradict it.
            emptyState("All findings snoozed.", symbol: "bell.slash")
        } else if findings.isEmpty {
            emptyState("All vital signs normal.", symbol: "checkmark.circle")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(icon: "exclamationmark.triangle", title: "Findings")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(findings.sortedBySeverity().enumerated()), id: \.element.id) { index, finding in
                        if index > 0 {
                            Divider()
                        }
                        row(finding)
                    }
                }
            }
        }
    }

    private func emptyState(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private func row(_ finding: Finding) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                SeverityBadge(severity: finding.severity)
                Text(finding.message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if let action = Self.primaryAction(for: finding) {
                Button(action.label) { onAction(action) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRunning)
            }
            snoozeMenu(finding)
        }
        .padding(.vertical, 6)
    }

    private func snoozeMenu(_ finding: Finding) -> some View {
        Menu {
            Button("Snooze for 1 hour") { onSnooze(finding.rule, .oneHour) }
            Button("Snooze for today") { onSnooze(finding.rule, .today) }
            Button("Snooze until restart") { onSnooze(finding.rule, .untilRestart) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Snooze options")
        .help("Snooze options")
    }

    /// Findings name actions without a target, so only the target-less ones can run from here.
    static func primaryAction(for finding: Finding) -> SuggestedAction? {
        guard let name = finding.actions.first else { return nil }
        let action = SuggestedAction(action: name, target: nil, label: ActionConfirmation.buttonLabel(for: name), estimate: nil)
        return ActionRunner.isRunnable(action) ? action : nil
    }
}
