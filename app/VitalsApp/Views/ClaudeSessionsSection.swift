import SwiftUI

/// Parallel Claude Code sessions are a normal, expected source of
/// background CPU/RAM load for a dev-stack monitor to explain — until
/// now only a *stale* session (past the configured age threshold)
/// surfaced at all, and only as a Finding; a perfectly normal session
/// doing active work stayed invisible. Informational only, mirroring
/// `DdevProjectsSection`'s summary + expandable-list shape: no
/// per-session action makes sense here, since killing an active coding
/// session isn't something this app should offer.
struct ClaudeSessionsSection: View {
    let sessions: [ClaudeSession]
    @State private var isExpanded = false

    private var summary: String {
        let totalCpu = sessions.reduce(0.0) { $0 + $1.cpuPercent }
        return "\(sessions.count) Claude Code session(s) running · \(Int(totalCpu.rounded()))% CPU"
    }

    var body: some View {
        if !sessions.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sessions.groupedByProject().enumerated()), id: \.element.id) { index, group in
                        if index > 0 {
                            Divider()
                        }
                        HStack(spacing: 4) {
                            Text(group.label)
                                .font(.caption)
                            if group.count > 1 {
                                Text("×\(group.count)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor, in: Capsule())
                            }
                            Spacer()
                            Text("\(Int(group.cpuPercent.rounded()))% CPU")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(Self.durationFormatter.string(from: TimeInterval(group.longestEtimeSeconds)) ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                // only the triangle toggles it — so extend the tap target
                // across the whole label instead of just the triangle.
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }
            }
        }
    }

    private var header: some View {
        SectionHeader(icon: "terminal", title: "Claude Code")
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        return formatter
    }()
}
