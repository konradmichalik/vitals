import XCTest
@testable import VitalsApp

final class ActionConfirmationTests: XCTestCase {
    private func make(_ action: String, target: String? = nil, estimate: String? = nil, label: String? = nil)
        -> ActionConfirmation {
        ActionConfirmation.make(
            for: SuggestedAction(action: action, target: target, label: "x", estimate: estimate),
            culpritLabel: label
        )
    }

    func testStopProject() {
        let result = make("stop_project", target: "witte")
        XCTAssertEqual(result.title, "Stop ddev project witte?")
        XCTAssertEqual(result.reversal, "Start again with ddev start witte")
        XCTAssertFalse(result.isDestructive)
    }

    func testStartProject() {
        let result = make("start_project", target: "witte")
        XCTAssertEqual(result.title, "Start ddev project witte?")
        XCTAssertEqual(result.reversal, "Stop it again")
        XCTAssertFalse(result.isDestructive)
    }

    func testKillProcess() {
        let result = make("kill_process", target: "48213@999400", label: "PhpStorm")
        XCTAssertEqual(result.title, "Quit PhpStorm?")
        XCTAssertEqual(result.reversal, "Not reversible")
        XCTAssertTrue(result.isDestructive)
    }

    func testPoweroff() {
        let result = make("poweroff")
        XCTAssertEqual(result.title, "Power off all DDEV projects?")
        XCTAssertTrue(result.isDestructive)
    }

    func testPruneDockerImages() {
        let result = make("prune_docker_images")
        XCTAssertEqual(result.title, "Remove dangling images?")
        XCTAssertTrue(result.isDestructive)
    }

    func testAddExclusions() {
        let result = make("add_exclusions")
        XCTAssertEqual(result.title, "Exclude container data from backups?")
        XCTAssertFalse(result.isDestructive)
    }

    func testStopBackup() {
        let result = make("stop_backup")
        XCTAssertEqual(result.title, "Stop the running backup?")
        XCTAssertFalse(result.isDestructive)
    }

    func testKillOrphanedAgents() {
        let result = make("kill_orphaned_agents")
        XCTAssertEqual(result.title, "Quit orphaned agents?")
        XCTAssertFalse(result.isDestructive)
    }

    func testKillRunawayProcesses() {
        let result = make("kill_runaway_processes")
        XCTAssertEqual(result.title, "Quit runaway processes?")
        XCTAssertEqual(result.reversal, "Not reversible")
        XCTAssertEqual(result.command, "vitals --fix kill_runaway_processes")
        XCTAssertTrue(result.isDestructive)
    }

    func testButtonLabelsMatchTheConfirmationVerb() {
        let expected = [
            "poweroff": "Power off DDEV", "stop_project": "Stop", "start_project": "Start",
            "stop_backup": "Stop backup", "add_exclusions": "Exclude", "kill_orphaned_agents": "Quit agents",
            "kill_runaway_processes": "Quit processes", "kill_process": "Quit", "prune_docker_images": "Prune images",
        ]
        for (action, label) in expected {
            XCTAssertEqual(ActionConfirmation.buttonLabel(for: action), label)
            XCTAssertEqual(make(action, target: "t").buttonLabel, label)
        }
    }

    func testUnknownButtonLabelIsSentenceCasedName() {
        XCTAssertEqual(ActionConfirmation.buttonLabel(for: "list_running_projects"), "List running projects")
    }

    func testCommandIncludesTargetAndEffectIsTheEstimate() {
        let result = make("kill_process", target: "1@2", estimate: "about 2 cores", label: "x")
        XCTAssertEqual(result.command, "vitals --fix kill_process --target 1@2")
        XCTAssertEqual(result.effect, "about 2 cores")
        XCTAssertEqual(make("poweroff").command, "vitals --fix poweroff")
    }

    func testBodyIsPlainTextWithoutMarkdown() {
        XCTAssertEqual(make("poweroff").body, "This runs vitals --fix poweroff.")
        XCTAssertEqual(make("kill_process", target: "1@2").body, "This runs vitals --fix kill_process --target 1@2.")
    }
}
