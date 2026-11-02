import SwiftUI

/// State, cause and the one suggested action, followed by the measured result of the last action.
struct VerdictHero: View {
    let verdict: Verdict
    let focus: MetricKind?
    let outcome: ActionOutcome
    let onAction: (SuggestedAction, String?) -> Void
    let onWhy: (MetricKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(tone.color)
                    .accessibilityHidden(true)
                Text(verdict.headline)
                    .font(.title3.weight(.semibold))
            }
            if !verdict.detail.isEmpty {
                Text(verdict.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let culprit = verdict.culprit {
                Text("\(culprit.label) \(culprit.reason).")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            outcomeView
            if !isChecking {
                actionRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tone: Tone {
        switch verdict.severity {
        case .critical: return .critical
        case .warn: return .warn
        case .info, nil: return .neutral
        }
    }

    private var symbol: String {
        tone.symbol ?? "checkmark.circle"
    }

    private var isChecking: Bool {
        if case .checking = outcome { return true }
        return false
    }

    private var isRunning: Bool {
        if case .running = outcome { return true }
        return false
    }

    @ViewBuilder
    private var outcomeView: some View {
        switch outcome {
        case .checking:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Checking…").font(.callout.weight(.medium))
                }
                Text("Waiting for the next measurement. Swap can stay high for a while after memory is freed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        case .failed(_, let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Tone.critical.color)
                .fixedSize(horizontal: false, vertical: true)
        case .idle, .running:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        if verdict.action != nil || focus != nil {
            HStack(spacing: 8) {
                if let action = verdict.action {
                    Button(buttonTitle(for: action)) { onAction(action, verdict.culprit?.label) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isRunning)
                    if let estimate = action.estimate {
                        Text(estimate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let focus {
                    Button("Why?") { onWhy(focus) }
                        .buttonStyle(.link)
                        .controlSize(.small)
                        .accessibilityLabel("Why? Show \(Self.metricName(focus)) details")
                }
            }
        }
    }

    /// A `kill_process` target is an internal `pid@start` identity, so the culprit's name stands in for it.
    private func buttonTitle(for action: SuggestedAction) -> String {
        let target = action.action == "kill_process" ? verdict.culprit?.label : action.target
        return [action.label, target].compactMap { $0 }.joined(separator: " ")
    }
}

extension VerdictHero {
    private static func metricName(_ kind: MetricKind) -> String {
        switch kind {
        case .cpu: return "CPU"
        case .memory: return "memory"
        case .load: return "load"
        case .swap: return "swap"
        }
    }

    /// The metric whose detail explains the verdict, nil for verdicts that no metric explains.
    static func focus(for findings: [Finding]) -> MetricKind? {
        switch findings.verdictFinding?.rule {
        case "load_status": return .load
        case "runaway_processes": return .cpu
        case "memory_pressure": return .memory
        default: return nil
        }
    }
}
