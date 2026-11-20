import XCTest
@testable import VitalsApp

final class HealthSummaryTests: XCTestCase {
    func testCriticalPressureLeadsWithMemoryAndStatesMeasuredValues() {
        let summary = HealthSummary.from(report: ReportFixtures.report(pressure: .critical, swap: 11 * 1_073_741_824), cpuSaturated: true)
        XCTAssertEqual(summary.tone, .critical)
        XCTAssertEqual(summary.focus, .memory)
        XCTAssertTrue(summary.detail.contains("6.0 GB free"))
        XCTAssertTrue(summary.detail.contains("11.0 GB in swap"))
    }

    func testWarnPressureIsAWarning() {
        let summary = HealthSummary.from(report: ReportFixtures.report(pressure: .warn), cpuSaturated: false)
        XCTAssertEqual(summary.tone, .warning)
        XCTAssertEqual(summary.title, "Memory is getting tight")
    }

    func testSaturatedCpuSpeaksOnlyWhenMemoryIsFine() {
        let summary = HealthSummary.from(report: ReportFixtures.report(idlePercent: 4), cpuSaturated: true)
        XCTAssertEqual(summary.focus, .cpu)
        XCTAssertTrue(summary.detail.contains("96% in use"))
        XCTAssertTrue(summary.detail.contains("node"))
    }

    func testCalmWhenNothingIsWrong() {
        let summary = HealthSummary.from(report: ReportFixtures.report(), cpuSaturated: false)
        XCTAssertEqual(summary.tone, .calm)
        XCTAssertEqual(summary.title, "All calm")
    }

    func testMenuBarShowsFreeMemoryOnWarningAndCpuWhenCpuIsTheProblem() {
        let warn = ReportFixtures.report(pressure: .warn)
        let warnState = MenuBarState.from(report: warn, summary: HealthSummary.from(report: warn, cpuSaturated: false))
        XCTAssertEqual(warnState.tone, .warning)
        XCTAssertEqual(warnState.label, "6.0 GB")
        XCTAssertEqual(warnState.fill, 0.75, accuracy: 0.001)

        let cpu = ReportFixtures.report(idlePercent: 4)
        let cpuState = MenuBarState.from(report: cpu, summary: HealthSummary.from(report: cpu, cpuSaturated: true))
        XCTAssertEqual(cpuState.label, "CPU 96%")

        let calm = ReportFixtures.report()
        XCTAssertNil(MenuBarState.from(report: calm, summary: HealthSummary.from(report: calm, cpuSaturated: false)).label)
    }

    func testIdleBytesSumOverGroups() {
        let report = ReportFixtures.report(consumers: [
            ReportFixtures.group(id: "ddev", idle: 100),
            ReportFixtures.group(id: "agents", idle: 50),
        ])
        XCTAssertEqual(report.idleBytes, 150)
        XCTAssertEqual(ReportFixtures.report().idleBytes, 0)
    }
}

final class GuardPolicyTests: XCTestCase {
    private func input(
        enabled: Bool = true,
        pressure: PressureLevel = .critical,
        threshold: PressureLevel = .critical,
        idle: UInt64 = 1,
        scopes: [String] = ["ddev"]
    ) -> GuardPolicy.Input {
        GuardPolicy.Input(enabled: enabled, pressure: pressure, threshold: threshold, idleBytes: idle, scopes: scopes)
    }

    func testRunsAtOrAboveTheThresholdWithSomethingIdle() {
        let now = Date()
        XCTAssertTrue(GuardPolicy.shouldRun(input(), lastRun: nil, now: now))
        XCTAssertTrue(GuardPolicy.shouldRun(input(pressure: .critical, threshold: .warn), lastRun: nil, now: now))
        XCTAssertFalse(GuardPolicy.shouldRun(input(pressure: .warn), lastRun: nil, now: now))
    }

