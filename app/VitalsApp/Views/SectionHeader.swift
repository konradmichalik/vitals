import SwiftUI

/// The icon+title pairing every section in the dropdown starts with
/// ("Load average", "CPU & Memory", "Docker & DDEV", ...) — previously
/// duplicated verbatim in each section file, so a styling tweak (font,
/// spacing, icon color) had to be repeated by hand everywhere and could
/// silently drift. Deliberately excludes trailing content (a Spacer +
/// Menu button, a status label): callers that need one wrap this in
/// their own HStack, same as before.
struct SectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
    }
}
