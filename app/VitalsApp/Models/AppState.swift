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
    @Published private(set) var activity: [ActivityEntry] = []

    @AppStorage(AppNotifier.alertStorageKey) private var notifyOnAlerts = true
    private var lastAlertSeverities: [String: Severity] = [:]
    private var lastNotifiedAt: [String: Date] = [:]
    private var pollTask: Task<Void, Never>?
    private var previousReport: VitalsReport?
    private var activityWrites: Task<Void, Never>?

    nonisolated static let greenInterval: TimeInterval = 30
    nonisolated static let alertInterval: TimeInterval = 10
    /// How long a rule must stay quiet before it's allowed to notify
    /// again — separate from the poll interval, since a finding
    /// hovering right at its threshold can cross in and out every poll.
    nonisolated static let notificationCooldown: TimeInterval = 15 * 60

    private let historyStore = MetricHistoryStore()
    private let snoozeStore = SnoozeStore()
    private let activityStore = ActivityLogStore()

    init() {
        history = historyStore.load()
        let bootTime = SnoozeStore.currentBootTime()
        snoozes = snoozeStore.load().filter { SnoozeStore.isActive($0, now: Date(), bootTime: bootTime) }
        let store = activityStore
        Task { [weak self] in
            let loaded = await Task.detached(priority: .utility) { store.load() }.value
            guard let self else { return }
            // A write may have landed before the load finished, so dedupe by id.
            var seen = Set<UUID>()
            let merged = (loaded + self.activity).filter { seen.insert($0.id).inserted }
            self.activity = ActivityLogStore.pruned(merged, now: Date())
        }
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

    func unsnooze(rule: String) {
        snoozes = snoozes.filter { $0.rule != rule }
        snoozeStore.save(snoozes)
    }

    private func pruneExpiredSnoozes() {
        let now = Date()
        let bootTime = SnoozeStore.currentBootTime()
        let active = snoozes.filter { SnoozeStore.isActive($0, now: now, bootTime: bootTime) }
        guard active.count != snoozes.count else { return }
        snoozes = active
        snoozeStore.save(active)
    }

    func perform(_ action: SuggestedAction) {
        // `.finished` carries no action identity, so a second run would finish the wrong one.
        if case .running = outcome { return }
        outcome = ActionOutcome.reduce(outcome, .started(action))
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                ActionRunner.run(action)
            }.value
            let finishedAt = Date()
            outcome = ActionOutcome.reduce(outcome, .finished(result, at: finishedAt))
            recordActivity([ActivityEntry.action(for: action, result: result, at: finishedAt)], now: finishedAt)
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
            pruneExpiredSnoozes()
            outcome = ActionOutcome.reduce(outcome, .reportArrived(timestamp: startedAt))
            history = MetricHistory.appending(.from(report: report), to: history)
            historyStore.save(history)
            notifyAboutNewAlertingFindings(in: report.findings)
            let events = ReportDiff.events(previous: previousReport, current: report, at: startedAt)
            previousReport = report
            recordActivity(events, now: startedAt)
        case .failure(let error):
            self.lastError = error
        }
        let now = Date()
        lastUpdated = now
        outcome = ActionOutcome.reduce(outcome, .tick(now: now))
    }

    /// Writes are chained so two quick appends cannot read the same file and drop one.
    private func recordActivity(_ entries: [ActivityEntry], now: Date) {
        guard !entries.isEmpty else { return }
        activity = ActivityLogStore.pruned(activity + entries, now: now)
        let store = activityStore
        let previous = activityWrites
        activityWrites = Task.detached(priority: .utility) {
            await previous?.value
            store.append(entries, now: now)
        }
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
            AppNotifier.notify(id: rule, title: title, body: finding.message, kind: isCritical ? .critical : .warning, rule: rule)
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
