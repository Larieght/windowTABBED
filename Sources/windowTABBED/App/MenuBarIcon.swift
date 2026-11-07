import AppKit

/// The menu bar glyph: the app icon (design 08g) as a one-color line drawing. The back window has
/// its tabs on top, the front window has them underneath, and the active tab of each is filled.
/// A template image, so macOS tints it for light and dark menu bars.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            draw()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "windowTABBED"
        return image
    }()

    private static let line: CGFloat = 1.1

    private static func draw() {
        // Back window, upper right, tabs on top: active left.
        window(CGRect(x: 6, y: 4.8, width: 11.5, height: 7.2))
        tab(CGRect(x: 7.2, y: 1.2, width: 4.6, height: 3.6), filled: true, openAt: .maxYEdge)
        tab(CGRect(x: 12.4, y: 1.2, width: 4.6, height: 3.6), filled: false, openAt: .maxYEdge)
        // Front window, lower left, tabs underneath: active right.
        let front = CGRect(x: 0.5, y: 7.8, width: 11.5, height: 6.8)
        clear(front.insetBy(dx: -line, dy: -line))
        window(front)
        tab(CGRect(x: 1.7, y: 14.6, width: 4.6, height: 3.2), filled: false, openAt: .minYEdge)
        tab(CGRect(x: 6.9, y: 14.6, width: 4.6, height: 3.2), filled: true, openAt: .minYEdge)
    }

    private static func window(_ rect: CGRect) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: line / 2, dy: line / 2), xRadius: 2, yRadius: 2)
        path.lineWidth = line
        NSColor.black.setStroke()
        path.stroke()
    }

    /// A tab sticking out of a window edge: rounded on the far side, open where it meets the window.
    private static func tab(_ rect: CGRect, filled: Bool, openAt edge: CGRectEdge) {
        let r = rect.insetBy(dx: line / 2, dy: 0)
        let radius: CGFloat = 0.9
        let path = NSBezierPath()
        if edge == .maxYEdge {
            path.move(to: CGPoint(x: r.minX, y: r.maxY))
            path.line(to: CGPoint(x: r.minX, y: r.minY + line / 2 + radius))
            path.appendArc(from: CGPoint(x: r.minX, y: r.minY + line / 2), to: CGPoint(x: r.maxX, y: r.minY + line / 2), radius: radius)
            path.appendArc(from: CGPoint(x: r.maxX, y: r.minY + line / 2), to: CGPoint(x: r.maxX, y: r.maxY), radius: radius)
            path.line(to: CGPoint(x: r.maxX, y: r.maxY))
        } else {
            path.move(to: CGPoint(x: r.minX, y: r.minY))
            path.line(to: CGPoint(x: r.minX, y: r.maxY - line / 2 - radius))
            path.appendArc(from: CGPoint(x: r.minX, y: r.maxY - line / 2), to: CGPoint(x: r.maxX, y: r.maxY - line / 2), radius: radius)
            path.appendArc(from: CGPoint(x: r.maxX, y: r.maxY - line / 2), to: CGPoint(x: r.maxX, y: r.minY), radius: radius)
            path.line(to: CGPoint(x: r.maxX, y: r.minY))
        }
        NSColor.black.set()
        if filled {
            path.close()
            path.fill()
        }
        path.lineWidth = line
        path.stroke()
    }

    /// Erases what's behind the front window, so the back window's lines don't show through it.
    private static func clear(_ rect: CGRect) {
        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(roundedRect: rect, xRadius: 2.8, yRadius: 2.8).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }
}
