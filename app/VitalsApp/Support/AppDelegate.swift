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
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate {
    @AppStorage(AppNotifier.alertStorageKey) private var notifyOnAlerts = true

    let appState = AppState()

    private var statusItem: NSStatusItem?
    private var badgeView: NSView?
    private var popover: NSPopover?
    private var cancellable: AnyCancellable?
    private var defaultsObserver: NSObjectProtocol?
    private var latestReport: VitalsReport?
    private var badgeLeading: NSLayoutConstraint?
    // Double optional: the outer nil means "never applied yet".
    private var shownLabel: String??

    private static let fallbackImageInset: CGFloat = 4
    private static let badgeDiameter: CGFloat = 6

    /// `xcodebuild test` hosts the app in a process that UNUserNotificationCenter
    /// can't resolve a bundle identity for (it crashes with "could not
    /// determine bundleIdentifier") — confirmed real, `open`-launched
    /// Debug and Release builds both work fine, so this is a test-runner
    /// artifact, not a product bug. Skipping notification setup under
    /// test avoids the crash without touching real launch behavior.
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// `LSUIElement` in Info.plist would keep the app out of the Dock
    /// from the very first instant, but Notification Center's icon
    /// lookup for a sender never resolves for apps that never once
    /// registered as Dock-eligible — banners rendered a blank placeholder
    /// where the app icon belongs, even though the icon itself is set up
    /// correctly (Finder, Launch Services, `CFBundleIconName` all resolve
    /// it fine). Switching the activation policy here instead, as early
    /// as possible, gives Launch Services that one legitimate pass while
    /// still hiding the Dock icon before the app is visibly usable.
    func applicationWillFinishLaunching(_ notification: Foundation.Notification) {
        guard !isRunningTests else { return }
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidFinishLaunching(_ notification: Foundation.Notification) {
        guard !isRunningTests else { return }
        if notifyOnAlerts {
            AppNotifier.requestPermission()
        }
        setupStatusItem()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let icon = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Vitals")
            icon?.isTemplate = true
            button.image = icon
            button.imagePosition = .imageLeading
            button.setAccessibilityLabel("Vitals")
            button.action = #selector(toggleDropdown)
            button.target = self
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            installBadge(on: button)
        }
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverShell().environmentObject(appState))
        self.popover = popover

        cancellable = appState.$report.sink { [weak self] report in
            self?.latestReport = report
            self?.updateBadge(for: report?.findings ?? [])
            self?.updateLabel()
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLabel() }
        }
    }

    private func installBadge(on button: NSStatusBarButton) {
        // A manual frame here read `button.bounds` before the button
        // had actually laid out to fit the new image, so the badge
        // landed wherever that premature (near-zero) size implied —
        // constraints resolve correctly regardless of when AppKit
        // finishes that layout pass.
        let badge = NSView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.wantsLayer = true
        button.addSubview(badge)
        // Leading, not trailing: the value label widens the button
        // on the right, the badge has to stay on the icon.
        let leading = badge.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 0)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: Self.badgeDiameter),
            badge.heightAnchor.constraint(equalToConstant: Self.badgeDiameter),
            leading,
            badge.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -1),
        ])
        badgeView = badge
        badgeLeading = leading
    }

    /// Re-derives the badge offset from the icon's real position, because
    /// the title changes the button width and the icon's inset with it.
    private func anchorBadgeToImage(_ button: NSStatusBarButton) {
        button.layoutSubtreeIfNeeded()
        let imageMaxX = button.cell?.imageRect(forBounds: button.bounds).maxX ?? 0
        let fallback = (button.image?.size.width ?? 0) + Self.fallbackImageInset
        badgeLeading?.constant = (imageMaxX > 0 ? imageMaxX : fallback) - Self.badgeDiameter + 1
    }

    private func updateLabel() {
        guard let button = statusItem?.button else { return }
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: QuietHours.menubarValueKey) == nil
            || defaults.bool(forKey: QuietHours.menubarValueKey)
        let text = latestReport.flatMap { MenubarLabel.text(for: $0, enabled: enabled) }
        // Defaults change on every history or snooze write, not only for this key.
        guard text != shownLabel else { return }
        shownLabel = text
        button.title = text ?? ""
        anchorBadgeToImage(button)
        button.setAccessibilityLabel(text.map { "Vitals, \($0)" } ?? "Vitals")
    }

    /// The dot only earns its keep as an interrupt for something worth
    /// noticing — showing it green for the common "all clear" case just
    /// added a permanent fixture next to the icon with nothing to say.
    private func updateBadge(for findings: [Finding]) {
        let light = TrafficLight.from(findings: findings)
        badgeView?.isHidden = light == .green
        badgeView?.layer?.cornerRadius = TrafficLight.badgeCornerRadius(for: light, diameter: Self.badgeDiameter)
        badgeView?.layer?.backgroundColor = NSColor(light.color).cgColor
        statusItem?.button?.toolTip = TrafficLight.tooltip(for: findings)
    }

    func popoverDidClose(_ notification: Notification) {
        NotificationCenter.default.post(name: .popoverDidClose, object: nil)
    }

    @objc private func toggleDropdown() {
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let popover, let button = statusItem?.button else { return }
        // `.transient` dismisses on an outside click via NSPopover's
        // own event monitor, set up as part of showing the popover
        // and taking key window status. Manually forcing
        // `.becomeKey()` on its window right after `.show()` stepped
        // on that internal setup, so outside clicks never dismissed
        // it. Activating the app
        // first is the standard way an accessory app's popover gets
        // real focus without needing to manage window key status by
        // hand.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func showOverview() {
        if popover?.isShown == true {
            NotificationCenter.default.post(name: .popoverShowOverview, object: nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            showPopover()
        }
    }

    private func handle(_ response: NotificationResponse) {
        switch response {
        case .show: showOverview()
        case .snooze(let rule): appState.snooze(rule: rule, for: .oneHour)
        case .ignore: break
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let parsed = NotificationResponse.parse(
            actionIdentifier: response.actionIdentifier,
            userInfo: response.notification.request.content.userInfo
        )
        await MainActor.run { handle(parsed) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
