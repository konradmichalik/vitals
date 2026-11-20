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
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSPopoverDelegate {
    @AppStorage(AppNotifier.alertStorageKey) private var notifyOnAlerts = true

    let appState = AppState()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellable: AnyCancellable?
    private var defaultsObserver: NSObjectProtocol?
    private var lastShownState: MenuBarState?
    private var lastShownMode: MenuBarMode?
    private var lastToolTip: String?

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
    }

    func applicationDidFinishLaunching(_ notification: Foundation.Notification) {
        guard !isRunningTests else { return }
        UNUserNotificationCenter.current().delegate = self
        AppNotifier.registerCategories()
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
            button.action = #selector(toggleDropdown)
            button.target = self
        }
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        self.popover = popover

        cancellable = appState.$menuBar.combineLatest(appState.$report).sink { [weak self] state, report in
            self?.updateStatusItem(state, findings: report?.findings ?? [])
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.updateStatusItem(self.appState.menuBar, findings: self.appState.report?.findings ?? [])
            }
        }
    }

    /// The icon stays a template image so macOS colors it like every other
    /// menu bar icon. The gauge and value sit in the button's title as a
    /// separate attachment: a template image can only be one uniform
    /// color, so they could never share an image with the icon.
    private func updateStatusItem(_ state: MenuBarState, findings: [Finding]) {
        guard let button = statusItem?.button else { return }
        let mode = MenuBarMode(rawValue: UserDefaults.standard.string(forKey: AppSettings.Key.menuBarMode) ?? "") ?? .gaugeAndValue
        // Every `UserDefaults` write lands here too; only touch the
        // button when what it shows actually changed.
        if lastShownState != state || lastShownMode != mode {
            button.attributedTitle = MenuBarGauge.title(for: state, mode: mode)
            lastShownState = state
            lastShownMode = mode
        }
        let toolTip = TrafficLight.tooltip(for: findings)
        if lastToolTip != toolTip {
            button.toolTip = toolTip
            lastToolTip = toolTip
        }
    }

    /// The popover's view tree exists only while it is open. Kept alive,
    /// SwiftUI would re-evaluate every screen and redraw every chart on
    /// each poll with nobody looking.
    func popoverDidClose(_ notification: Foundation.Notification) {
        popover?.contentViewController = nil
    }

    func applicationWillTerminate(_ notification: Foundation.Notification) {
        appState.flushHistory()
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
            popover.contentViewController = NSHostingController(rootView: MenubarView().environmentObject(appState))
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    /// The button on the memory warning banner frees idle items directly.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isFreeIdle = response.actionIdentifier == AppNotifier.freeIdleAction
        completionHandler()
        guard isFreeIdle else { return }
        Task { @MainActor in
            self.appState.freeAllIdle()
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
