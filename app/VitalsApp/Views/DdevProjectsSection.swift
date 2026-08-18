import SwiftUI

/// A summary line when no DDEV projects are running (nothing to expand
/// into), an expandable list with a per-project Stop button otherwise —
/// `stop_project` already exists end-to-end (CLI, `Action`, tests), this
/// was purely a missing UI path to it. Docker containers stay
/// summary-only: there's no equivalent per-container stop action yet,
/// only the bulk dangling-image prune.
struct DdevProjectsSection: View {
    let report: VitalsReport
    let onPoweroff: () -> Void
    let onStop: (String) -> Void
    @State private var isExpanded = false

    private var summary: String {
        let totalCpu = report.docker.containers.reduce(0.0) { $0 + $1.cpuPercent }
        return "\(report.docker.containers.count) container(s) · \(report.ddev.running.count) DDEV project(s)"
            + " running · \(Int(totalCpu.rounded()))% CPU"
    }

    /// OrbStack belongs here rather than in its own section: it *is* the
    /// runtime those containers burn CPU through, and `container_load`
    /// judges exactly this number while the UI never showed it.
    @ViewBuilder
    private var orbstackLine: some View {
        if let label = ServiceSummary.orbstackLabel(report.processes.orbstack) {
            Text("OrbStack · \(label)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func cpuPercent(for project: String) -> Double {
        report.docker.containers
            .filter { $0.ddevProject == project }
            .reduce(0) { $0 + $1.cpuPercent }
    }

    private var sortedProjects: [String] {
        report.ddev.running.sorted { lhs, rhs -> Bool in
            let lhsCpu = cpuPercent(for: lhs)
            let rhsCpu = cpuPercent(for: rhs)
            if lhsCpu != rhsCpu {
                return lhsCpu > rhsCpu
            }
            return lhs < rhs
        }
    }

    var body: some View {
        if report.ddev.running.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                header
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                orbstackLine
            }
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sortedProjects.enumerated()), id: \.element) { index, project in
                        if index > 0 {
                            Divider()
                        }
                        HStack {
                            Text(project)
                                .font(.caption)
                            Spacer()
                            Text("\(Int(cpuPercent(for: project).rounded()))% CPU")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Stop") { onStop(project) }
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
                    orbstackLine
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
        HStack(spacing: 6) {
            SectionHeader(icon: "shippingbox", title: "Docker & DDEV")
            Spacer()
            // A menu rather than a second header button — bulk actions
            // are rare enough that a permanently visible button would
            // just eat space next to the per-project Stop buttons below.
            if !report.ddev.running.isEmpty {
                Menu {
                    Button("Power off all DDEV projects", action: onPoweroff)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                // The ellipsis already reads as "there's more here" —
                // macOS's default disclosure arrow next to it is a second
                // affordance for the same thing.
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.secondary)
            }
        }
    }
}
