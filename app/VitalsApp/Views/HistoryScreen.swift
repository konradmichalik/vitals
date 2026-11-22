import Charts
import SwiftUI

struct HistoryScreen: View {
    @EnvironmentObject private var appState: AppState
    @State var metric: Metric
    @State private var lastHour = true
    @State private var hovered: Int?

    private var samples: [MetricSample] {
        let window: TimeInterval = lastHour ? 3600 : 900
        let now = Date()
        return appState.history.filter { now.timeIntervalSince($0.timestamp) <= window }
    }

    var body: some View {
        let visible = samples
        let values = metric.values(visible)
        VStack(alignment: .leading, spacing: 12) {
            Picker("Metric", selection: $metric) {
                ForEach(Metric.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            header(values: values, samples: visible)
            chart(values: values)
            pressureStrip(visible)
            stats(values: values)
            changes
        }
    }

    private func header(values: [Double?], samples: [MetricSample]) -> some View {
        let index = hovered ?? (values.count - 1)
        let value = values.indices.contains(index) ? values[index] : nil
        let formatted = metric.format(value)
        let when = hovered.flatMap { samples.indices.contains($0) ? Format.clock(samples[$0].timestamp) : nil } ?? "now"
        return HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(metric.label) \(when)").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("\(formatted.number) \(formatted.unit)")
                    .font(.system(size: 28, weight: .bold))
                    .monospacedDigit()
            }
            Spacer()
            Picker("Range", selection: $lastHour) {
                Text("15m").tag(false)
                Text("1h").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 100)
        }
    }

    private func chart(values: [Double?]) -> some View {
        let tint = (metric == .memory || metric == .swap) && appState.report?.system.memory.pressureLevel != .normal
            ? Theme.color(for: appState.report?.system.memory.pressureLevel ?? .normal)
            : Color.secondary
        return Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                if let value {
                    AreaMark(x: .value("Sample", index), y: .value(metric.label, value))
                        .foregroundStyle(tint.opacity(0.15))
                    LineMark(x: .value("Sample", index), y: .value(metric.label, value))
                        .foregroundStyle(tint)
                }
            }
            if let hovered {
                RuleMark(x: .value("Sample", hovered)).foregroundStyle(.tertiary)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
        .chartOverlay { proxy in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hovered = proxy.value(atX: location.x, as: Int.self).map { min(max($0, 0), values.count - 1) }
                    case .ended:
                        hovered = nil
                    }
                }
        }
        .frame(height: 120)
        .padding(8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    /// The pressure level macOS reported at each sample, as a strip under
    /// the chart — the one signal that precedes crashes and freezes.
    private func pressureStrip(_ samples: [MetricSample]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 1) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    Rectangle().fill(sample.memoryPressure == .normal ? Theme.fill : Theme.color(for: sample.memoryPressure))
                }
            }
            .frame(height: 4)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            Text("Memory pressure as reported by macOS: normal, warning, critical")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }

    private struct Stat: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    private func stats(values: [Double?]) -> some View {
        let present = values.compactMap { $0 }
        let now = metric.format(present.last)
        let peak = metric.format(present.max())
        let third: Stat
        if metric == .memory {
            third = Stat(label: "Pressure", value: appState.report?.system.memory.pressureLevel.label ?? "–")
        } else {
            let average = present.isEmpty ? nil : present.reduce(0, +) / Double(present.count)
            let formatted = metric.format(average)
            third = Stat(label: "Average", value: "\(formatted.number) \(formatted.unit)")
        }
        let items = [
            Stat(label: "Now", value: "\(now.number) \(now.unit)"),
            Stat(label: "Peak", value: "\(peak.number) \(peak.unit)"),
            third,
        ]
        return HStack(spacing: 6) {
            ForEach(items) { stat in
                VStack(alignment: .leading, spacing: 1) {
                    Text(stat.label).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(stat.value).font(.system(size: 13, weight: .semibold)).monospacedDigit().lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            }
        }
    }

    @ViewBuilder
    private var changes: some View {
        let window: TimeInterval = lastHour ? 3600 : 900
        let recent = appState.activity.filter { Date().timeIntervalSince($0.date) <= window }.prefix(4)
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "What changed")
                CardList(items: Array(recent)) { entry in
                    ActivityRow(entry: entry)
                }
            }
        }
    }
}
