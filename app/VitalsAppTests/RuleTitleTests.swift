import XCTest
@testable import VitalsApp

final class RuleTitleTests: XCTestCase {
    func testKnownRulesReadAsShortTitles() {
        XCTAssertEqual(RuleTitle.title(for: "load_status"), "High load")
        XCTAssertEqual(RuleTitle.title(for: "memory_pressure"), "Memory pressure")
        XCTAssertEqual(RuleTitle.title(for: "runaway_processes"), "Runaway processes")
    }

    func testUnknownRuleFallsBackToItsId() {
        XCTAssertEqual(RuleTitle.title(for: "made_up_rule"), "made_up_rule")
    }
}
