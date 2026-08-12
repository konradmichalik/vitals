import SwiftUI

struct SeverityBadge: View {
    let severity: Severity

    var body: some View {
        Text(severity.rawValue)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch severity {
        case .info: return .blue
        case .warn: return .yellow
        case .critical: return .red
        }
    }
}
