import SwiftUI

/// The Vitals pulse mark (`vitals.svg` at the repo root), transcribed as a
/// SwiftUI `Shape` so the menu bar icon has real brand identity instead of
/// being a bare colored dot. Coordinates are copied verbatim from the
/// SVG's 0–100 viewBox and scaled to whatever rect is given. Uses the
/// SVG's even-odd fill rule (`FillStyle(eoFill: true)`) — the two inner
/// arrow shapes are cut out of the outer ring, not stacked on top of it.
struct VitalsMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 100
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }

        var path = Path()

        path.move(to: point(50, 5))
        path.addCurve(to: point(5, 50), control1: point(25.188, 5), control2: point(5, 25.188))
        path.addCurve(to: point(50, 95), control1: point(5, 74.812), control2: point(25.188, 95))
        path.addCurve(to: point(95, 50), control1: point(74.812, 95), control2: point(95, 74.812))
        path.addCurve(to: point(50, 5), control1: point(95, 25.188), control2: point(74.812, 5))
        path.closeSubpath()

        path.move(to: point(50, 13))
        path.addCurve(to: point(86.781, 46), control1: point(69.051, 13), control2: point(84.777, 27.473))
        path.addLine(to: point(67, 46))
        path.addCurve(to: point(63.301, 48.477), control1: point(65.379, 46), control2: point(63.918, 46.977))
        path.addLine(to: point(59.07, 58.75))
        path.addLine(to: point(39.265, 30.695))
        path.addCurve(to: point(35.832, 29.003), control1: point(38.484, 29.585), control2: point(37.203, 28.949))
        path.addCurve(to: point(32.551, 30.972), control1: point(34.476, 29.058), control2: point(33.238, 29.8))
        path.addLine(to: point(23.711, 45.999))
        path.addLine(to: point(13.219, 45.999))
        path.addCurve(to: point(50, 12.999), control1: point(15.223, 27.472), control2: point(30.949, 12.999))
        path.addLine(to: point(50, 13))
        path.closeSubpath()

        path.move(to: point(50, 87))
        path.addCurve(to: point(13.219, 54), control1: point(30.949, 87), control2: point(15.223, 72.527))
        path.addLine(to: point(26, 54))
        path.addCurve(to: point(29.449, 52.027), control1: point(27.418, 54), control2: point(28.73, 53.25))
        path.addLine(to: point(36.309, 40.367))
        path.addLine(to: point(56.735, 69.305))
        path.addCurve(to: point(60, 71.001), control1: point(57.489, 70.376), control2: point(58.711, 71.001))
        path.addCurve(to: point(60.449, 70.977), control1: point(60.149, 71.001), control2: point(60.297, 70.993))
        path.addCurve(to: point(63.699, 68.524), control1: point(61.899, 70.813), control2: point(63.145, 69.876))
        path.addLine(to: point(69.68, 54.001))
        path.addLine(to: point(86.782, 54.001))
        path.addCurve(to: point(50.001, 87.001), control1: point(84.782, 72.528), control2: point(69.052, 87.001))
        path.addLine(to: point(50, 87))
        path.closeSubpath()

        return path
    }
}
