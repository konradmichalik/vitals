import Charts
import SwiftUI

/// Line chart of one metric over the selected range. The line stays neutral, the tone color only marks the load threshold rule.
struct HistoryChart: View {
    let kind: MetricKind
    let samples: [MetricSample]
    let values: [Double]
    let tone: Tone
    let now: Date

    @State private var selectedIndex: Int?
    @State private var selectedDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            chart
            Text(selectionText ?? " ")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                LineMark(x: .value("Time", sample.timestamp), y: .value("Value", values[index]))
                    .foregroundStyle(Color.secondary)
                    .interpolationMethod(.catmullRom)
            }
            if kind == .load {
                RuleMark(y: .value("Limit", 1.0))
                    .foregroundStyle(tone.color)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("1.0×").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            if let selectedIndex, samples.indices.contains(selectedIndex) {
                RuleMark(x: .value("Selected", samples[selectedIndex].timestamp))
                    .foregroundStyle(Color.secondary.opacity(0.4))
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYScale(domain: .automatic(includesZero: kind != .memory))
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 120)
        .onChange(of: selectedDate) { _, date in
            guard let date else { return }
            selectedIndex = samples.indices.min {
                abs(samples[$0].timestamp.timeIntervalSince(date)) < abs(samples[$1].timestamp.timeIntervalSince(date))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(selectionText ?? "No data")
        .accessibilityAdjustableAction(adjust)
    }

    private var label: String {
        switch kind {
        case .cpu: return "CPU history"
        case .memory: return "Memory used history"
        case .load: return "Load history"
        case .swap: return "Swap history"
        }
    }

    private var effectiveIndex: Int? {
        if let selectedIndex, samples.indices.contains(selectedIndex) { return selectedIndex }
        return samples.indices.last
    }

    private var selectionText: String? {
        guard let index = effectiveIndex else { return nil }
        return "\(MetricSeries.ago(from: samples[index].timestamp, now: now)): \(MetricSeries.format(kind, values[index]))"
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        guard let last = samples.indices.last else { return }
        let current = effectiveIndex ?? last
        switch direction {
        case .increment: selectedIndex = min(current + 1, last)
        case .decrement: selectedIndex = max(current - 1, 0)
        @unknown default: break
        }
    }
}
