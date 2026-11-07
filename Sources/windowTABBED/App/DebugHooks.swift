#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: lets scripts drive the tab bars, since UI-testing tools can't click
/// a menu bar app's own windows. Trigger with scripts/debug.swift.
///
///   select <n>      click tab n (0-based) of the first group
///   close <n>       click × on tab n of the first group
///   move <n> <m>    drag tab n to position m
///   dragout <n>     drag tab n out of the bar, dropping it at the pointer
///   login on|off   open at login (logs the resulting status)
///   size small|medium|large|extraLarge   the tab size
///   theme aqua|glass|flat|pill|metallic|retro   the tab theme
///   tearoff window|outline|tab   how a tab dragged out of the bar looks
///   themes <bundle id>…    show a bar of those apps in every theme for 4 s (logs the window number)
///   preview <bundle id>…   show an active and a background tab for each app for 4 s (logs the window number)
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
        case ("setpos", let n?, let group?) where group.windows.indices.contains(n) && parts.count == 4:
            let window = group.windows[n]
            window.setPosition(CGPoint(x: Double(parts[2]) ?? 0, y: Double(parts[3]) ?? 0))
            log.notice("debug: \(window.description, privacy: .public) now at \(String(describing: window.frame), privacy: .public)")
        case ("pin", _, let group?):
            groups.setPinned(!group.bar.isPinned, group)
            log.notice("debug: pinned \(group.bar.isPinned, privacy: .public) covered \(group.bar.isCovered, privacy: .public) alpha \(group.bar.alphaValue, privacy: .public)")
        case ("pinlook", _, _) where parts.count == 2:
            Settings.shared.pinnedLook = PinnedLook(rawValue: String(parts[1])) ?? .dimmed
        case ("menu", _, _):
            let titles = (NSApp.delegate as? AppDelegate)?.currentMenuTitles() ?? []
            log.notice("debug: menu \(titles.joined(separator: " | "), privacy: .public)")
        case ("settings", _, _):
            SettingsWindow.shared.show()
        case ("style", _, _) where parts.count == 2:
            Settings.shared.tabStyle = TabStyle(rawValue: String(parts[1])) ?? .full
        case ("theme", _, _) where parts.count == 2:
            Settings.shared.tabTheme = TabTheme(rawValue: String(parts[1])) ?? .aqua
        case ("tearoff", _, _) where parts.count == 2:
            Settings.shared.tearOffStyle = TearOffStyle(rawValue: String(parts[1])) ?? .window
        case ("record", _, _):
            SettingsWindow.shared.recorder.start(onRecord: Settings.shared.useRecorded)
        case ("press", _, _) where parts.count == 2:
            press(String(parts[1]))
        case ("release", _, _):
            Self.releaseModifiers()
        case ("size", _, _) where parts.count == 2:
            Settings.shared.tabSize = TabSize(rawValue: String(parts[1])) ?? .small
        case ("login", _, _) where parts.count == 2:
            LoginItem.shared.set(parts[1] == "on")
            log.notice("debug: login item status \(LoginItem.shared.status.rawValue, privacy: .public)")
        case ("glyph", _, _):
            // The menu bar glyph at 8x, black on white, for checking its drawing.
            let size = NSSize(width: 144, height: 144)
            let out = NSImage(size: size)
            out.lockFocus()
            NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
            MenuBarIcon.image.draw(in: NSRect(x: 0, y: 36, width: 108, height: 108))
            MenuBarIcon.image.draw(in: NSRect(x: 112, y: 4, width: 18, height: 18))
            out.unlockFocus()
            if let tiff = out.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("build/glyph.png")
                try? png.write(to: url)
            }
        case ("themes", _, _) where parts.count >= 2:
            MainActor.assumeIsolated { themesPreview(parts.dropFirst().map(String.init)) }
        case ("preview", _, _) where parts.count >= 2:
            MainActor.assumeIsolated { preview(parts.dropFirst().map(String.init)) }
        case ("snapshot", _, _):
            snapshot()
        case ("keydrag", _, _) where parts.count == 5:
            let n = parts.dropFirst().compactMap { Double($0) }
            guard n.count == 4 else { return }
            keyDrag(from: CGPoint(x: n[0], y: n[1]), to: CGPoint(x: n[2], y: n[3]))
        case ("drag", _, let group?) where parts.count == 5:
            let n = parts.dropFirst().compactMap { Double($0) }
            guard n.count == 4 else { return }
            drag(from: CGPoint(x: n[0], y: n[1]), to: CGPoint(x: n[2], y: n[3]), measuring: group)
        default:
            log.notice("debug: can't run \(command, privacy: .public)")
            return
        }
        log.notice("debug: ran \(command, privacy: .public)")
    }

    /// Tabs for apps you may not have windows of, without touching anyone's windows.
    private var previewPanel: NSPanel?

    @MainActor private func preview(_ bundleIDs: [String]) {
        let rows = bundleIDs.compactMap { id -> (TabBarModel.Tab, TabBarModel.Tab)? in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let tint = AppTint.dominantColor(of: icon) ?? AppTint.fallback
            let name = url.deletingPathExtension().lastPathComponent
            return (TabBarModel.Tab(id: 1, title: name, icon: icon, tint: tint),
                    TabBarModel.Tab(id: 2, title: name, icon: icon, tint: tint))
        }
        let view = VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .bottom, spacing: TabBarPanel.tabSpacing) {
                    TabFace(tab: row.0, isActive: true, flipped: false, iconOnly: false, width: 184)
                    TabFace(tab: row.1, isActive: false, flipped: false, iconOnly: false, width: 184)
                }
            }
        }
        .padding(10)
        .background(Color(white: 0.15))
        showPreview(view)
    }

    /// Every theme: a bar of the given apps (the first one active) on a window edge, over a
    /// colorful backdrop so glass has something to show.
    @MainActor private func themesPreview(_ bundleIDs: [String]) {
        let tabs = bundleIDs.enumerated().compactMap { index, id -> TabBarModel.Tab? in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return TabBarModel.Tab(id: CGWindowID(index + 1), title: url.deletingPathExtension().lastPathComponent,
                                   icon: icon, tint: AppTint.dominantColor(of: icon) ?? AppTint.fallback)
        }
        let view = VStack(alignment: .leading, spacing: 14) {
            ForEach(TabTheme.allCases) { theme in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom, spacing: theme.resolved.spacing) {
                        ForEach(tabs) { tab in
                            TabFace(tab: tab, isActive: tab.id == 1, flipped: false, iconOnly: false,
                                    width: 160, theme: theme.resolved)
                        }
                    }
                    .frame(height: TabBarPanel.height, alignment: .bottom)
                    .padding(.leading, TabBarPanel.inset)
                    UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10)
                        .fill(Color(white: 0.13))
                        .frame(width: 560, height: 26)
                }
            }
        }
        .padding(16)
        .background(LinearGradient(colors: [Color(red: 0.12, green: 0.45, blue: 0.55), Color(red: 0.32, green: 0.28, blue: 0.62),
                                            Color(red: 0.85, green: 0.45, blue: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
        showPreview(view)
    }

    @MainActor private func showPreview<V: View>(_ view: V) {
        // Shown for real for a few seconds, so `screencapture -l` sees exactly what the bar draws.
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = NSPanel(contentRect: ScreenGeometry.appKitRect(fromAX: CGRect(x: 20, y: 900, width: size.width, height: size.height)),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isReleasedWhenClosed = false
        panel.orderFrontRegardless()
        previewPanel = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.previewPanel?.orderOut(nil)
            self?.previewPanel = nil
        }
        log.notice("debug: preview window \(panel.windowNumber, privacy: .public)")
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

    /// Posts press, 20 drag steps and release, ~16 ms apart, all carrying the grouping key's flags.
    private func keyDrag(from start: CGPoint, to end: CGPoint) {
        let key = Settings.shared.groupingKey?.flags ?? []
        let pairs: [(NSEvent.ModifierFlags, CGEventFlags)] = [
            (.shift, .maskShift), (.option, .maskAlternate), (.control, .maskControl),
            (.command, .maskCommand), (.function, .maskSecondaryFn),
        ]
        let flags = pairs.filter { key.contains($0.0) }.reduce(into: CGEventFlags()) { $0.insert($1.1) }
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
            Self.releaseModifiers()
        }
    }

    /// Presses modifiers one by one (e.g. `press ctrl,opt`), then lets go of them one by one.
    private func press(_ names: String) {
        let keys: [String: (CGKeyCode, CGEventFlags)] = [
            "shift": (56, .maskShift), "ctrl": (59, .maskControl), "opt": (58, .maskAlternate),
            "cmd": (55, .maskCommand), "fn": (63, .maskSecondaryFn),
        ]
        let chosen = names.split(separator: ",").compactMap { keys[String($0)] }
        var flags = CGEventFlags()
        var steps: [CGEventFlags] = []
        for (_, flag) in chosen { flags.insert(flag); steps.append(flags) }
        for (_, flag) in chosen { flags.remove(flag); steps.append(flags) }
        for (i, state) in steps.enumerated() {
            let code = chosen[i % chosen.count].0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 * Double(i)) {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
                event?.type = .flagsChanged
                event?.flags = state
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    /// Events posted with a modifier flag leave it set system-wide, as if the key were still
    /// held, until a key event says otherwise.
    private static func releaseModifiers() {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 63, keyDown: false)
        event?.type = .flagsChanged
        event?.flags = []
        event?.post(tap: .cghidEventTap)
    }

    /// A plain drag (no grouping key) over ~1 s that logs how far the tab bar trails the active
    /// window. Runs off the main thread so windowTABBED handles the drag as it would a real one,
    /// and samples the window server halfway between mouse events.
    private func drag(from start: CGPoint, to end: CGPoint, measuring group: WindowGroup) {
        let windowID = group.activeID, barID = CGWindowID(group.bar.windowNumber)
        func post(_ type: CGEventType, _ point: CGPoint) {
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            // Without this the events pick up modifier state left behind by keydrag.
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
        func lag() -> CGFloat {
            guard let active = WindowDriver.serverFrame(of: windowID), let bar = WindowDriver.serverFrame(of: barID)
            else { return 0 }
            return hypot(bar.minX - TabBarPanel.inset - active.minX, bar.maxY - active.minY)
        }
        DispatchQueue.global(qos: .userInteractive).async {
            var samples: [CGFloat] = []
            post(.leftMouseDown, start)
            let steps = 120
            for step in 1...steps {
                usleep(4_000)
                let t = CGFloat(step) / CGFloat(steps)
                post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
                usleep(4_000)
                if step > 5 { samples.append(lag()) }
            }
            usleep(100_000)
            post(.leftMouseUp, end)
            usleep(500_000)
            let average = samples.reduce(0, +) / CGFloat(max(samples.count, 1))
            log.notice("debug: bar lag avg \(Int(average), privacy: .public) pt, max \(Int(samples.max() ?? 0), privacy: .public) pt, after release \(Int(lag()), privacy: .public) pt")
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
