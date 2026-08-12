import Foundation

/// Polls `vitals-ffi` on an adaptive interval (§4 sampling notes: 30s
/// when green, 10s once a rule has fired) and republishes the result for
/// SwiftUI. `pollInterval(for:)` is a pure function so the adaptive
/// behavior is testable without a real timer.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var report: VitalsReport?
    @Published private(set) var lastError: VitalsCollectError?
    @Published private(set) var lastUpdated: Date?

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
        case .failure(let error):
            self.lastError = error
        }
        lastUpdated = Date()
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
