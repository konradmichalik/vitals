import SwiftUI

struct OverviewScreen: View {
    @EnvironmentObject private var appState: AppState
    let report: VitalsReport
    let open: (Screen) -> Void

    @State private var sortByCPU = false
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeroCard(report: report, open: open)
            tiles
            if !report.quickWinList.isEmpty {
                quickWins
            }
            consumers
        }
    }

    private var tiles: some View {
        HStack(spacing: 6) {
            ForEach(Metric.allCases) { metric in
                MetricTile(metric: metric, report: report) { open(.history(metric)) }
            }
        }
    }

    private var quickWins: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Quick wins")
            CardList(items: report.quickWinList) { win in
                QuickWinRow(win: win)
            }
        }
    }

    private var sortedGroups: [ConsumerGroup] {
        report.consumerGroups
            .filter { sortByCPU ? $0.cpuPercent > 0 : $0.memBytes > 0 }
            .sorted { sortByCPU ? $0.cpuPercent > $1.cpuPercent : $0.memBytes > $1.memBytes }
    }

    private var consumers: some View {
        let groups = sortedGroups
        let limit = report.quickWinList.count > 1 ? 3 : 4
        let shown = showAll ? groups : Array(groups.prefix(limit))
        let rest = groups.dropFirst(shown.count)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(text: "Top consumers")
                Spacer()
                Picker("Sort by", selection: $sortByCPU) {
                    Text("Memory").tag(false)
                    Text("CPU").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 130)
                .controlSize(.small)
            }
            VStack(spacing: 0) {
                CardList(items: shown) { group in
                    ConsumerRow(group: group, sortByCPU: sortByCPU, maxValue: maxValue(groups)) { open(.group(group.id)) }
                }
                if !rest.isEmpty {
                    moreRow(Array(rest))
                }
            }
        }
    }

    private func maxValue(_ groups: [ConsumerGroup]) -> Double {
        groups.map { sortByCPU ? $0.cpuPercent : Double($0.memBytes) }.max() ?? 1
    }

    private func moreRow(_ rest: [ConsumerGroup]) -> some View {
        let total = sortByCPU
            ? "\(Int(rest.reduce(0) { $0 + $1.cpuPercent }))%"
            : Format.gigabytes(rest.reduce(0) { $0 + $1.memBytes })
        return Button { showAll = true } label: {
            HStack {
                Text(rest.map(\.name).joined(separator: ", ")).lineLimit(1)
                Spacer()
                Text(total).monospacedDigit()
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}

struct HeroCard: View {
    @EnvironmentObject private var appState: AppState
    let report: VitalsReport
    let open: (Screen) -> Void

    var body: some View {
        let summary = appState.summary ?? HealthSummary.from(report: report, cpuSaturated: false)
        let tint = appState.measuring ? Color.secondary : Theme.color(for: summary.tone)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon(summary))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(tint, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.measuring ? "Measuring…" : summary.title)
                        .font(.system(size: 17, weight: .semibold))
                    Text(appState.measuring ? "Waiting for the next reading from macOS." : summary.detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if summary.tone != .calm, !appState.measuring {
                actions(summary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .animation(.easeOut(duration: 0.4), value: summary)
    }

    private func icon(_ summary: HealthSummary) -> String {
        if appState.measuring { return "clock" }
        return summary.tone == .calm ? "checkmark" : "exclamationmark"
    }

    @ViewBuilder
    private func actions(_ summary: HealthSummary) -> some View {
        HStack(spacing: 8) {
            if summary.focus == .memory, report.idleBytes > 0 {
                let label = "Free \(Format.gigabytes(report.idleBytes))\(summary.tone == .critical ? " now" : "")"
                PrimaryButton(title: label, busy: appState.busy.contains("relief")) { appState.freeAllIdle() }
            } else if summary.focus == .cpu, let runaway = report.quickWinList.first(where: { $0.id == "quit_runaway" }) {
                PrimaryButton(title: runaway.title, tint: .red) { appState.request(.quickWin(runaway)) }
            }
            SecondaryButton(title: "Why?") { open(.history(summary.focus == .cpu ? .cpu : .memory)) }
        }
    }
}

struct MetricTile: View {
    @EnvironmentObject private var appState: AppState
    let metric: Metric
    let report: VitalsReport
    let action: () -> Void

    var body: some View {
        let values = metric.values(appState.history)
        let current = values.last.flatMap { $0 }
        let formatted = metric.format(current)
        let tint = metric.tint(report: report, summary: appState.summary, diskBusy: appState.diskBusy())
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Label(metric.label, systemImage: metric.symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(formatted.number).font(.system(size: 15, weight: .semibold))
                    Text(formatted.unit).font(.system(size: 11, weight: .medium))
                }
                .monospacedDigit()
                .foregroundStyle(tint ?? .primary)
                MiniSparkline(values: values.map { $0 ?? 0 }, color: tint ?? .secondary)
                    .padding(.top, 2)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(metric.label): show history")
    }
}

struct QuickWinRow: View {
    @EnvironmentObject private var appState: AppState
    let win: QuickWin

    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: Theme.symbol(forWin: win.id))
            VStack(alignment: .leading, spacing: 1) {
                Text(win.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(win.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if win.reclaimableBytes > 0 {
                Text(Format.gigabytes(win.reclaimableBytes))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.reclaim)
                    .monospacedDigit()
            }
            RowButton(title: win.label, busy: appState.busy.contains("win:\(win.id)") || appState.busy.contains("relief")) {
                appState.request(.quickWin(win))
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(minHeight: Theme.rowHeight)
    }
}

struct ConsumerRow: View {
    let group: ConsumerGroup
    let sortByCPU: Bool
    let maxValue: Double
    let action: () -> Void

    var body: some View {
        let value = sortByCPU ? group.cpuPercent : Double(group.memBytes)
        Button(action: action) {
            HStack(spacing: 8) {
                IconTile(symbol: Theme.symbol(forGroup: group.id))
                Text(group.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if group.idleBytes > 0 {
                    Text("\(Format.gigabytes(group.idleBytes)) idle")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.reclaim).lineLimit(1)
                }
                Spacer(minLength: 4)
                Capsule().fill(Theme.fill)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule().fill(Color.primary.opacity(0.35))
                                .frame(width: max(proxy.size.width * value / max(maxValue, 1), 2))
                        }
                    }
                    .frame(width: 40, height: 4)
                Text(sortByCPU ? "\(Int(group.cpuPercent))%" : Format.gigabytes(group.memBytes))
                    .font(.system(size: 13)).monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(group.name): show details")
    }
}
