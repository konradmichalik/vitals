import Foundation

enum ActionOutcomeEvent {
    case started(SuggestedAction)
    case finished(Result<String, ActionRunnerError>, at: Date)
    case reportArrived(timestamp: Date)
    case tick(now: Date)
}

/// Tracks an action from click until a measurement taken after it
/// finished shows its effect. `reduce` is pure: callers pass every
/// timestamp in, so tests need no clock.
enum ActionOutcome: Equatable {
    case idle
    case running(SuggestedAction)
    case checking(SuggestedAction, since: Date)
    case failed(SuggestedAction, message: String, at: Date)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    /// "Checking…" cannot hang when polling stalls, and a failure does not stay pinned under later verdicts.
    static let displayTimeout: TimeInterval = 60

    static func reduce(_ state: ActionOutcome, _ event: ActionOutcomeEvent) -> ActionOutcome {
        switch (state, event) {
        case (_, .started(let action)):
            return .running(action)
        case (.running(let action), .finished(.success, let finishedAt)):
            return .checking(action, since: finishedAt)
        case (.running(let action), .finished(.failure(let error), let finishedAt)):
            return .failed(action, message: error.message, at: finishedAt)
        case (.checking(_, let since), .reportArrived(let timestamp)):
            return timestamp > since ? .idle : state
        case (.checking(_, let since), .tick(let now)), (.failed(_, _, let since), .tick(let now)):
            // A negative interval means the clock stepped back; waiting for it to catch up could take hours.
            let elapsed = now.timeIntervalSince(since)
            return elapsed >= displayTimeout || elapsed < 0 ? .idle : state
        default:
            return state
        }
    }
}
