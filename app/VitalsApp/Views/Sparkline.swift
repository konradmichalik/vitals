import Charts
import SwiftUI

/// Compact, axis-less recent-trend line — a glance-only companion to the
/// numeric value next to it, not a standalone chart with its own labels.
/// Hovering reveals what a point actually means via `tooltip`, rather
/// than ambient per-point markers: a marker on every sample that's
/// currently in a sustained state (the common case) reads as visual
/// noise indistinguishable from an isolated spike, and nothing explains
/// what it means without already knowing the convention.
///
/// The hover indicator is drawn as a plain overlay positioned via
/// `proxy.position(forX:forY:)`, never as extra marks inside `Chart`
/// itself — conditionally adding marks there made `.chartYScale`
/// recompute the plot's domain between hovered/not-hovered, which
/// visibly shifted the whole line on every hover start/end.
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
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            SparklineHoverOverlay(proxy: proxy, sampleCount: values.count, hoveredIndex: $hoveredIndex) { index in
                guard let y = proxy.position(forY: values[index]) else { return nil }
                return SparklineIndicator(points: [IndicatorPoint(y: y, color: color)], tooltip: tooltip(index))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 24)
    }
}

/// Two related percentage series sharing one axis (CPU and memory both
/// being 0–100 already makes a shared scale meaningful, unlike load —
/// see `Sparkline`), so they fit in the vertical space one chart needs
/// instead of two.
///
/// Uses the categorical `foregroundStyle(by:)` + `chartForegroundStyleScale`
/// pattern over one unified `Chart(data:)` data source, rather than two
/// separate `ForEach` blocks each with their own manual `.foregroundStyle`
/// — the manual version produced visible rendering artifacts (a spurious
/// extra line, colors not applying) despite giving each series its own
/// unique mark identities. This categorical form is Charts' own supported
/// way to draw multiple distinctly colored lines and doesn't have that
/// problem.
struct DualSparkline: View {
    let primaryValues: [Double]
    let primaryColor: Color
    let secondaryValues: [Double]
    let secondaryColor: Color
    let tooltip: (Int) -> String

    @State private var hoveredIndex: Int?

    private static let primarySeries = "primary"
    private static let secondarySeries = "secondary"

    private var points: [SeriesPoint] {
        let primary = primaryValues.enumerated().map {
            SeriesPoint(id: "p-\($0.offset)", index: $0.offset, value: $0.element, series: Self.primarySeries)
        }
        let secondary = secondaryValues.enumerated().map {
            SeriesPoint(id: "s-\($0.offset)", index: $0.offset, value: $0.element, series: Self.secondarySeries)
        }
        return primary + secondary
    }

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Sample", point.index), y: .value("Value", point.value))
                .foregroundStyle(by: .value("Series", point.series))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .chartForegroundStyleScale([Self.primarySeries: primaryColor, Self.secondarySeries: secondaryColor])
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            SparklineHoverOverlay(proxy: proxy, sampleCount: secondaryValues.count, hoveredIndex: $hoveredIndex) { index in
                guard let secondaryY = proxy.position(forY: secondaryValues[index]) else { return nil }
                var indicatorPoints = [IndicatorPoint(y: secondaryY, color: secondaryColor)]
                if let primaryY = proxy.position(forY: primaryValues[index]) {
                    indicatorPoints.append(IndicatorPoint(y: primaryY, color: primaryColor))
                }
                return SparklineIndicator(points: indicatorPoints, tooltip: tooltip(index))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
    }
}

private struct SeriesPoint: Identifiable {
    let id: String
    let index: Int
    let value: Double
    let series: String
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

                if let hoveredIndex, let plotFrame,
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
