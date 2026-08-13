import XCTest
@testable import VitalsApp

final class ClaudeSessionTests: XCTestCase {
    private func session(workingDirectory: String?, version: String = "2.1.228") -> ClaudeSession {
        ClaudeSession(
            pid: 1,
            etimeSeconds: 60,
            cpuPercent: 0,
            rssBytes: 0,
            kind: "cli",
            version: version,
            workingDirectory: workingDirectory
        )
    }

    func testProjectLabelUsesTheWorkingDirectorysLastPathComponent() {
        let result = session(workingDirectory: "/Users/km/Sites/Projects/verdi").projectLabel
        XCTAssertEqual(result, "verdi")
    }

    func testProjectLabelFallsBackToVersionWhenNoWorkingDirectory() {
        let result = session(workingDirectory: nil).projectLabel
        XCTAssertEqual(result, "v2.1.228")
    }

    func testGroupedByProjectCombinesSessionsInTheSameDirectory() {
        let sessions = [
            session(workingDirectory: "/Users/km/Sites/Projects/verdi"),
            session(workingDirectory: "/Users/km/Sites/Projects/verdi"),
            session(workingDirectory: "/Users/km/Sites/Projects/vitals"),
        ]
        let groups = sessions.groupedByProject()
        XCTAssertEqual(groups.map(\.label), ["verdi", "vitals"])
        XCTAssertEqual(groups.map(\.count), [2, 1])
    }

    func testGroupedByProjectUsesTheLongestRunningSessionsEtime() {
        let sessions = [
            ClaudeSession(
                pid: 1, etimeSeconds: 60, cpuPercent: 0, rssBytes: 0, kind: "cli",
                version: "2.1.228", workingDirectory: "/Users/km/verdi"
            ),
            ClaudeSession(
                pid: 2, etimeSeconds: 3600, cpuPercent: 0, rssBytes: 0, kind: "cli",
                version: "2.1.228", workingDirectory: "/Users/km/verdi"
            ),
        ]
        let groups = sessions.groupedByProject()
        XCTAssertEqual(groups.first?.longestEtimeSeconds, 3600)
    }

    func testGroupedByProjectSumsCpuPercentAcrossSessions() {
        let sessions = [
            ClaudeSession(
                pid: 1, etimeSeconds: 60, cpuPercent: 3.5, rssBytes: 0, kind: "cli",
                version: "2.1.228", workingDirectory: "/Users/km/verdi"
            ),
            ClaudeSession(
                pid: 2, etimeSeconds: 60, cpuPercent: 8.2, rssBytes: 0, kind: "cli",
                version: "2.1.228", workingDirectory: "/Users/km/verdi"
            ),
        ]
        let groups = sessions.groupedByProject()
        XCTAssertEqual(groups.first!.cpuPercent, 11.7, accuracy: 0.001)
    }

    func testGroupedByProjectSortsByCpuPercentEvenOverACountOfMoreSessions() {
        let sessions = [
            ClaudeSession(
                pid: 1, etimeSeconds: 60, cpuPercent: 1, rssBytes: 0, kind: "cli",
                version: "2.1.228", workingDirectory: "/Users/km/quiet"
            ),
            ClaudeSession(
                pid: 2, etimeSeconds: 60, cpuPercent: 1, rssBytes: 0, kind: "cli",
                version: "2.1.228", workingDirectory: "/Users/km/quiet"
            ),
            ClaudeSession(
                pid: 3, etimeSeconds: 60, cpuPercent: 90, rssBytes: 0, kind: "cli",
                version: "2.1.228", workingDirectory: "/Users/km/busy"
            ),
        ]
        let groups = sessions.groupedByProject()
        XCTAssertEqual(groups.map(\.label), ["busy", "quiet"])
    }
}
