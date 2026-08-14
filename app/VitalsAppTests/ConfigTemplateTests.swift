import XCTest
@testable import VitalsApp

final class ConfigTemplateTests: XCTestCase {
    func testTemplateIsValidTomlCommentaryPlusSections() {
        let contents = ConfigTemplate.contents
        XCTAssertTrue(contents.contains("[rules]"))
        XCTAssertTrue(contents.contains("[thresholds]"))
        XCTAssertTrue(contents.contains("[actions]"))
    }

    /// The whole point of the template is discoverability — every knob
    /// the rule engine reads should be visible (commented out) rather
    /// than something you only learn about from the source.
    func testTemplateDocumentsEveryThresholdKey() {
        let keys = [
            "load_warn_factor",
            "load_critical_factor",
            "compressor_warn_gb",
            "uptime_warn_days",
            "stale_session_days",
            "changed_items_warn",
            "docker_reclaimable_warn_gb",
            "runaway_cpu_percent",
            "runaway_min_minutes",
            "orbstack_cpu_percent",
            "mutagen_cpu_percent",
            "acp_agent_warn_count",
        ]
        for key in keys {
            XCTAssertTrue(ConfigTemplate.contents.contains(key), "template is missing \(key)")
        }
    }

    /// Everything ships commented out, so writing the template over a
    /// fresh install can never change behaviour on its own.
    func testTemplateLeavesEverySettingCommentedOut() {
        let assignments = ConfigTemplate.contents
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("=") && !$0.hasPrefix("#") }
        XCTAssertTrue(assignments.isEmpty, "uncommented settings: \(assignments)")
    }
}
