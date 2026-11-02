import SwiftUI

extension Notification.Name {
    static let popoverDidClose = Notification.Name("VitalsPopoverDidClose")
}

/// Hosts every popover screen and owns the shared header and footer chrome.
struct PopoverShell: View {
    @EnvironmentObject private var appState: AppState
    @State private var screen: PopoverScreen = .overview
    @State private var contentHeight: CGFloat = 0

    /// Keeps the header and footer (Refresh, Quit) on screen when a busy overview grows tall.
    private static let maxContentHeight: CGFloat = 560

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            scrollingContent
            Divider()
            footer
        }
        .frame(width: 380)
        // NSPopover has no opaque backing of its own: without this the
        // system's vibrancy blur shows the desktop through the card tints.
        .background(Color(nsColor: .windowBackgroundColor))
        // The hosted view stays alive while the popover is closed, so onDisappear is not reliable here.
        .onReceive(NotificationCenter.default.publisher(for: .popoverDidClose)) { _ in
            screen = .overview
        }
    }

    /// A ScrollView has no ideal height inside an NSPopover, so it is sized to the measured content up to the cap.
    private var scrollingContent: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        // Before the first measurement a fixed 0 height would open the popover collapsed.
        .frame(height: contentHeight > 0 ? min(contentHeight, Self.maxContentHeight) : nil)
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .overview:
            MenubarView { screen = $0 }
        case .settings:
            PopoverSettingsView()
        case .detail, .toolchain, .activity:
            Text(screen.title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(24)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if screen == .overview {
                Image("VitalsIcon")
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
            } else {
                iconButton("chevron.left", label: "Back to overview") { screen = .overview }
            }
            Text(screen.title)
                .font(.headline)
            if screen == .overview, let report = appState.report {
                StatusPill(
                    text: TrafficLight.statusLabel(for: report.findings),
                    color: TrafficLight.from(findings: report.findings).color
                )
            }
            Spacer()
            iconButton("clock", label: "Activity") { screen = screen.toggled(.activity) }
            iconButton("gearshape", label: "Settings") { screen = screen.toggled(.settings) }
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            if let lastUpdated = appState.lastUpdated {
                Text("Updated ").font(.caption) + Text(lastUpdated, style: .relative).font(.caption)
            } else {
                Text("Updating…").font(.caption)
            }
            Spacer()
            iconButton("arrow.clockwise", label: "Refresh") { Task { await appState.refresh() } }
            iconButton("power", label: "Quit Vitals") { NSApplication.shared.terminate(nil) }
        }
        .foregroundStyle(.secondary)
        .padding(12)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(label)
        .help(label)
    }
}
