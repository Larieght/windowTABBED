import CoreGraphics

/// Where background tabs wait: pushed off the bottom corner of their display, so only a
/// 1-point sliver stays on screen. macOS has no way to hide one window of another app
/// (Cmd-H hides the whole app, minimizing animates), and a window that's out of sight
/// doesn't have to follow the group around, so nothing trails behind a drag.
enum Parking {
    /// macOS keeps this much of a window on screen horizontally.
    private static let sliver: CGFloat = 1

    /// The position that parks a window of `size` for a group at `groupFrame`. It uses the
    /// bottom-right corner, or bottom-left if another display sits to the right, so the
    /// window never shows up on a neighbor.
    static func origin(for size: CGSize, near groupFrame: CGRect) -> CGPoint {
        let screen = ScreenGeometry.screenFrame(containing: groupFrame)
        let neighborOnRight = ScreenGeometry.screenFrames.contains { other in
            other != screen && other.minX >= screen.maxX - 1
                && other.minY < screen.maxY && other.maxY > screen.minY
        }
        let x = neighborOnRight ? screen.minX - size.width + sliver : screen.maxX - sliver
        return CGPoint(x: x, y: screen.maxY - sliver)
    }

    /// True for a window that sits where `origin` puts one: left behind if windowTABBED
    /// didn't quit normally.
    static func isParked(_ frame: CGRect) -> Bool {
        ScreenGeometry.screenFrames.contains { screen in
            // macOS pulls the window up until its title bar is on screen, so y isn't exact.
            let atBottom = frame.minY > screen.maxY - 60 && frame.minY < screen.maxY
            let atSide = abs(frame.minX - (screen.maxX - sliver)) < 1 || abs(frame.maxX - (screen.minX + sliver)) < 1
            return atBottom && atSide
        }
    }
}
