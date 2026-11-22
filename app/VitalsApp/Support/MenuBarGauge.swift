import AppKit

/// Draws the memory gauge (and the value next to it) for the status item
/// title. The gauge image uses a drawing handler, so `labelColor` is
/// resolved each time it is drawn and follows the menu bar's light or
/// dark appearance instead of a color guessed once at creation.
enum MenuBarGauge {
    static let size = NSSize(width: 24, height: 11)

    static func color(for tone: MenuBarState.Tone) -> NSColor {
        switch tone {
        case .normal: return .labelColor
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    static func image(fill: Double, tone: MenuBarState.Tone) -> NSImage {
        let clamped = min(max(fill, 0), 1)
        return NSImage(size: size, flipped: false) { rect in
            let color = color(for: tone)
            let frame = rect.insetBy(dx: 0.75, dy: 0.75)
            let outline = NSBezierPath(roundedRect: frame, xRadius: 3, yRadius: 3)
            outline.lineWidth = 1.3
            color.setStroke()
            outline.stroke()
            let inner = frame.insetBy(dx: 1.75, dy: 1.75)
            let bar = NSRect(x: inner.minX, y: inner.minY, width: inner.width * clamped, height: inner.height)
            color.setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
            return true
        }
    }

    static func title(for state: MenuBarState, mode: MenuBarMode) -> NSAttributedString {
        guard mode != .icon else { return NSAttributedString(string: "") }
        let result = NSMutableAttributedString(string: " ")
        let attachment = NSTextAttachment()
        attachment.image = image(fill: state.fill, tone: state.tone)
        attachment.bounds = NSRect(x: 0, y: -1, width: size.width, height: size.height)
        result.append(NSAttributedString(attachment: attachment))
        if mode == .gaugeAndValue, let label = state.label {
            result.append(NSAttributedString(
                string: " \(label)",
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: color(for: state.tone),
                ]
            ))
        }
        return result
    }
}
