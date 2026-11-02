import SwiftUI

/// Grouped resource consumers. Rows expand to their children, and only the culprit's action is prominent.
struct ConsumersList: View {
    let consumers: [Consumer]
    let culpritID: String?
    let defaultSort: ConsumerSort
    let isRunning: Bool
    let onAction: (SuggestedAction, String?) -> Void

    @State private var chosenSort: ConsumerSort?
    @State private var expanded: Set<String> = []

    /// Keeps the popover short; the core can send more than 12 groups because runaways are never capped.
    private static let visibleCount = 5

    var body: some View {
        if !consumers.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionHeader(icon: "chart.bar", title: "Consumers")
                    Spacer()
                    Picker("Sort by", selection: sortBinding) {
                        ForEach(ConsumerSort.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Sort consumers by")
                }
                VStack(alignment: .leading, spacing: 0) {
                    let rows = ConsumerSort.visible(
                        consumers, by: sortBinding.wrappedValue, limit: Self.visibleCount, keeping: culpritID
                    )
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, consumer in
                        if index > 0 {
                            Divider()
                        }
                        row(consumer)
                    }
                }
            }
        }
    }

    /// The default follows the verdict until the user picks a sort.
    private var sortBinding: Binding<ConsumerSort> {
        Binding(get: { chosenSort ?? defaultSort }, set: { chosenSort = $0 })
    }

    private func row(_ consumer: Consumer) -> some View {
        let isOpen = expanded.contains(consumer.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                disclosure(consumer, isOpen: isOpen)
                usage(consumer.label, detail: consumer.detail, cpu: consumer.cpuPercent, mem: consumer.memBytes)
                if let action = consumer.action {
                    actionButton(action, culpritLabel: consumer.label, prominent: consumer.id == culpritID)
                }
            }
            .padding(.vertical, 4)
            if isOpen {
                ForEach(Array(consumer.children.enumerated()), id: \.offset) { _, child in
                    HStack(spacing: 6) {
                        usage(child.label, detail: child.detail, cpu: child.cpuPercent, mem: child.memBytes)
                        if let action = child.action {
                            actionButton(action, culpritLabel: child.label, prominent: false)
                        }
                    }
                    .padding(.leading, 22)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private func disclosure(_ consumer: Consumer, isOpen: Bool) -> some View {
        if consumer.children.isEmpty {
            Color.clear.frame(width: 16, height: 16)
        } else {
            Button {
                expanded = isOpen ? expanded.subtracting([consumer.id]) : expanded.union([consumer.id])
            } label: {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(isOpen ? "Collapse \(consumer.label)" : "Expand \(consumer.label)")
        }
    }

    private func usage(_ label: String, detail: String?, cpu: Double, mem: UInt64) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Text(String(format: "%.0f%% · %.1f GB", cpu, Double(mem) / MetricSeries.gib))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func actionButton(_ action: SuggestedAction, culpritLabel: String, prominent: Bool) -> some View {
        let button = Button(action.label) { onAction(action, culpritLabel) }
            .controlSize(.small)
            .disabled(isRunning)
            .accessibilityLabel("\(action.label) \(culpritLabel)")
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}
