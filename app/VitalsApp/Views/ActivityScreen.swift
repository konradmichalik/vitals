import SwiftUI

struct ActivityScreen: View {
    @EnvironmentObject private var appState: AppState
    let report: VitalsReport
    let openIncident: (Incident) -> Void

    private var incidents: [Incident] { report.incidentList }

    /// Findings the overview already covers through the summary or a
    /// quick win are left out here.
    private static let coveredRules: Set<String> = [
        "memory_pressure", "runaway_processes", "orphaned_acp_agents",
        "backup_paths_not_excluded", "backup_scanning_container_data",
    ]

    private var findings: [Finding] {
        report.findings.sortedBySeverity().filter { !Self.coveredRules.contains($0.rule) }
    }

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case actions = "Actions"
        case incidents = "Incidents"
        var id: String { rawValue }
    }

    @State private var filter: Filter = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if filter == .all, !findings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Also noticed")
                    CardList(items: findings) { finding in
                        FindingNote(finding: finding)
                    }
                }
            }
            if filter != .actions, !incidents.isEmpty {
                CardList(items: incidents) { incident in
                    IncidentRow(incident: incident) { openIncident(incident) }
                }
            }
            if filter != .incidents {
                let entries = filter == .actions ? appState.activity.filter { $0.kind == .action } : appState.activity
                if entries.isEmpty {
                    Text("Nothing yet. Actions and pressure changes appear here.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    CardList(items: Array(entries.prefix(30))) { entry in
                        ActivityRow(entry: entry)
                    }
                }
            }
            Text("Incidents come from JetsamEvent reports in /Library/Logs/DiagnosticReports. Open one to see what was running.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct FindingNote: View {
    @EnvironmentObject private var appState: AppState
    let finding: Finding

    private var runnable: String? {
        finding.actions.first { ActionRunner.runnableActions.contains($0) && $0 != "free_idle" }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(finding.severity == .critical ? Color.red : finding.severity == .warn ? .orange : .secondary)
                .frame(width: 8, height: 8)
            Text(finding.message).font(.system(size: 12)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let action = runnable {
                RowButton(title: "Run", busy: appState.busy.contains("finding:\(finding.rule)")) {
                    appState.request(ActionRequest(
                        id: "finding:\(finding.rule)", action: action, targets: [],
                        logTitle: finding.message, doneText: "Done: \(action)",
                        confirmation: .init(
                            title: "Run \(action)?", body: finding.message, effect: "see message",
                            verb: "Run", destructive: true
                        )
                    ))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
    }
}

struct ActivityRow: View {
    let entry: ActivityEntry

    private var symbol: String {
        switch entry.tone {
        case .good: return "checkmark"
        case .neutral: return "clock"
        case .warning, .critical: return "exclamationmark"
        }
    }

    private var tint: Color {
        switch entry.tone {
        case .good: return .green
        case .neutral: return .secondary
        case .warning: return .orange
        case .critical: return .red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(Calendar.current.isDateInToday(entry.date) ? Format.clock(entry.date) : entry.date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 34, alignment: .leading)
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if !entry.note.isEmpty {
                    Text(entry.note).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
    }
}

struct IncidentRow: View {
    let incident: Incident
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.red)
                    .frame(width: 22, height: 22)
                    .background(Color.red.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Memory ran out").font(.system(size: 13, weight: .medium))
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        let ended = incident.killed.isEmpty ? "" : "macOS ended \(incident.killed.count) process(es) · "
        return "\(ended)\(String(incident.date.prefix(16)))"
    }
}

struct IncidentScreen: View {
    let incident: Incident

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.red, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memory ran out").font(.system(size: 17, weight: .semibold))
                    Text("\(String(incident.date.prefix(16))), from the macOS jetsam report. "
                        + "Largest process: \(incident.largestProcess ?? "unknown").")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            if !incident.killed.isEmpty {
                section("Ended by macOS", processes: incident.killed)
            }
            section("Largest at that moment", processes: incident.top)
            Text(incident.file)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
    }

    private func section(_ title: String, processes: [IncidentProcess]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: title)
            CardList(items: processes) { process in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(process.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(process.reason.map { "reason: \($0)" } ?? process.pid.map { "pid \($0)" } ?? "")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Format.gigabytes(process.bytes)).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
            }
        }
    }
}