    func testNeverRunsWhenOffIdleLessUnscopedOrNormal() {
        let now = Date()
        XCTAssertFalse(GuardPolicy.shouldRun(input(enabled: false), lastRun: nil, now: now))
        XCTAssertFalse(GuardPolicy.shouldRun(input(idle: 0), lastRun: nil, now: now))
        XCTAssertFalse(GuardPolicy.shouldRun(input(scopes: []), lastRun: nil, now: now))
        XCTAssertFalse(GuardPolicy.shouldRun(input(pressure: .normal, threshold: .normal), lastRun: nil, now: now))
    }

    func testRespectsTheCooldown() {
        let now = Date()
        XCTAssertFalse(GuardPolicy.shouldRun(input(), lastRun: now.addingTimeInterval(-60), now: now))
        XCTAssertTrue(GuardPolicy.shouldRun(input(), lastRun: now.addingTimeInterval(-GuardPolicy.cooldown), now: now))
    }

    func testSustainedCheckNeedsTheWholeWindowAboveTheLimit() {
        let now = Date()
        let points = (0...10).map { SustainedCheck.Point(date: now.addingTimeInterval(Double(-$0) * 30), value: 95) }
        XCTAssertTrue(SustainedCheck.isSustained(points.reversed(), above: 90, for: 300, now: now))
        var dipped = Array(points.reversed())
        dipped[8] = SustainedCheck.Point(date: dipped[8].date, value: 40)
        XCTAssertFalse(SustainedCheck.isSustained(dipped, above: 90, for: 300, now: now))
        let short = points.prefix(3).reversed().map { $0 }
        XCTAssertFalse(SustainedCheck.isSustained(short, above: 90, for: 300, now: now))
    }
}

final class AppSettingsTests: XCTestCase {
    func testOverridesJSONMatchesWhatTheCoreParses() {
        XCTAssertEqual(
            AppSettings.overridesJSON(idleMinutes: 90, protected: ["witte"]),
            #"{"idleAfterMinutes":90,"protected":["witte"]}"#
        )
    }

    func testCliArgumentsCarryTheSameSettings() {
        XCTAssertEqual(AppSettings.cliArguments(idleMinutes: 60, protected: []), ["--idle-minutes=60"])
        XCTAssertEqual(
            AppSettings.cliArguments(idleMinutes: 60, protected: ["a", "b"]),
            ["--idle-minutes=60", "--protect=a,b"]
        )
    }

    func testFreshIsOnlySentWhenAsked() {
        XCTAssertEqual(
            AppSettings.overridesJSON(idleMinutes: 90, protected: [], fresh: true),
            #"{"fresh":true,"idleAfterMinutes":90,"protected":[]}"#
        )
    }

    /// The CLI splits `--protect` on commas; an entry containing one
    /// would protect nothing while looking as if it did.
    func testProtectedEntriesWithCommasAreRefused() {
        XCTAssertEqual(AppSettings.sanitizedProtectedEntry("  witte "), "witte")
        XCTAssertEqual(AppSettings.sanitizedProtectedEntry("~/Sites/my project"), "~/Sites/my project")
        XCTAssertNil(AppSettings.sanitizedProtectedEntry("a,b"))
        XCTAssertNil(AppSettings.sanitizedProtectedEntry("   "))
    }

    func testGuardScopesKeepOnlyEnabledKinds() {
        XCTAssertEqual(AppSettings.guardScopes(ddev: true, agents: false, orphans: true), ["ddev", "orphans"])
    }

    func testQuietHoursRunOvernight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        func at(_ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: hour)) ?? Date()
        }
        XCTAssertTrue(AppSettings.isQuietTime(at(23), calendar: calendar))
        XCTAssertTrue(AppSettings.isQuietTime(at(7), calendar: calendar))
        XCTAssertFalse(AppSettings.isQuietTime(at(8), calendar: calendar))
        XCTAssertFalse(AppSettings.isQuietTime(at(18), calendar: calendar))
    }
}

