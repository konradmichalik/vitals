import XCTest
@testable import VitalsApp

final class VitalsBridgeTests: XCTestCase {
    // A trimmed but real-shaped success response, matching what
    // `vitals_collect()` actually returns (see core/src/types.rs).
    private let successJSON = """
    {
        "schemaVersion": 4,
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
        "ddev": {
            "running": ["witte"], "problems": [], "pausedCount": 0, "stoppedCount": 0,
            "projects": [{ "name": "witte", "status": "running" }]
        },
        "docker": { "containers": [] },
        "processes": {
            "claudeSessions": [], "acpAgents": [], "orbstack": null,
            "topByCpu": [{
                "pid": 4242, "name": "node", "label": "node", "cpuPercent": 91.2,
                "rssBytes": 1048576, "startedAt": 1786528000
            }],
            "topByMemory": [{
                "pid": 4243, "name": "java", "label": "java", "cpuPercent": 1.5,
                "rssBytes": 2147483648, "startedAt": 1786520000
            }]
        },
        "findings": [
            { "rule": "uptime_ballast", "severity": "info", "message": "ballast", "actions": [] }
        ],
        "consumers": [{
            "id": "ddev:witte", "kind": "ddevProject", "label": "witte", "detail": "4 containers",
            "cpuPercent": 12.5, "memBytes": 3221225472,
            "children": [{
                "label": "web", "detail": null, "cpuPercent": 10.0, "memBytes": 1073741824,
                "action": null
            }],
            "action": { "action": "stop_project", "target": "witte", "label": "Stop witte", "estimate": "about 3 GB" }
        }],
        "verdict": {
            "severity": "warn",
            "headline": "Memory is tight",
            "detail": "Swap is growing.",
            "culprit": { "id": "ddev:witte", "label": "witte", "reason": "uses 3 GB" },
            "action": { "action": "stop_project", "target": "witte", "label": "Stop witte", "estimate": null }
        }
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
        XCTAssertEqual(report.schemaVersion, 4)
        XCTAssertEqual(report.system.load.m1, 7.40)
        XCTAssertEqual(report.findings.first?.rule, "uptime_ballast")
        XCTAssertEqual(report.processes.topByCpu.first?.name, "node")
    }

    func testDecodesSchema4VerdictAndConsumers() {
        guard case .success(let report) = VitalsBridge.decode(successJSON) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(report.verdict.headline, "Memory is tight")
        XCTAssertEqual(report.verdict.severity, .warn)
        XCTAssertEqual(report.verdict.culprit?.id, "ddev:witte")
        XCTAssertEqual(report.verdict.action?.target, "witte")
        XCTAssertEqual(report.consumers.first?.kind, .ddevProject)
        XCTAssertEqual(report.consumers.first?.children.first?.label, "web")
        XCTAssertEqual(report.consumers.first?.action?.estimate, "about 3 GB")
        XCTAssertEqual(report.processes.topByMemory.first?.rssBytes, 2_147_483_648)
        XCTAssertEqual(report.ddev.projects.first?.status, "running")
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
