import SwiftUI

/// Read-only: the core offers no per-container action, only the image prune on the overview.
struct DockerTab: View {
    let docker: DockerInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolchainSummaryText(text: ToolchainSummary.docker(docker))
            if docker.containers.isEmpty {
                ToolchainEmptyText(text: "No containers.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(docker.containers) { container in
                        Divider()
                        ToolchainRow(
                            title: container.name,
                            detail: container.ddevManaged ? "DDEV" : nil,
                            symbol: "shippingbox"
                        )
                    }
                }
            }
        }
    }
}
