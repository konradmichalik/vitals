import XCTest
@testable import VitalsApp

final class ActionEntryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let kill = SuggestedAction(action: "kill_process", target: "4242@1799999000", label: "End", estimate: nil)

    func testSuccessEntryStripsQuestionMarkAndHasNoNote() {
        let entry = ActivityEntry.action(for: kill, result: .success("ok"), at: now)
        XCTAssertEqual(entry.title, "Quit this process")
        XCTAssertEqual(entry.kind, .action)
        XCTAssertEqual(entry.severity, nil)
        XCTAssertEqual(entry.note, nil)
    }

    func testFailureNoteIsFixedAndLeaksNoPidOrTarget() {
        let result: Result<String, ActionRunnerError> = .failure(.nonZeroExit("kill 4242 failed at /Users/x"))
        let entry = ActivityEntry.action(for: kill, result: result, at: now)
        XCTAssertEqual(entry.note, "Action failed")
        XCTAssertTrue(!(entry.note ?? "").contains("4242"))
        XCTAssertTrue(!entry.title.contains("4242"))
    }
}
