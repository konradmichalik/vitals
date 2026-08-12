import XCTest
@testable import VitalsApp

final class VitalsBridgeTests: XCTestCase {
    // A trimmed but real-shaped success response, matching what
    // `vitals_collect()` actually returns (see core/src/types.rs).
    private let successJSON = """
    {
        "schemaVersion": 1,
        "timestamp": "2026-08-12T09:52:00Z",
        "system": {
            "uptimeSeconds": 1204140,
            "load": { "m1": 7.40, "m5": 7.04, "m15": 9.97 },
            "cores": { "performance": 10, "efficiency": 4, "total": 14 },
            "memory": {
                "pressureLevel": "normal",
                "freePercent": 36,
                "pageSizeBytes": 16384,
                "compressorBytes": 10905550848,
                "swapUsedBytes": 21690548224,
                "pageouts": 7301205
            }
        },
        "timeMachine": { "running": false, "phase": null, "changedItemCount": null, "exclusions": [] },
        "ddev": { "running": [], "problems": [], "pausedCount": 0, "stoppedCount": 0 },
        "docker": { "containers": [] },
        "processes": { "claudeSessions": [], "acpAgents": [], "orbstack": null },
        "findings": [
            { "rule": "uptime_ballast", "severity": "info", "message": "ballast", "actions": [] }
        ]
    }
    """

    private let errorJSON = """
    {"schemaVersion":1,"error":"probe not yet implemented: probes::load::read"}
    """

    func testDecodesASuccessfulReport() {
        let result = VitalsBridge.decode(successJSON)
        guard case .success(let report) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.system.load.m1, 7.40)
        XCTAssertEqual(report.findings.first?.rule, "uptime_ballast")
    }

    func testDecodesAReportedErrorEnvelope() {
        let result = VitalsBridge.decode(errorJSON)
        guard case .failure(let error) = result else {
            return XCTFail("expected failure, got \(result)")
        }
        XCTAssertEqual(error, .reported("probe not yet implemented: probes::load::read"))
    }

    func testRejectsGarbageAsMalformed() {
        let result = VitalsBridge.decode("not json at all")
        guard case .failure(let error) = result else {
            return XCTFail("expected failure, got \(result)")
        }
        XCTAssertEqual(error, .malformed)
    }
}
