import SwiftUI

/// Polls `vitals-ffi` on an adaptive interval (§4 sampling notes: 30s
/// when green, faster once a rule has fired) and republishes the result
/// for SwiftUI. `pollInterval(for:)` is a pure function so the adaptive
/// behavior is testable without a real timer. Actions live in
/// `AppState+Actions.swift`, notifications and Guard in
/// `AppState+Alerts.swift`.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var report: VitalsReport?
    @Published private(set) var lastError: VitalsCollectError?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var history: [MetricSample] = []
    @Published private(set) var summary: HealthSummary?
    @Published private(set) var menuBar = MenuBarState(fill: 0, tone: .normal, label: nil)
    @Published var activity: [ActivityEntry] = []
    @Published var busy: Set<String> = []
    @Published var toast: Toast?
    @Published var pendingConfirmation: ActionRequest?
    /// Set while the first reading after a "free" action is outstanding,
    /// so the summary can say it is measuring instead of showing a stale
    /// verdict.
    @Published var measuring = false
    /// Derived once per reading instead of in every view body.
    @Published private(set) var cpuSaturatedNow = false
    @Published private(set) var diskBusyNow = false

    @AppStorage(AppNotifier.alertStorageKey) var notifyOnAlerts = true
    var lastAlertSeverities: [String: Severity] = [:]
    var lastNotifiedAt: [String: Date] = [:]
    var lastPressure: PressureLevel?
    var lastGuardRun: Date?
    var toastTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var lastHistorySave = Date.distantPast
    /// History is written at most this often; the samples in between are
    /// only lost if the app is killed, and `flushHistory` covers a normal
    /// quit.
    nonisolated static let historySaveInterval: TimeInterval = 60

    nonisolated static let greenInterval: TimeInterval = 30
    nonisolated static let alertInterval: TimeInterval = 10
    /// How long a rule must stay quiet before it's allowed to notify
    /// again — separate from the poll interval, since a finding
    /// hovering right at its threshold can cross in and out every poll.
    nonisolated static let notificationCooldown: TimeInterval = 15 * 60

    private let historyStore = MetricHistoryStore()
    let activityStore = ActivityLogStore()
    let defaults = UserDefaults.standard

    init() {
        AppSettings.register(in: defaults)
        history = historyStore.load()
        activity = activityStore.load()
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    deinit {
        pollTask?.cancel()
    }

    var idleMinutes: Int { AppSettings.idleMinutes(in: defaults) }
    var protectedItems: [String] { AppSettings.protectedItems(in: defaults) }

    func flushHistory() {
        historyStore.save(history)
        lastHistorySave = Date()
    }

    /// `fresh` skips the core's probe caches: right after an action the
    /// report has to show what just changed.
    func refresh(fresh: Bool = false) async {
        let overrides = AppSettings.overridesJSON(idleMinutes: idleMinutes, protected: protectedItems, fresh: fresh)
        let result = await Task.detached(priority: .utility) {
            VitalsBridge.collect(overridesJSON: overrides)
        }.value

        switch result {
        case .success(let report):
            apply(report)
        case .failure(let error):
            self.lastError = error
        }
        lastUpdated = Date()
    }

    private func apply(_ report: VitalsReport) {
        self.report = report
        self.lastError = nil
        history = MetricHistory.appending(.from(report: report), to: history)
        if Date().timeIntervalSince(lastHistorySave) >= Self.historySaveInterval {
            flushHistory()
        }
        measuring = false

        cpuSaturatedNow = cpuSaturated()
        diskBusyNow = diskBusy()
        let summary = HealthSummary.from(report: report, cpuSaturated: cpuSaturatedNow)
        self.summary = summary
        menuBar = MenuBarState.from(report: report, summary: summary)

        logPressureChange(report.system.memory.pressureLevel)
        notifyAboutNewAlertingFindings(in: report)
        notifySustainedLoad()
        runGuardIfNeeded(report)
    }

    func log(_ title: String, note: String = "", kind: ActivityEntry.Kind, tone: ActivityEntry.Tone) {
        let entry = ActivityEntry(date: Date(), kind: kind, tone: tone, title: title, note: note)
        activity = ActivityLogStore.prepending(entry, to: activity)
        activityStore.save(activity)
    }

    private func logPressureChange(_ pressure: PressureLevel) {
        defer { lastPressure = pressure }
        guard let previous = lastPressure, previous != pressure else { return }
        let tone: ActivityEntry.Tone = pressure == .critical ? .critical : pressure == .warn ? .warning : .good
        log("Memory pressure: \(pressure.label.lowercased())", note: "was \(previous.label.lowercased())", kind: .event, tone: tone)
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
            var seconds = Self.pollInterval(for: report)
            if seconds == Self.alertInterval {
                seconds = TimeInterval(max(defaults.integer(forKey: AppSettings.Key.refreshSeconds), 5))
            }
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    }
}
