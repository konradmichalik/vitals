import Foundation

extension AppState {
    func cpuSaturated() -> Bool {
        let minutes = max(defaults.integer(forKey: AppSettings.Key.cpuMinutes), 1)
        return SustainedCheck.isSustained(
            history.map { SustainedCheck.Point(date: $0.timestamp, value: $0.cpuUsedPercent) },
            above: HealthSummary.cpuSaturatedPercent,
            for: TimeInterval(minutes * 60),
            now: Date()
        )
    }

    /// Disk activity above this, sustained, counts as busy. A judgement
    /// call, not a macOS value: an SSD handles far more in bursts.
    static let diskBusyMBps: Double = 150

    func diskBusy() -> Bool {
        let minutes = max(defaults.integer(forKey: AppSettings.Key.diskMinutes), 1)
        let rates = MetricHistory.diskRates(history)
        return SustainedCheck.isSustained(
            zip(history, rates).map { SustainedCheck.Point(date: $0.timestamp, value: $1) },
            above: Self.diskBusyMBps,
            for: TimeInterval(minutes * 60),
            now: Date()
        )
    }

    private var warnThreshold: PressureLevel {
        PressureLevel(rawValue: defaults.string(forKey: AppSettings.Key.warnLevel) ?? "") ?? .warn
    }

    /// Quiet hours hold back banners, except critical ones when the user
    /// lets those break through. Guard keeps working either way.
    func bannersAllowed(critical: Bool) -> Bool {
        guard notifyOnAlerts else { return false }
        guard defaults.bool(forKey: AppSettings.Key.quietHours), AppSettings.isQuietTime(Date()) else { return true }
        return critical && defaults.bool(forKey: AppSettings.Key.breakThrough)
    }

    /// `lastAlertSeverities` is updated unconditionally, even with
    /// notifications turned off — otherwise turning them on later would
    /// treat every already-alerting finding as new and fire a
    /// notification storm for state that isn't actually new.
    func notifyAboutNewAlertingFindings(in report: VitalsReport) {
        let findings = report.findings
        let current = FindingAlertTransition.alertingSeverities(in: findings)
        let newlyAlerting = FindingAlertTransition.newlyAlerting(previous: lastAlertSeverities, current: current)
        lastAlertSeverities = current

        let now = Date()
        for rule in newlyAlerting.sorted() {
            guard let finding = findings.first(where: { $0.rule == rule }) else { continue }
            let isCritical = finding.severity == .critical
            if rule == "memory_pressure", report.system.memory.pressureLevel.rank < warnThreshold.rank { continue }
            guard bannersAllowed(critical: isCritical),
                  FindingAlertTransition.shouldNotify(
                    rule: rule, now: now, lastNotifiedAt: lastNotifiedAt, cooldown: Self.notificationCooldown
                  )
            else { continue }
            lastNotifiedAt[rule] = now
            notify(finding: finding, report: report, critical: isCritical)
        }
    }

    private func notify(finding: Finding, report: VitalsReport, critical: Bool) {
        let idle = report.idleBytes
        if finding.rule == "memory_pressure", idle > 0 {
            AppNotifier.notify(
                id: finding.rule,
                title: critical ? "Memory pressure is critical" : "Memory is getting tight",
                body: "Idle projects and sessions hold \(Format.gigabytes(idle)).",
                kind: critical ? .critical : .warning,
                category: AppNotifier.freeIdleCategory
            )
            return
        }
        AppNotifier.notify(
            id: finding.rule,
            title: critical ? "Vitals — critical" : "Vitals — warning",
            body: finding.message,
            kind: critical ? .critical : .warning
        )
    }

    private struct SustainedAlert {
        let key: String
        let title: String
        let body: String
    }

    func notifySustainedLoad() {
        var alerts: [SustainedAlert] = []
        if cpuSaturated() {
            alerts.append(SustainedAlert(key: "cpu_saturated", title: "CPU saturated", body: "CPU has been above 90% for a while."))
        }
        if diskBusy() {
            alerts.append(SustainedAlert(key: "disk_busy", title: "Disk busy", body: "Disk activity has stayed above 150 MB/s."))
        }
        let now = Date()
        for alert in alerts {
            let key = alert.key
            let body = alert.body
            guard bannersAllowed(critical: false),
                  FindingAlertTransition.shouldNotify(
                    rule: key, now: now, lastNotifiedAt: lastNotifiedAt, cooldown: Self.notificationCooldown
                  )
            else { continue }
            lastNotifiedAt[key] = now
            log(alert.title, note: body, kind: .event, tone: .warning)
            AppNotifier.notify(id: key, title: "Vitals — warning", body: body, kind: .warning)
        }
    }

    func runGuardIfNeeded(_ report: VitalsReport) {
        let scopes = AppSettings.guardScopes(
            ddev: defaults.bool(forKey: AppSettings.Key.guardDdev),
            agents: defaults.bool(forKey: AppSettings.Key.guardAgents),
            orphans: defaults.bool(forKey: AppSettings.Key.guardOrphans)
        )
        let threshold = PressureLevel(rawValue: defaults.string(forKey: AppSettings.Key.guardLevel) ?? "") ?? .critical
        let input = GuardPolicy.Input(
            enabled: defaults.bool(forKey: AppSettings.Key.guardEnabled),
            pressure: report.system.memory.pressureLevel,
            threshold: threshold,
            idleBytes: report.idleBytes,
            scopes: scopes
        )
        guard GuardPolicy.shouldRun(input, lastRun: lastGuardRun, now: Date()) else { return }
        lastGuardRun = Date()
        perform(.freeIdle(bytes: report.idleBytes, scope: scopes, byGuard: true))
    }
}
