import Charts
import SwiftUI

private let sparklineLineStyle = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)

private extension View {
    /// A domain that does not force 0 as the floor keeps small fluctuations
    /// in a narrow band (RAM hovering around 80%) visible as a trend.
    func sparklineChartStyle() -> some View {
        chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartLegend(.hidden)
    }
}

/// Compact, axis-less trend line next to a numeric value; hovering explains a point through `tooltip`.
/// The hover indicator is an overlay placed with `proxy.position(forX:forY:)`, not a mark inside `Chart`:
/// conditional marks made `.chartYScale` recompute its domain and shifted the whole line on every hover.
struct Sparkline: View {
    let values: [Double]
    let color: Color
    let tooltip: (Int) -> String

    @State private var hoveredIndex: Int?

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                LineMark(x: .value("Sample", index), y: .value("Value", value))
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(sparklineLineStyle)
            }
        }
        .sparklineChartStyle()
        .chartOverlay { proxy in
            SparklineHoverOverlay(proxy: proxy, sampleCount: values.count, hoveredIndex: $hoveredIndex) { index in
                guard values.indices.contains(index), let y = proxy.position(forY: values[index]) else { return nil }
                return SparklineIndicator(points: [IndicatorPoint(y: y, color: color)], tooltip: tooltip(index))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        // The window shrinks as samples age out, and the pointer may rest without moving.
        .onChange(of: values.count) { hoveredIndex = nil }
    }
}

enum SparklineHover {
    /// A stored hover index survives re-renders, so it is only usable while it still points into the current values.
    static func validIndex(_ index: Int?, count: Int) -> Int? {
        guard let index, (0..<count).contains(index) else { return nil }
        return index
    }
}

private struct IndicatorPoint {
    let y: CGFloat
    let color: Color
}

private struct SparklineIndicator {
    let points: [IndicatorPoint]
    let tooltip: String
}

private struct SparklineTooltip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
            .fixedSize()
    }
}

/// Hover-to-index mapping plus the actual indicator drawing (vertical
/// rule, dot(s), tooltip), all positioned in plain view coordinates
/// derived from the chart's own coordinate space — never as `Chart`
/// marks, so hovering can never change what the chart itself computes
/// to render.
private struct SparklineHoverOverlay: View {
    let proxy: ChartProxy
    let sampleCount: Int
    @Binding var hoveredIndex: Int?
    let indicator: (Int) -> SparklineIndicator?

    var body: some View {
        GeometryReader { geometry in
            let plotFrame = proxy.plotFrame.map { geometry[$0] }

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard sampleCount > 0, let plotFrame else { return }
                            let x = location.x - plotFrame.origin.x
                            guard let rawIndex: Int = proxy.value(atX: x) else { return }
                            hoveredIndex = min(max(0, rawIndex), sampleCount - 1)
                        case .ended:
                            hoveredIndex = nil
                        }
                    }

                if let hoveredIndex = SparklineHover.validIndex(hoveredIndex, count: sampleCount), let plotFrame,
                   let x = proxy.position(forX: hoveredIndex),
                   let result = indicator(hoveredIndex) {
                    let originX = plotFrame.origin.x + x

                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 1, height: plotFrame.height)
                        .position(x: originX, y: plotFrame.origin.y + plotFrame.height / 2)

                    ForEach(Array(result.points.enumerated()), id: \.offset) { _, point in
                        Circle()
                            .fill(point.color)
                            .frame(width: 5, height: 5)
                            .position(x: originX, y: plotFrame.origin.y + point.y)
                    }

                    let topY = plotFrame.origin.y + (result.points.map(\.y).min() ?? 0)
                    SparklineTooltip(text: result.tooltip)
                        .position(x: originX, y: max(10, topY - 14))
                }
            }
        }
    }
}
