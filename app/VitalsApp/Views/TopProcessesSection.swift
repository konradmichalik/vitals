import SwiftUI

/// Answers "what's actually driving load right now" — a critical
/// `load_status` finding names the load figure but never the process
/// behind it. `kill_session` (already wired end-to-end in the CLI for
/// killing an arbitrary PID, previously with no UI path to it) offers a
/// way to act on what's found here directly, on top of
/// `kill_runaway_processes`'s separate, criteria-gated path for sustained
/// offenders.
struct TopProcessesSection: View {
    let processes: [TopProcess]
    let onKill: (UInt32) -> Void
    @State private var isExpanded = false

    private var summary: String {
        "\(processes.count) process(es) by CPU usage"
    }

    var body: some View {
        if !processes.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(processes.enumerated()), id: \.element.id) { index, process in
                        if index > 0 {
                            Divider()
                        }
                        HStack {
                            Text(process.name)
                                .font(.caption)
                            Spacer()
                            Text("\(Int(process.cpuPercent.rounded()))% CPU")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Kill") { onKill(process.pid) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    header
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // DisclosureGroup's label is inert by default on macOS —
                // only the triangle toggles it — so extend the tap
                // target across the whole label instead.
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }
            }
        }
    }

    private var header: some View {
        SectionHeader(icon: "list.number", title: "Top processes")
    }
}
