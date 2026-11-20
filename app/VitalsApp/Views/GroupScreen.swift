import SwiftUI

struct GroupScreen: View {
    @EnvironmentObject private var appState: AppState
    let group: ConsumerGroup
    let totalBytes: UInt64

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Label("\(group.name) · memory", systemImage: Theme.symbol(forGroup: group.id))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(Format.gigabytes(group.memBytes))
                        .font(.system(size: 28, weight: .bold))
                        .monospacedDigit()
                }
                Spacer()
                if group.idleBytes > 0 {
                    PrimaryButton(
                        title: "Free \(Format.gigabytes(group.idleBytes))",
                        busy: appState.busy.contains { $0.hasPrefix("group:\(group.id)") }
                    ) { appState.freeIdle(in: group) }
                    .frame(width: 130)
                }
            }
            ShareBar(used: group.memBytes - group.idleBytes, idle: group.idleBytes, total: max(totalBytes, group.memBytes))
            CardList(items: group.items) { item in
                ItemRow(item: item)
            }
            Text(note)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
    }

    private var note: String {
        let idle = "\(Format.duration(UInt64(appState.idleMinutes * 60))) without activity"
        switch group.id {
        case "ddev": return "A project counts as idle after \(idle). Stopping keeps its database and files."
        case "agents": return "A session counts as idle after \(idle) in its transcript. Resume with claude --continue."
        case "phpstorm": return "Agents whose IDE window is gone count as left behind. PhpStorm's own heap is set under Help, Change Memory Settings."
        case "browser": return "Whether tabs come back after quitting depends on the browser's startup setting."
        case "containers": return "The container VM gives memory back to macOS once containers stop using it."
        case "system": return "Not reclaimable while the Mac is running."
        default: return "Memory is the resident size of each app's processes."
        }
    }
}

struct ItemRow: View {
    @EnvironmentObject private var appState: AppState
    let item: ConsumerItem

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(item.idle ? Theme.reclaim : Color.secondary.opacity(item.protected ? 0.3 : 0.6))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(item.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if item.memBytes > 0 {
                Text(Format.gigabytes(item.memBytes))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let action = item.action, !item.protected {
                RowButton(
                    title: action.label,
                    busy: appState.busy.contains("item:\(item.id)"),
                    tint: action.confirm ? .red : .primary
                ) { appState.request(.item(item, action: action)) }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(minHeight: 44)
    }
}
