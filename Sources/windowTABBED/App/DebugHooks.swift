#if DEBUG
import AppKit

/// Debug builds only: lets scripts drive the tab bars, since UI-testing tools can't click
/// a menu bar app's own windows. Trigger with scripts/debug.swift.
///
///   select <n>      click tab n (0-based) of the first group
///   close <n>       click × on tab n of the first group
///   move <n> <m>    drag tab n to position m
///   dragout <n>     drag tab n out of the bar, dropping it at the pointer
///   snapshot        save each bar as build/tabbar-<k>.png (and the Settings window, if open)
///   keydrag x1 y1 x2 y2   real mouse drag (AX points) with the grouping key held
final class DebugHooks {
    static let notification = Notification.Name("windowTABBED.debug")

    private let groups: GroupManager

    init(groups: GroupManager) {
        self.groups = groups
        DistributedNotificationCenter.default().addObserver(forName: Self.notification, object: nil, queue: .main) { [weak self] note in
            guard let command = note.object as? String else { return }
            self?.run(command)
        }
    }

    private func run(_ command: String) {
        let parts = command.split(separator: " ")
        let index = parts.count > 1 ? Int(parts[1]) : nil
        let group = groups.groups.first
        switch (parts.first, index, group) {
        case ("select", let n?, let group?) where group.windows.indices.contains(n):
            group.bar.model.onSelect?(group.windows[n].windowID)
        case ("close", let n?, let group?) where group.windows.indices.contains(n):
            group.bar.model.onClose?(group.windows[n].windowID)
        case ("move", let n?, let group?) where group.windows.indices.contains(n) && parts.count > 2:
            group.bar.model.onMove?(group.windows[n].windowID, Int(parts[2]) ?? n)
        case ("dragout", let n?, let group?) where group.windows.indices.contains(n):
            group.bar.model.onDragOut?(group.windows[n].windowID)
        case ("snapshot", _, _):
            snapshot()
        case ("keydrag", _, _) where parts.count == 5:
            let n = parts.dropFirst().compactMap { Double($0) }
            guard n.count == 4 else { fallthrough }
            keyDrag(from: CGPoint(x: n[0], y: n[1]), to: CGPoint(x: n[2], y: n[3]))
        default:
            log.notice("debug: can't run \(command, privacy: .public)")
            return
        }
        log.notice("debug: ran \(command, privacy: .public)")
    }

    private func snapshot() {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build")
        for (k, group) in groups.groups.enumerated() {
            save(group.bar.contentView, to: folder.appendingPathComponent("tabbar-\(k).png"))
        }
        if let settings = SettingsWindow.shared.window, settings.isVisible {
            // The frame view includes the title bar.
            save(settings.contentView?.superview, to: folder.appendingPathComponent("settings.png"))
        }
    }

    /// Posts press, 20 drag steps and release, ~16 ms apart, all carrying the grouping key's flag.
    private func keyDrag(from start: CGPoint, to end: CGPoint) {
        let flags: CGEventFlags = switch Settings.shared.groupingKey {
        case .shift: .maskShift
        case .option: .maskAlternate
        case .control: .maskControl
        case .command: .maskCommand
        case .fn: .maskSecondaryFn
        case nil: []
        }
        func post(_ type: CGEventType, _ point: CGPoint) {
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
        post(.leftMouseDown, start)
        let steps = 20
        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016 * Double(step)) {
                let t = CGFloat(step) / CGFloat(steps)
                post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016 * Double(steps) + 0.3) {
            post(.leftMouseUp, end)
        }
    }

    private func save(_ view: NSView?, to url: URL) {
        guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        log.notice("debug: saved \(url.path, privacy: .public)")
    }
}
#endif
