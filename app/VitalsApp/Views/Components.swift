import Charts
import SwiftUI

/// Shared building blocks so every screen uses the same row, the same two
/// button heights and the same two corner radii (12 for cards, 8 for
/// controls). Color carries meaning only: blue is "can be freed", orange
/// and red mark the bottleneck, everything else stays neutral.
enum Theme {
    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 8
    static let rowHeight: CGFloat = 42
    static let rowButtonHeight: CGFloat = 28
    static let primaryButtonHeight: CGFloat = 32
    static let card = Color.primary.opacity(0.05)
    static let fill = Color.primary.opacity(0.10)
    static let reclaim = Color.blue

    static func color(for tone: HealthSummary.Tone) -> Color {
        switch tone {
        case .calm: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    static func color(for pressure: PressureLevel) -> Color {
        switch pressure {
        case .normal: return .primary
        case .warn: return .orange
        case .critical: return .red
        }
    }

    static func symbol(forGroup id: String) -> String {
        switch id {
        case "ddev": return "shippingbox"
        case "agents": return "sparkles"
        case "phpstorm": return "chevron.left.forwardslash.chevron.right"
        case "browser": return "globe"
        case "containers": return "square.stack.3d.up"
        case "system": return "cpu"
        default: return "square.grid.2x2"
        }
    }

    static func symbol(forWin id: String) -> String {
        switch id {
        case "stop_idle_ddev": return "shippingbox"
        case "end_idle_sessions": return "sparkles"
        case "quit_orphaned_agents": return "chevron.left.forwardslash.chevron.right"
        case "quit_runaway": return "flame"
        default: return "clock.arrow.circlepath"
        }
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
    }
}

struct IconTile: View {
    let symbol: String
    var tint: Color = .secondary

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 22, height: 22)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// A rounded card holding rows with hairlines between them.
struct CardList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider().padding(.leading, 12)
                }
                row(item)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

struct RowButton: View {
    let title: String
    var busy = false
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Text(title)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .frame(minWidth: 40)
            .padding(.horizontal, 10)
            .frame(height: Theme.rowButtonHeight)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }
}

struct PrimaryButton: View {
    let title: String
    var busy = false
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.small).tint(.white)
                }
                Text(title)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.primaryButtonHeight)
            .background(tint, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: Theme.primaryButtonHeight)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        }
        .buttonStyle(.plain)
    }
}

/// Tiny trend line for the vital-sign tiles: no axes, no hover.
struct MiniSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                AreaMark(x: .value("t", index), y: .value("v", value))
                    .foregroundStyle(color.opacity(0.15))
                LineMark(x: .value("t", index), y: .value("v", value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 18)
    }
}

/// How much of the total a group holds, with its idle part in blue.
struct ShareBar: View {
    let used: UInt64
    let idle: UInt64
    let total: UInt64

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let scale = total > 0 ? width / CGFloat(total) : 0
            HStack(spacing: 2) {
                Rectangle().fill(Color.primary.opacity(0.35)).frame(width: CGFloat(used) * scale)
                Rectangle().fill(Theme.reclaim).frame(width: CGFloat(idle) * scale)
                Spacer(minLength: 0)
            }
            .background(Theme.fill)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.5), value: used)
    }
}
