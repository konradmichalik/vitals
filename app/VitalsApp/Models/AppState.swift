import SwiftUI

/// Polls `vitals-ffi` on an adaptive interval (§4 sampling notes: 30s
/// when green, 10s once a rule has fired) and republishes the result for
/// SwiftUI. `pollInterval(for:)` is a pure function so the adaptive
/// behavior is testable without a real timer.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var report: VitalsReport?
    @Published private(set) var lastError: VitalsCollectError?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var history: [MetricSample] = []
    @Published private(set) var outcome: ActionOutcome = .idle
    @Published private(set) var snoozes: [Snooze] = []

    @AppStorage(AppNotifier.alertStorageKey) private var notifyOnAlerts = true
    private var lastAlertSeverities: [String: Severity] = [:]
    private var lastNotifiedAt: [String: Date] = [:]
    private var pollTask: Task<Void, Never>?

    nonisolated static let greenInterval: TimeInterval = 30
    nonisolated static let alertInterval: TimeInterval = 10
    /// How long a rule must stay quiet before it's allowed to notify
    /// again — separate from the poll interval, since a finding
    /// hovering right at its threshold can cross in and out every poll.
    nonisolated static let notificationCooldown: TimeInterval = 15 * 60

    private let historyStore = MetricHistoryStore()
    private let snoozeStore = SnoozeStore()

    init() {
        history = historyStore.load()
        let bootTime = SnoozeStore.currentBootTime()
        snoozes = snoozeStore.load().filter { SnoozeStore.isActive($0, now: Date(), bootTime: bootTime) }
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    deinit {
        pollTask?.cancel()
    }

    /// The traffic light and status pill keep using all findings, so a snooze never hides the dot.
    var visibleFindings: [Finding] {
        let now = Date()
        let bootTime = SnoozeStore.currentBootTime()
        return (report?.findings ?? []).filter {
            !SnoozeStore.isSnoozed(rule: $0.rule, snoozes: snoozes, now: now, bootTime: bootTime)
        }
    }

    func snooze(rule: String, for duration: SnoozeDuration) {
        let entry = SnoozeStore.snooze(
            rule: rule, for: duration, now: Date(), bootTime: SnoozeStore.currentBootTime(), calendar: .current
        )
        snoozes = snoozes.filter { $0.rule != rule } + [entry]
        snoozeStore.save(snoozes)
    }

    func perform(_ action: SuggestedAction) {
        // `.finished` carries no action identity, so a second run would finish the wrong one.
        if case .running = outcome { return }
        outcome = ActionOutcome.reduce(outcome, .started(action))
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                ActionRunner.run(action)
            }.value
            outcome = ActionOutcome.reduce(outcome, .finished(result, at: Date()))
            if case .success = result {
                await refresh()
            }
        }
    }

    func refresh() async {
        let startedAt = Date()
        let result = await Task.detached(priority: .utility) {
            VitalsBridge.collect()
        }.value

        switch result {
        case .success(let report):
            self.report = report
            self.lastError = nil
            outcome = ActionOutcome.reduce(outcome, .reportArrived(timestamp: startedAt))
            history = MetricHistory.appending(.from(report: report), to: history)
            historyStore.save(history)
            notifyAboutNewAlertingFindings(in: report.findings)
        case .failure(let error):
            self.lastError = error
        }
        let now = Date()
        lastUpdated = now
        outcome = ActionOutcome.reduce(outcome, .tick(now: now))
    }

    /// `lastAlertSeverities` is updated unconditionally, even with
    /// notifications turned off — otherwise turning them on later would
    /// treat every already-alerting finding as new and fire a
    /// notification storm for state that isn't actually new.
    private func notifyAboutNewAlertingFindings(in findings: [Finding]) {
        let current = FindingAlertTransition.alertingSeverities(in: findings)
        let newlyAlerting = FindingAlertTransition.newlyAlerting(
            previous: lastAlertSeverities,
            current: current
        )
        lastAlertSeverities = current

        guard notifyOnAlerts else { return }
        let now = Date()
        if UserDefaults.standard.bool(forKey: QuietHours.storageKey), QuietHours.isQuiet(now) { return }
        let bootTime = SnoozeStore.currentBootTime()
        for rule in newlyAlerting {
            guard !SnoozeStore.isSnoozed(rule: rule, snoozes: snoozes, now: now, bootTime: bootTime) else { continue }
            guard let finding = findings.first(where: { $0.rule == rule }) else { continue }
            guard FindingAlertTransition.shouldNotify(
                rule: rule, now: now, lastNotifiedAt: lastNotifiedAt, cooldown: Self.notificationCooldown
            ) else { continue }
            lastNotifiedAt[rule] = now

            let isCritical = finding.severity == .critical
            let title = isCritical ? "Vitals — critical" : "Vitals — warning"
            AppNotifier.notify(id: rule, title: title, body: finding.message, kind: isCritical ? .critical : .warning)
        }
    }

    /// Keyed on severity, not on findings merely existing: info findings
    /// are advisory and frequently permanent (accumulated ballast,
    /// unmanaged containers), so counting them as "something is firing"
    /// pinned the app to the 10s interval forever while the menu bar icon
    /// sat green — polling a monitoring tool three times as often as
    /// needed is exactly the load it exists to prevent.
    nonisolated static func pollInterval(for report: VitalsReport?) -> TimeInterval {
        guard let report, report.findings.contains(where: { $0.severity >= .warn }) else {
            return greenInterval
        }
        return alertInterval
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await refresh()
            let seconds = Self.pollInterval(for: report)
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    }
}
