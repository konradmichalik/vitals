import SwiftUI

/// The screen behind a tile or a verdict's `Why?`: one metric over time, what changed and who uses most of it.
struct MetricDetailView: View {
    @EnvironmentObject private var appState: AppState
    let kind: MetricKind
    let onSelect: (MetricKind) -> Void

    @State private var range: HistoryRange = .fifteenMinutes

    var body: some View {
        if let report = appState.report {
            detail(report)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(24)
        }
    }

    private func detail(_ report: VitalsReport) -> some View {
        let now = Date()
        let samples = MetricHistory.window(appState.history, range: range, now: now)
        let cores = report.system.cores.performance
        let values = MetricSeries.values(kind, from: samples, performanceCores: cores)
        let current = MetricSeries.values(kind, from: [.from(report: report, timestamp: now)], performanceCores: cores)[0]
        let tone = TileTone.tone(for: kind, report: report)
        return VStack(alignment: .leading, spacing: 12) {
            pickers
            readout(current, tone: tone)
            if samples.count >= 2 {
                HistoryChart(kind: kind, samples: samples, values: values, tone: tone, now: now)
                    .id("\(kind)-\(range.label)")
            } else {
                Text("Collecting history…").font(.callout).foregroundStyle(.secondary)
            }
            stats(report, current: current, peak: max(values.max() ?? current, current))
            WhatChangedList(entries: WhatChangedList.entries(appState.activity, range: range, now: now))
            BiggestShareList(kind: kind, consumers: report.consumers)
        }
        .padding(12)
    }

    private var pickers: some View {
        VStack(spacing: 8) {
            Picker("Metric", selection: Binding(get: { kind }, set: onSelect)) {
                ForEach(MetricKind.allCases, id: \.self) { Text(Self.title($0)).tag($0) }
            }
            Picker("Range", selection: $range) {
                ForEach(HistoryRange.allCases, id: \.self) { Text($0.label).tag($0) }
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func readout(_ current: Double, tone: Tone) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if kind == .memory {
                Text("Memory used").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if let symbol = tone.symbol {
                    Image(systemName: symbol).foregroundStyle(tone.color).accessibilityHidden(true)
                }
                Text(MetricSeries.format(kind, current)).font(.title.weight(.semibold).monospacedDigit())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func stats(_ report: VitalsReport, current: Double, peak: Double?) -> some View {
        HStack(alignment: .top, spacing: 16) {
            stat("Now", MetricSeries.format(kind, current))
            stat("Peak \(range.label)", peak.map { MetricSeries.format(kind, $0) } ?? "No data")
            switch kind {
            case .memory, .swap: stat("Pressure", TileTone.pressureLabel(report.system.memory.pressureLevel))
            case .load: stat("Limit", "1.0× / 1.5×")
            case .cpu: EmptyView()
            }
            Spacer(minLength: 0)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    private static func title(_ kind: MetricKind) -> String {
        switch kind {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .load: return "Load"
        case .swap: return "Swap"
        }
    }
}
