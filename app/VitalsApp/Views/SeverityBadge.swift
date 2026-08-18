import SwiftUI

struct SeverityBadge: View {
    let severity: Severity

    var body: some View {
        StatusPill(text: severity.rawValue, color: color)
    }

    private var color: Color {
        switch severity {
        case .info: return .blue
        case .warn: return .yellow
        case .critical: return .red
        }
    }
}
