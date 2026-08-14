import AppKit
import Combine
import SwiftUI
import UserNotifications

/// Owns the `NSStatusItem` directly via AppKit rather than SwiftUI's
/// `MenuBarExtra`, because `MenuBarExtra`'s `label:` closure gets
/// composited into a single `NSImage` for the real status item, and a
/// template image is a pure alpha mask painted in one uniform color — it
/// cannot show a neutral, OS-adaptive base icon next to a distinctly
/// colored badge in the same image. Every attempt to fake that by
/// disabling `isTemplate` and guessing the "right" neutral color
/// ourselves (`NSApp.effectiveAppearance`, the raw `AppleInterfaceStyle`
/// preference) rendered wrong against the real menu bar. Managing the
/// status item ourselves lets the base icon stay a genuine template
/// image (colored correctly by the OS, like every other menu bar icon)
/// while the badge is a real, separate `NSView` layered on top — never
/// part of the same image, so it's never subject to template masking.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    @AppStorage(AppNotifier.alertStorageKey) private var notifyOnAlerts = true

    let appState = AppState()

    private var statusItem: NSStatusItem?
    private var badgeView: NSView?
    private var popover: NSPopover?
    private var cancellable: AnyCancellable?

    /// `xcodebuild test` hosts the app in a process that UNUserNotificationCenter
    /// can't resolve a bundle identity for (it crashes with "could not
    /// determine bundleIdentifier") — confirmed real, `open`-launched
    /// Debug and Release builds both work fine, so this is a test-runner
    /// artifact, not a product bug. Skipping notification setup under
    /// test avoids the crash without touching real launch behavior.
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Foundation.Notification) {
        guard !isRunningTests else { return }
        UNUserNotificationCenter.current().delegate = self
        if notifyOnAlerts {
            AppNotifier.requestPermission()
        }
        setupStatusItem()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let icon = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Vitals")
            icon?.isTemplate = true
            button.image = icon
            button.action = #selector(toggleDropdown)
            button.target = self

            // A manual frame here read `button.bounds` before the button
            // had actually laid out to fit the new image, so the badge
            // landed wherever that premature (near-zero) size implied —
            // constraints resolve correctly regardless of when AppKit
            // finishes that layout pass.
            let diameter: CGFloat = 6
            let badge = NSView()
            badge.translatesAutoresizingMaskIntoConstraints = false
            badge.wantsLayer = true
            badge.layer?.cornerRadius = diameter / 2
            button.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.widthAnchor.constraint(equalToConstant: diameter),
                badge.heightAnchor.constraint(equalToConstant: diameter),
                badge.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -1),
                badge.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -1),
            ])
            badgeView = badge
        }
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenubarView().environmentObject(appState))
        self.popover = popover

        cancellable = appState.$report.sink { [weak self] report in
            self?.updateBadge(for: report?.findings ?? [])
        }
    }

    private func updateBadge(for findings: [Finding]) {
        badgeView?.layer?.backgroundColor = NSColor(TrafficLight.from(findings: findings).color).cgColor
        statusItem?.button?.toolTip = TrafficLight.tooltip(for: findings)
    }

    @objc private func toggleDropdown() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // `.transient` dismisses on an outside click via NSPopover's
            // own event monitor, set up as part of showing the popover
            // and taking key window status — manually forcing
            // `.becomeKey()` on its window right after `.show()` (the
            // previous code here) stepped on that internal setup, so
            // outside clicks never dismissed it. Activating the app
            // first is the standard way an accessory app's popover gets
            // real focus without needing to manage window key status by
            // hand.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
