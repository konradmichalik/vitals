import SwiftUI

/// A summary line when no DDEV projects are running (nothing to expand
/// into), an expandable list with a per-project Stop button otherwise —
/// `stop_project` already exists end-to-end (CLI, `Action`, tests), this
/// was purely a missing UI path to it. Docker containers stay
/// summary-only: there's no equivalent per-container stop action yet,
/// only the bulk dangling-image prune.
struct DdevProjectsSection: View {
    let report: VitalsReport
    let onStop: (String) -> Void
    @State private var isExpanded = false

    private var summary: String {
        "\(report.docker.containers.count) container(s) · \(report.ddev.running.count) DDEV project(s) running"
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
            Image(systemName: "shippingbox")
                .foregroundStyle(.secondary)
            Text("Docker & DDEV")
                .font(.subheadline.weight(.semibold))
        }
    }
}
