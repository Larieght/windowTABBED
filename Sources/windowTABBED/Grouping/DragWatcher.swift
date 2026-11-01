import AppKit
import SwiftUI

/// Watches window drags across the whole screen. Hold the grouping key and drag a window over
/// another one: a blue outline shows on the target, and letting go there groups them.
final class DragWatcher {
    private let groups: GroupManager
    private var monitors: [Any] = []
    private let outline = DropOutlinePanel()

    /// The window under the pointer when the button went down.
    private var pressed: WindowDriver.ServerWindow?
    /// Set once that window is actually moving with the grouping key held.
    private var dragged: ExternalWindow?
    private var target: ExternalWindow?

    init(groups: GroupManager) {
        self.groups = groups
        // Global monitors see events going to other apps, which is where window drags happen.
        monitor(.leftMouseDown) { watcher, _ in watcher.mouseDown() }
        monitor(.leftMouseDragged) { watcher, event in watcher.mouseDragged(keyHeld: Self.keyHeld(in: event)) }
        monitor(.leftMouseUp) { watcher, event in watcher.mouseUp(keyHeld: Self.keyHeld(in: event)) }
        monitor(.flagsChanged) { watcher, event in watcher.keyChanged(keyHeld: Self.keyHeld(in: event)) }
    }

    /// Read from each event rather than the global key state, so it matches what that event carried.
    private static func keyHeld(in event: NSEvent) -> Bool {
        guard let key = Settings.shared.groupingKey else { return false }
        return event.modifierFlags.contains(key.flag)
    }

    private func monitor(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (DragWatcher, NSEvent) -> Void) {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            if let self { handler(self, event) }
        }) {
            monitors.append(monitor)
        }
    }

    private func mouseDown() {
        reset()
        // Window server only: this runs on every click, so Accessibility waits until a drag starts.
        pressed = WindowDriver.serverWindow(at: ScreenGeometry.mouseLocation)
    }

    private func mouseDragged(keyHeld: Bool) {
        guard let pressed, keyHeld else {
            clearTarget()
            return
        }

        if dragged == nil {
            // Only a window that is moving counts. Dragging inside its content (selecting text) doesn't.
            guard let now = WindowDriver.serverFrame(of: pressed.id), now.origin != pressed.frame.origin,
                  let window = WindowDriver.window(for: pressed)
            else { return }
            dragged = window
            // Let the window leave its group visually while you carry it.
            groups.pauseSync(for: window.windowID)
        }
        guard let dragged else { return }

        // The pointer is over the dragged window itself, so look underneath it,
        // and skip the rest of its own group, stacked right behind it.
        var excluded: Set<CGWindowID> = [dragged.windowID]
        if let own = groups.group(containing: dragged.windowID) {
            excluded.formUnion(own.windows.map(\.windowID))
        }
        let point = ScreenGeometry.mouseLocation
        let hit = WindowDriver.serverWindow(at: point, excluding: excluded)
        if hit?.id != target?.windowID {
            target = hit.flatMap(WindowDriver.window(for:))
        }

        if let target, let frame = target.frame {
            outline.show(around: frame, above: target.windowID)
        } else {
            outline.hide()
        }
    }

    private func mouseUp(keyHeld: Bool) {
        defer { reset() }
        guard let dragged else { return }
        if let target, keyHeld {
            groups.add(dragged, to: target)
        }
        // After grouping: nothing left to catch up. Without a target: the window's own group follows it.
        groups.resumeSync()
    }

    private func keyChanged(keyHeld: Bool) {
        // Letting go of the key mid-drag cancels the drop.
        if dragged != nil, !keyHeld {
            clearTarget()
        }
    }

    private func clearTarget() {
        target = nil
        outline.hide()
    }

    private func reset() {
        pressed = nil
        dragged = nil
        clearTarget()
    }
}

/// The blue outline on the window you're about to drop onto.
private final class DropOutlinePanel: NSPanel {
    private var shownFrame: CGRect?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .normal
        collectionBehavior = [.managed, .ignoresCycle, .transient]
        contentView = NSHostingView(rootView: DropOutline())
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Just above the target, so the window you're carrying stays on top of it.
    func show(around frame: CGRect, above windowID: CGWindowID) {
        let padded = frame.insetBy(dx: -4, dy: -4)
        if padded != shownFrame {
            setFrame(ScreenGeometry.appKitRect(fromAX: padded), display: true)
            shownFrame = padded
        }
        order(.above, relativeTo: Int(windowID))
    }

    func hide() {
        guard shownFrame != nil else { return }
        orderOut(nil)
        shownFrame = nil
    }
}

private struct DropOutline: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.accentColor.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 4))
    }
}
