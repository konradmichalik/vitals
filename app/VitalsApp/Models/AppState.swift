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

    @AppStorage(AppNotifier.alertStorageKey) private var notifyOnAlerts = true
    private var lastAlertSeverities: [String: Severity] = [:]
    private var pollTask: Task<Void, Never>?

    nonisolated static let greenInterval: TimeInterval = 30
    nonisolated static let alertInterval: TimeInterval = 10

    private let historyStore = MetricHistoryStore()

    init() {
        history = historyStore.load()
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    deinit {
        pollTask?.cancel()
    }

    func refresh() async {
        let result = await Task.detached(priority: .utility) {
            VitalsBridge.collect()
        }.value

        switch result {
        case .success(let report):
            self.report = report
            self.lastError = nil
            history = MetricHistory.appending(.from(report: report), to: history)
            historyStore.save(history)
            notifyAboutNewAlertingFindings(in: report.findings)
        case .failure(let error):
            self.lastError = error
        }
        lastUpdated = Date()
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
        for rule in newlyAlerting {
            guard let finding = findings.first(where: { $0.rule == rule }) else { continue }
            let title = finding.severity == .critical ? "Vitals — critical" : "Vitals — warning"
            AppNotifier.notify(id: rule, title: title, body: finding.message)
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
