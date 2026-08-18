import SwiftUI

/// The tinted capsule used for both the header's traffic-light summary
/// and per-finding severity — previously two near-identical
/// implementations with different padding (8/3 vs 6/2) and background
/// opacity (0.15 vs 0.2), so the two pills read as subtly different
/// sizes next to each other. One definition means they can't drift again.
struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
