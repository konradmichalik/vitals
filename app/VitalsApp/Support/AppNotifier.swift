import AppKit
import UserNotifications

/// Posts a system notification — used both for a finding newly entering
/// critical severity, and for the result of a "Run"/"Stop" action
/// (§9: the app's own confirmation already gates the run; the
/// notification is just reliable feedback once it's done, since the
/// dropdown may well be closed by then). Not unit tested: it's a thin
/// pass-through to `UNUserNotificationCenter` with real side effects
/// (actual banners, actual permission prompts), matching
/// `LaunchAtLogin`'s rationale.
enum AppNotifier {
    /// Single source of truth for the `@AppStorage` key shared by
    /// `AppDelegate`, `AppState`, and `SettingsView` — declaring it three
    /// times independently would let a typo in one silently desync it
    /// from the others. Only gates warn/critical finding notifications; a
    /// user-triggered action's own result always notifies regardless,
    /// since they explicitly asked for that action to run.
    static let alertStorageKey = "notifyOnAlerts"

    /// Drives the notification's large attachment image — the small
    /// corner badge already shows the app's own icon (via bundle
    /// identity), so this is the one visual that can actually tell a
    /// critical finding apart from a routine "action succeeded" banner
    /// at a glance, without opening the dropdown.
    enum Kind {
        case critical
        case warning
        case success
        case failure

        var symbolName: String {
            switch self {
            case .critical: return "exclamationmark.triangle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .success: return "checkmark.circle.fill"
            case .failure: return "xmark.circle.fill"
            }
        }

        var tint: NSColor {
            switch self {
            case .critical: return .systemRed
            case .warning: return .systemOrange
            case .success: return .systemGreen
            case .failure: return .systemRed
            }
        }
    }

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    @MainActor
    static func notify(id: String, title: String, body: String, kind: Kind) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let attachment = iconAttachment(kind: kind) {
            content.attachments = [attachment]
        }

        // Reusing a stable identifier means a second notification for
        // the same id (e.g. the same still-critical rule) replaces the
        // first instead of piling up.
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// `LSUIElement` (agent) apps like this one have no Dock presence,
    /// and Notification Center's implicit bundle-icon lookup for that
    /// app class is unreliable — banners render with a blank image even
    /// though `CFBundleIconName` resolves fine everywhere else. Attaching
    /// an image explicitly sidesteps that lookup entirely, and drawing a
    /// tinted glyph rather than reusing the static app icon lets this
    /// image actually communicate what kind of notification it is.
    @MainActor
    private static func iconAttachment(kind: Kind) -> UNNotificationAttachment? {
        guard let png = badgeImage(kind: kind).pngData() else { return nil }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        do {
            try png.write(to: url)
            return try UNNotificationAttachment(identifier: "badge-\(kind)", url: url, options: nil)
        } catch {
            return nil
        }
    }

    private static func badgeImage(kind: Kind) -> NSImage {
        let size = CGSize(width: 256, height: 256)
        let image = NSImage(size: size)
        image.lockFocus()

        kind.tint.setFill()
        NSBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()

        if let symbol = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 120, weight: .bold)
                .applying(.init(paletteColors: [.white]))
            let glyph = symbol.withSymbolConfiguration(config) ?? symbol
            let origin = CGPoint(x: (size.width - glyph.size.width) / 2, y: (size.height - glyph.size.height) / 2)
            glyph.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        }

        image.unlockFocus()
        return image
    }
}

extension AppNotifier.Kind: CustomStringConvertible {
    var description: String {
        switch self {
        case .critical: return "critical"
        case .warning: return "warning"
        case .success: return "success"
        case .failure: return "failure"
        }
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
