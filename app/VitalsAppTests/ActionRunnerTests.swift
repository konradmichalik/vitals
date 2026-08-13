import XCTest
@testable import VitalsApp

final class ActionRunnerTests: XCTestCase {
    func testBuildArgumentsAlwaysPassesYesToSkipTheInteractivePrompt() {
        let args = ActionRunner.buildArguments(action: "stop_backup", target: nil)
        XCTAssertTrue(args.contains("--yes"))
    }

    func testBuildArgumentsIncludesTheAction() {
        let args = ActionRunner.buildArguments(action: "poweroff", target: nil)
        XCTAssertEqual(args, ["--fix", "poweroff", "--yes"])
    }

    func testBuildArgumentsIncludesTargetWhenGiven() {
        let args = ActionRunner.buildArguments(action: "stop_project", target: "witte")
        XCTAssertEqual(args, ["--fix", "stop_project", "--yes", "--target", "witte"])
    }

    func testBuildArgumentsOmitsTargetWhenNil() {
        let args = ActionRunner.buildArguments(action: "stop_backup", target: nil)
        XCTAssertFalse(args.contains("--target"))
    }

    func testLocateVitalsBinaryReturnsFirstExistingCandidate() {
        let found = ActionRunner.locateVitalsBinary(
            candidates: ["/nonexistent/vitals", "/opt/homebrew/bin/vitals"],
            fileExists: { $0 == "/opt/homebrew/bin/vitals" }
        )
        XCTAssertEqual(found, "/opt/homebrew/bin/vitals")
    }

    func testLocateVitalsBinaryReturnsNilWhenNoneExist() {
        let found = ActionRunner.locateVitalsBinary(
            candidates: ["/nonexistent/vitals"],
            fileExists: { _ in false }
        )
        XCTAssertNil(found)
    }

    func testPruneDockerImagesIsRunnable() {
        XCTAssertTrue(ActionRunner.runnableActions.contains("prune_docker_images"))
    }

    func testKillRunawayProcessesIsRunnable() {
        XCTAssertTrue(ActionRunner.runnableActions.contains("kill_runaway_processes"))
    }
}