final class ActionPlumbingTests: XCTestCase {
    func testBuildsMultiTargetScopedArgumentsWithSettings() {
        let args = ActionRunner.buildArguments(
            action: "free_idle", targets: [], scope: ["ddev", "agents"], extra: ["--idle-minutes=120"]
        )
        XCTAssertEqual(args, ["--fix", "free_idle", "--yes", "--scope=ddev,agents", "--idle-minutes=120"])
        XCTAssertEqual(
            ActionRunner.buildArguments(action: "stop_project", targets: ["a", "b"], scope: nil, extra: []),
            ["--fix", "stop_project", "--yes", "--target=a,b"]
        )
    }

    /// A value that starts with a dash must stay a value. Joined with
    /// `=` it can never be read as an option; the CLI then refuses it.
    func testATargetCanNeverBecomeAnOption() {
        let args = ActionRunner.buildArguments(action: "stop_project", targets: ["--remove-data"], scope: nil, extra: [])
        XCTAssertEqual(args, ["--fix", "stop_project", "--yes", "--target=--remove-data"])
    }

    func testDownsamplingKeepsThePeaks() {
        let values: [Double?] = (0..<100).map { $0 == 57 ? 99 : 1 }
        let small = MetricHistory.downsampled(values, to: 10)
        XCTAssertEqual(small.count, 10)
        XCTAssertEqual(small.max(), 99)
        XCTAssertEqual(MetricHistory.downsampled([1, nil, 3], to: 10), [1, 0, 3])
    }

    func testQuickWinRequestsAskOnlyWhenTheCoreSaysSo() {
        let win = QuickWin(
            id: "stop_idle_ddev", title: "Stop 2 idle DDEV projects", detail: "verdi, pagetree",
            reclaimableBytes: 2_791_728_742, action: "stop_project", targets: ["verdi", "pagetree"],
            label: "Stop", confirm: false, undoAction: "start_project"
        )
        let request = ActionRequest.quickWin(win)
        XCTAssertNil(request.confirmation)
        XCTAssertEqual(request.undo?.action, "start_project")
        XCTAssertEqual(request.commandPreview, "vitals --fix stop_project --target verdi,pagetree")
        XCTAssertTrue(request.doneText.contains("about 2.6 GB"))
    }

    func testDiskRatesComeFromConsecutiveTotals() {
        func sample(_ seconds: Double, _ total: UInt64?) -> MetricSample {
            var sample = MetricSample(
                load: 0, loadStatus: .normal, cpuUsedPercent: 0, memoryUsedPercent: 0,
                memoryPressure: .normal, timestamp: Date(timeIntervalSince1970: seconds)
            )
            sample.diskTotalBytes = total
            return sample
        }
        let rates = MetricHistory.diskRates([sample(0, 0), sample(10, 104_857_600), sample(20, nil), sample(30, 0)])
        XCTAssertNil(rates[0])
        XCTAssertEqual(rates[1] ?? 0, 10, accuracy: 0.001)
        XCTAssertNil(rates[2])
        XCTAssertNil(rates[3])
    }

    func testActivityLogKeepsTheNewestEntriesOnly() {
        let entries = (0..<ActivityLogStore.maxEntries).map {
            ActivityEntry(date: Date(timeIntervalSince1970: Double($0)), kind: .event, tone: .neutral, title: "\($0)", note: "")
        }
        let newest = ActivityEntry(date: Date(), kind: .action, tone: .good, title: "new", note: "")
        let result = ActivityLogStore.prepending(newest, to: entries)
        XCTAssertEqual(result.count, ActivityLogStore.maxEntries)
        XCTAssertEqual(result.first?.title, "new")
    }

    func testFormatsDurationsLikeTheCore() {
        XCTAssertEqual(Format.duration(30), "1 min")
        XCTAssertEqual(Format.duration(5 * 3600), "5 h")
        XCTAssertEqual(Format.duration(4 * 86400), "4 days")
        XCTAssertEqual(Format.gigabytes(2_791_728_742), "2.6 GB")
    }
}
