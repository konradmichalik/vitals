import Foundation

/// One-line summaries shown above the DDEV and Docker lists.
enum ToolchainSummary {
    static func ddev(_ info: DdevInfo) -> String {
        "\(info.running.count) of \(info.projects.count) projects running. Stopping keeps database and files."
    }

    static func docker(_ info: DockerInfo) -> String {
        let ddev = info.containers.filter(\.ddevManaged).count
        return "\(info.containers.count) containers. \(ddev) belong to DDEV, \(info.containers.count - ddev) do not."
    }
}
