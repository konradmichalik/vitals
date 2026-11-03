import SwiftUI

struct SeverityBadge: View {
    let severity: Severity

    var body: some View {
        StatusPill(text: severity.rawValue, color: color)
    }

    private var color: Color {
        switch severity {
        case .info: return .blue
        // Plain yellow fails text contrast in light mode, the same reason TrafficLight uses orange.
        case .warn: return .orange
        case .critical: return .red
        }
    }
}
