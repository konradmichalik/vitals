import XCTest
@testable import VitalsApp

final class ReportDiffTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func report(
        ddev: [String] = [],
        tmRunning: Bool = false,
        pressure: String = "normal",
        findings: String = ""
    ) throws -> VitalsReport {
        let names = ddev.map { "\"\($0)\"" }.joined(separator: ",")
        let json = """
        {"schemaVersion":4,"timestamp":"t",
        "system":{"uptimeSeconds":1,"load":{"m1":0,"m5":0,"m15":0},
          "cores":{"performance":1,"efficiency":1,"total":2},
          "memory":{"pressureLevel":"\(pressure)","freePercent":50,"usedPercent":50,"pageSizeBytes":16384,
            "compressorBytes":0,"swapUsedBytes":0,"pageouts":0},
          "cpu":{"userPercent":1,"systemPercent":1,"idlePercent":98}},
        "timeMachine":{"running":\(tmRunning),"phase":null,"changedItemCount":null,"exclusions":[]},
        "ddev":{"running":[\(names)],"problems":[],"pausedCount":0,"stoppedCount":0,"projects":[]},
        "docker":{"containers":[]},
        "processes":{"claudeSessions":[],"acpAgents":[],"orbstack":null,"topByCpu":[],"topByMemory":[]},
        "findings":[\(findings)],"consumers":[],
        "verdict":{"headline":"h","detail":"d"}}
        """
        return try JSONDecoder().decode(VitalsReport.self, from: Data(json.utf8))
    }

    private func finding(_ rule: String, _ severity: String, _ message: String) -> String {
        "{\"rule\":\"\(rule)\",\"severity\":\"\(severity)\",\"message\":\"\(message)\",\"actions\":[]}"
    }

    func testNoPreviousReportYieldsNoEvents() throws {
        XCTAssertEqual(ReportDiff.events(previous: nil, current: try report(ddev: ["a"]), at: now), [])
    }

    func testDdevProjectStartAndStop() throws {
        let events = ReportDiff.events(
            previous: try report(ddev: ["old"]), current: try report(ddev: ["new"]), at: now
        )
        XCTAssertEqual(events.map(\.title), ["ddev start new", "ddev stop old"])
        XCTAssertTrue(events.allSatisfy { $0.kind == .event && $0.severity == nil })
    }

    func testTimeMachineBeganAndFinished() throws {
        let began = ReportDiff.events(previous: try report(), current: try report(tmRunning: true), at: now)
        let finished = ReportDiff.events(previous: try report(tmRunning: true), current: try report(), at: now)
        XCTAssertEqual(began.map(\.title), ["Time Machine began"])
        XCTAssertEqual(finished.map(\.title), ["Time Machine finished"])
    }

    func testPressureChange() throws {
        let events = ReportDiff.events(previous: try report(), current: try report(pressure: "warn"), at: now)
        XCTAssertEqual(events.map(\.title), ["Memory pressure normal to warn"])
    }

    func testRuleEnteringWarnEmitsFindingMessageWithSeverity() throws {
        let current = try report(findings: finding("load", "warn", "Load is high"))
        let events = ReportDiff.events(previous: try report(), current: current, at: now)
        XCTAssertEqual(events.map(\.title), ["Load is high"])
        XCTAssertEqual(events.first?.severity, .warn)
    }

    func testSteadyStateYieldsNoEvents() throws {
        let steady = try report(ddev: ["a"], findings: finding("load", "warn", "Load is high"))
        XCTAssertEqual(ReportDiff.events(previous: steady, current: steady, at: now), [])
    }
}
