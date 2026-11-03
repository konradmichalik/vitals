import SwiftUI

private struct DetailHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }
}

/// The two lists under the chart on the metric detail screen.
struct WhatChangedList: View {
    let entries: [ActivityEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DetailHeading(title: "What changed")
            if entries.isEmpty {
                Text("Nothing changed in this range.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.date, format: .dateTime.hour().minute())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(entry.title).font(.callout)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    static func entries(_ activity: [ActivityEntry], range: HistoryRange, now: Date) -> [ActivityEntry] {
        let cutoff = now.addingTimeInterval(-range.seconds)
        return Array(activity.filter { $0.date >= cutoff && $0.date <= now }.sorted { $0.date > $1.date }.prefix(5))
    }
}

struct BiggestShareList: View {
    let kind: MetricKind
    let consumers: [Consumer]

    var body: some View {
        let byMemory = kind == .memory || kind == .swap
        let top = ConsumerSort.sorted(consumers, by: byMemory ? .memory : .cpu).prefix(3)
        VStack(alignment: .leading, spacing: 4) {
            DetailHeading(title: "Biggest share")
            ForEach(Array(top)) { consumer in
                HStack {
                    Text(consumer.label).font(.callout).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(byMemory ? MetricSeries.formatBytes(consumer.memBytes) : "\(Int(consumer.cpuPercent.rounded()))%")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
