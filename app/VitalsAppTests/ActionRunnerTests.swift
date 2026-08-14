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

    /// The dropdown used to interpolate the raw enum, so a missing
    /// binary surfaced to the user as "Failed: vitalsNotFound".
    func testNotFoundErrorReadsAsProseWithTheSearchedLocation() {
        let message = ActionRunnerError.vitalsNotFound.message
        XCTAssertFalse(message.contains("vitalsNotFound"))
        XCTAssertTrue(message.lowercased().contains("vitals"))
        XCTAssertTrue(message.contains("/opt/homebrew/bin"), "got: \(message)")
    }

    func testLaunchFailedErrorIncludesTheUnderlyingReason() {
        let message = ActionRunnerError.launchFailed("permission denied").message
        XCTAssertFalse(message.contains("launchFailed"))
        XCTAssertTrue(message.contains("permission denied"))
    }

    func testNonZeroExitErrorIncludesTheCommandOutput() {
        let message = ActionRunnerError.nonZeroExit("no runaway processes found").message
        XCTAssertFalse(message.contains("nonZeroExit"))
        XCTAssertTrue(message.contains("no runaway processes found"))
    }

    /// A non-empty exit output is the whole diagnosis; falling back to a
    /// generic sentence when the CLI said nothing keeps it readable.
    func testNonZeroExitErrorFallsBackWhenOutputIsEmpty() {
        let message = ActionRunnerError.nonZeroExit("   ").message
        XCTAssertFalse(message.isEmpty)
        XCTAssertFalse(message.contains("nonZeroExit"))
    }

    func testCandidatePathsIncludeEntriesFromThePathEnvironment() {
        let candidates = ActionRunner.candidatePaths(pathEnvironment: "/my/tools:/usr/bin")
        XCTAssertTrue(candidates.contains("/my/tools/vitals"), "got: \(candidates)")
        XCTAssertTrue(candidates.contains("/usr/bin/vitals"), "got: \(candidates)")
    }

    /// Homebrew's locations stay ahead of PATH so a shell alias or an
    /// unrelated `vitals` earlier in PATH can't shadow the real install.
    func testCandidatePathsKeepTheKnownInstallLocationsFirst() {
        let candidates = ActionRunner.candidatePaths(pathEnvironment: "/my/tools")
        XCTAssertEqual(candidates.first, "/opt/homebrew/bin/vitals")
    }

    func testCandidatePathsIgnoreEmptyPathSegments() {
        let candidates = ActionRunner.candidatePaths(pathEnvironment: "/my/tools::")
        XCTAssertFalse(candidates.contains("/vitals"), "got: \(candidates)")
    }

    func testCandidatePathsHaveNoDuplicates() {
        let candidates = ActionRunner.candidatePaths(pathEnvironment: "/opt/homebrew/bin:/opt/homebrew/bin")
        XCTAssertEqual(candidates.count, Set(candidates).count, "got: \(candidates)")
    }

    func testPruneDockerImagesIsRunnable() {
        XCTAssertTrue(ActionRunner.runnableActions.contains("prune_docker_images"))
    }

    func testKillRunawayProcessesIsRunnable() {
        XCTAssertTrue(ActionRunner.runnableActions.contains("kill_runaway_processes"))
    }
}
