import SwiftUI

/// The activity log: newest first, filterable by kind.
struct ActivityView: View {
    @EnvironmentObject private var appState: AppState
    @State private var filter: ActivityFilter = .all

    var body: some View {
        let entries = filter.apply(appState.activity)
        VStack(alignment: .leading, spacing: 12) {
            Picker("Filter", selection: $filter) {
                ForEach(ActivityFilter.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if entries.isEmpty {
                Text(filter.emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            }
            ForEach(entries) { ActivityRow(entry: $0) }
        }
        .padding(12)
    }
}

private struct ActivityRow: View {
    let entry: ActivityEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.timeText(entry.date, now: Date()))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: entry.kind == .action ? "bolt" : "waveform.path.ecg")
                .foregroundStyle(.secondary)
                .accessibilityLabel(entry.kind == .action ? "Action" : "Event")
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.callout)
                if let note = entry.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let severity = entry.severity {
                SeverityBadge(severity: severity)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static func timeText(_ date: Date, now: Date) -> String {
        if Calendar.current.isDate(date, inSameDayAs: now) {
            return date.formatted(.dateTime.hour().minute())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
