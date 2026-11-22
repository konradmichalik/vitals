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
                "usedPercent": 64,
                "pageSizeBytes": 16384,
                "compressorBytes": 10905550848,
                "swapUsedBytes": 21690548224,
                "pageouts": 7301205
            },
            "cpu": { "userPercent": 22.82, "systemPercent": 22.93, "idlePercent": 54.23 }
        },
        "timeMachine": { "running": false, "phase": null, "changedItemCount": null, "exclusions": [] },
        "ddev": { "running": [], "problems": [], "pausedCount": 0, "stoppedCount": 0 },
        "docker": { "containers": [] },
        "processes": {
            "claudeSessions": [], "acpAgents": [], "orbstack": null,
            "topByCpu": [{ "pid": 4242, "name": "node", "cpuPercent": 91.2 }]
        },
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
        XCTAssertEqual(report.processes.topByCpu.first?.name, "node")
    }

    /// Schema 4 adds consumer groups, quick wins, incidents and the disk
    /// total; older payloads without them must still decode (see above).
    func testDecodesSchemaFourAdditions() {
        let json = successJSON
            .replacingOccurrences(of: #""pageouts": 7301205"#, with: #""pageouts": 7301205, "totalBytes": 25769803776, "availableBytes": 2791728742"#)
            .replacingOccurrences(of: #""findings": ["#, with: """
            "disk": { "totalBytes": 104857600 },
            "consumers": [{ "id": "ddev", "name": "DDEV", "memBytes": 100, "cpuPercent": 1.5, "idleBytes": 40,
              "items": [{ "id": "ddev:verdi", "name": "verdi", "detail": "no activity for 3 h", "memBytes": 40, "cpuPercent": 0.1,
                "idle": true, "idleSeconds": 10800, "protected": false,
                "action": { "action": "stop_project", "target": "verdi", "label": "Stop", "confirm": false } }] }],
            "quickWins": [{ "id": "stop_idle_ddev", "title": "Stop 1 idle DDEV project", "detail": "verdi", "reclaimableBytes": 40,
              "action": "stop_project", "targets": ["verdi"], "label": "Stop", "confirm": false, "undoAction": "start_project" }],
            "incidents": [{ "file": "JetsamEvent-x.ips", "date": "2026-11-16 16:42:00 +0100", "largestProcess": "PhpStorm",
              "pageSizeBytes": 16384, "killed": [{ "pid": 7, "name": "PhpStorm", "bytes": 1, "reason": "vm-pageshortage" }], "top": [] }],
            "findings": [
            """)
        guard case .success(let report) = VitalsBridge.decode(json) else {
            return XCTFail("expected schema 4 payload to decode")
        }
        XCTAssertEqual(report.system.memory.availableBytes, 2_791_728_742)
        XCTAssertEqual(report.disk?.totalBytes, 104_857_600)
        XCTAssertEqual(report.consumerGroups.first?.idleItems.first?.action?.target, "verdi")
        XCTAssertEqual(report.quickWinList.first?.undoAction, "start_project")
        XCTAssertEqual(report.incidentList.first?.killed.first?.reason, "vm-pageshortage")
        XCTAssertEqual(report.idleBytes, 40)
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
