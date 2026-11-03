import XCTest
@testable import VitalsApp

final class ToolchainSummaryTests: XCTestCase {
    private func container(ddev: Bool) -> DockerContainer {
        DockerContainer(
            id: UUID().uuidString, name: "c", image: "img", cpuPercent: 0, memBytes: 0,
            ddevManaged: ddev, ddevProject: nil, composeProject: nil
        )
    }

    private func project(_ name: String, _ status: String) -> DdevProjectStatus {
        DdevProjectStatus(name: name, status: status)
    }

    func testDdevSummaryCountsRunningOfTotal() {
        let info = DdevInfo(
            running: ["a", "b"], problems: [], pausedCount: 1, stoppedCount: 1,
            projects: [project("a", "running"), project("b", "running"), project("c", "paused"), project("d", "stopped")]
        )
        XCTAssertEqual(ToolchainSummary.ddev(info), "2 of 4 projects running. Stopping keeps database and files.")
    }

    func testDockerSummarySplitsDdevAndOthers() {
        let info = DockerInfo(containers: [container(ddev: true), container(ddev: true), container(ddev: false)])
        XCTAssertEqual(ToolchainSummary.docker(info), "3 containers. 2 belong to DDEV, 1 do not.")
    }

    func testDockerSummaryWithoutContainers() {
        XCTAssertEqual(ToolchainSummary.docker(DockerInfo(containers: [])), "0 containers. 0 belong to DDEV, 0 do not.")
    }
}
