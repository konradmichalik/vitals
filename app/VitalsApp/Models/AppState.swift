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

    @AppStorage(CriticalFindingNotifier.storageKey) private var notifyOnCritical = true
    private var lastCriticalRules: Set<String> = []
    private var pollTask: Task<Void, Never>?

    nonisolated static let greenInterval: TimeInterval = 30
    nonisolated static let alertInterval: TimeInterval = 10

    init() {
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
            notifyAboutNewCriticalFindings(in: report.findings)
        case .failure(let error):
            self.lastError = error
        }
        lastUpdated = Date()
    }

    /// `lastCriticalRules` is updated unconditionally, even with
    /// notifications turned off — otherwise turning them on later would
    /// treat every already-critical finding as newly critical and fire a
    /// notification storm for state that isn't actually new.
    private func notifyAboutNewCriticalFindings(in findings: [Finding]) {
        let currentCritical = CriticalFindingTransition.criticalRuleNames(in: findings)
        let newlyCritical = CriticalFindingTransition.newlyCritical(previous: lastCriticalRules, current: currentCritical)
        lastCriticalRules = currentCritical

        guard notifyOnCritical else { return }
        for rule in newlyCritical {
            guard let finding = findings.first(where: { $0.rule == rule }) else { continue }
            CriticalFindingNotifier.notify(rule: rule, message: finding.message)
        }
    }

    nonisolated static func pollInterval(for report: VitalsReport?) -> TimeInterval {
        guard let report, !report.findings.isEmpty else { return greenInterval }
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
