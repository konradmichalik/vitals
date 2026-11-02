import SwiftUI

/// Four tappable tiles, each opening the metric's detail screen.
struct MetricTiles: View {
    let report: VitalsReport
    let history: [MetricSample]
    let onSelect: (MetricKind) -> Void

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        let recent = MetricHistory.window(history, range: .fifteenMinutes, now: Date())
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(MetricKind.allCases, id: \.self) { kind in
                tile(kind, recent: recent)
            }
        }
    }

    private func tile(_ kind: MetricKind, recent: [MetricSample]) -> some View {
        let tone = TileTone.tone(for: kind, report: report)
        let values = MetricSeries.values(kind, from: recent, performanceCores: report.system.cores.performance)
        return Button { onSelect(kind) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    if let symbol = tone.symbol {
                        Image(systemName: symbol)
                            .font(.caption)
                            .foregroundStyle(tone.color)
                    }
                    Text(value(kind))
                        .font(.callout.weight(.semibold).monospacedDigit())
                }
                Text(caption(kind))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if values.count >= 2 {
                    Sparkline(values: values, color: tone.color) { index in
                        values.indices.contains(index) ? MetricSeries.format(kind, values[index]) : ""
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(tone.color.opacity(tone == .neutral ? 0.06 : 0.12), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title(kind))
        .accessibilityValue("\(value(kind)), \(caption(kind))")
        .accessibilityHint("Shows details")
        .accessibilityAddTraits(.isButton)
    }

    private func title(_ kind: MetricKind) -> String {
        switch kind {
        case .cpu: return "CPU"
        case .memory: return "Pressure"
        case .load: return "Load"
        case .swap: return "Swap"
        }
    }

    private func value(_ kind: MetricKind) -> String {
        guard kind != .memory else { return TileTone.pressureLabel(report.system.memory.pressureLevel) }
        return MetricSeries.format(kind, MetricSeries.current(kind, report: report))
    }

    private func caption(_ kind: MetricKind) -> String {
        switch kind {
        case .cpu: return "in use"
        case .memory: return "\(report.system.memory.usedPercent)% used"
        case .load: return "\(report.system.cores.performance) performance cores"
        case .swap: return "in swap"
        }
    }
}
