import AppKit

/// Converts between the two coordinate spaces macOS uses.
///
/// Accessibility and the window server use a top-left origin on the main display, y growing down.
/// AppKit (NSWindow, NSScreen) uses a bottom-left origin, y growing up. Both are in points.
enum ScreenGeometry {
    private static var mainHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func appKitRect(fromAX rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func axRect(fromAppKit rect: NSRect) -> CGRect {
        CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The mouse pointer, in AX coordinates.
    static var mouseLocation: CGPoint {
        let point = NSEvent.mouseLocation
        return CGPoint(x: point.x, y: mainHeight - point.y)
    }

    /// The usable area (without menu bar and Dock) of the display that holds most of `rect`, in AX coordinates.
    static func visibleFrame(containing rect: CGRect) -> CGRect {
        let appKit = appKitRect(fromAX: rect)
        let overlap = { (screen: NSScreen) -> CGFloat in
            let shared = screen.frame.intersection(appKit)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        guard let screen = NSScreen.screens.max(by: { overlap($0) < overlap($1) }) ?? NSScreen.main else {
            return rect
        }
        return axRect(fromAppKit: screen.visibleFrame)
    }
}
