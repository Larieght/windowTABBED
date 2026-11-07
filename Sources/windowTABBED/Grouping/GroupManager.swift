import AppKit

/// Windows that share one tab bar. The active one sits at the group's frame; the others are
/// parked out of sight (see Parking) until you switch to them.
final class WindowGroup {
    var windows: [ExternalWindow]
    var activeID: CGWindowID
    /// Where the group is: the active window's frame, and where a tab goes when it becomes active.
    var frame: CGRect
    let bar = TabBarPanel()
    /// The whole group was sent to the Dock together.
    var isMinimized = false
    /// The active window is full screen: the group pauses and the bar hides.
    var isFullScreen = false
    var isPaused: Bool { isMinimized || isFullScreen }

    init(window: ExternalWindow, frame: CGRect) {
        windows = [window]
        activeID = window.windowID
        self.frame = frame
    }

    var active: ExternalWindow? { windows.first { $0.windowID == activeID } }

    func contains(_ id: CGWindowID) -> Bool { windows.contains { $0.windowID == id } }
}

/// The source of truth for all groups. Applies the rules in SPEC.md.
final class GroupManager {
    private(set) var groups: [WindowGroup] = []
    let watcher = WindowWatcher()
    /// A window being carried with the grouping key held: its group doesn't follow it.
    private var syncPausedID: CGWindowID?
    /// A group's active window you're dragging normally. Its bar follows the window server
    /// (followDrag), so the app's own move notifications, which arrive late, are ignored until
    /// you let go.
    private var draggingID: CGWindowID?
    /// How often we tried making a window one bar shorter, so we don't fight an app that refuses.
    private var shrinkAttempts: [CGWindowID: Int] = [:]
    private var pendingShrinks: [CGWindowID: DispatchWorkItem] = [:]
    private static let maxShrinkAttempts = 3

    /// A tab being pulled out of its bar (TearOff.swift).
    var tearOff: TearOffSession?
    let overlay = DragOverlay()
    let mover = WindowMover()

    /// Offset for a window that leaves its group with ×, so it doesn't vanish behind the group.
    private static let detachOffset: CGFloat = 30

    init() {
        watcher.onEvent = { [weak self] event in self?.handle(event) }
        recoverParkedWindows()
        // Safety net for apps that close windows without telling Accessibility (Finder).
        // Also for full screen, which doesn't always send a resize notification.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            // Not mid-drag: the full screen check asks the app through Accessibility, and an app
            // whose window is being dragged can't answer, which froze the bar for half a second.
            guard let self, !self.groups.isEmpty, self.draggingID == nil, self.syncPausedID == nil,
                  self.tearOff == nil else { return }
            self.removeClosedWindows()
            self.checkFullScreen()
        }
    }

    func group(containing id: CGWindowID) -> WindowGroup? {
        groups.first { $0.contains(id) }
    }

    // MARK: - Grouping

    /// Puts `window` into `target`'s group (making one if needed), at the group's frame,
    /// and makes it the active tab. A window is only ever in one group.
    func add(_ window: ExternalWindow, to target: ExternalWindow) {
        guard window != target, !window.isFullScreen, !target.isFullScreen else { return }

        let targetGroup = group(containing: target.windowID)
        if let current = group(containing: window.windowID) {
            if current === targetGroup { return }
            remove(window.windowID, from: current, detach: false)
        }

        let group: WindowGroup
        if let targetGroup {
            group = targetGroup
        } else {
            guard let frame = target.frame else { return }
            group = WindowGroup(window: target, frame: frame)
            group.bar.model.onSelect = { [weak self, weak group] id in
                guard let self, let group else { return }
                self.activate(id, in: group)
            }
            group.bar.model.onClose = { [weak self, weak group] id in
                guard let self, let group else { return }
                self.remove(id, from: group, detach: true)
            }
            group.bar.model.onMove = { [weak self, weak group] id, index in
                guard let self, let group else { return }
                self.move(id, to: index, in: group)
            }
            group.bar.model.onDragOut = { [weak self, weak group] id in
                guard let self, let group else { return }
                let point = ScreenGeometry.mouseLocation
                self.dragOut(id, from: group, to: CGRect(origin: CGPoint(x: point.x - 60, y: point.y - 12), size: group.frame.size))
            }
            group.bar.model.onDragChanged = { [weak self, weak group] id in
                guard let self, let group else { return }
                self.tabDragChanged(id, in: group)
            }
            group.bar.model.onDragEnded = { [weak self, weak group] id in
                guard let self, let group else { return }
                self.tabDragEnded(id, in: group)
            }
            groups.append(group)
            watcher.watch(target)
        }

        group.windows.append(window)
        watcher.watch(window)
        activate(window.windowID, in: group)
        log.notice("Grouped \(window.description, privacy: .public) with \(target.description, privacy: .public); \(group.windows.count) tabs")
    }

    /// Switches tabs: moves that window into the group's frame and brings it to the front, then
    /// parks the one it replaces. Its content shows instantly; only the tabs animate.
    func activate(_ id: CGWindowID, in group: WindowGroup) {
        guard let window = group.windows.first(where: { $0.windowID == id }) else { return }
        let previous = group.active
        group.activeID = id
        if previous?.windowID != id {
            window.setFrame(group.frame)
        }
        window.raise()
        // Park the old tab only once the new one covers it, so nothing flashes in between.
        if let previous, previous.windowID != id {
            park(previous, in: group)
        }
        refreshBar(of: group)
        // The other app raises its window asynchronously; order the bar again once it has.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.positionBar(of: group)
        }
    }

    private func park(_ window: ExternalWindow, in group: WindowGroup) {
        let size = window.frame?.size ?? group.frame.size
        window.setPosition(Parking.origin(for: size, near: group.frame))
    }

    /// Puts back windows a previous run left parked (it crashed or was force-quit), in the
    /// middle of their display.
    private func recoverParkedWindows() {
        for window in WindowDriver.allWindows() {
            guard let frame = window.frame, Parking.isParked(frame) else { continue }
            let visible = ScreenGeometry.visibleFrame(containing: frame)
            window.setPosition(CGPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2))
            log.notice("Brought back parked window \(window.description, privacy: .public)")
        }
    }

    /// Takes a window out of its group. With `detach`, the window stays open on top, nudged
    /// down-right so you can see it, while the group carries on behind it.
    func remove(_ id: CGWindowID, from group: WindowGroup, detach: Bool) {
        guard let index = group.windows.firstIndex(where: { $0.windowID == id }) else { return }
        let removed = group.windows.remove(at: index)
        watcher.unwatch(id)

        if group.windows.count <= 1 {
            dissolve(group)
        } else if group.activeID == id {
            activate(group.windows[min(index, group.windows.count - 1)].windowID, in: group)
        } else {
            refreshBar(of: group)
        }

        if detach {
            // It may be parked: bring it back next to the group.
            removed.setFrame(group.frame.offsetBy(dx: Self.detachOffset, dy: Self.detachOffset))
            removed.raise()
        }
    }

    /// Reorders tabs.
    func move(_ id: CGWindowID, to index: Int, in group: WindowGroup) {
        guard let from = group.windows.firstIndex(where: { $0.windowID == id }) else { return }
        let window = group.windows.remove(at: from)
        group.windows.insert(window, at: min(max(index, 0), group.windows.count))
        refreshBar(of: group)
    }

    /// A tab dragged out of the bar: the window leaves the group and lands at `frame`.
    func dragOut(_ id: CGWindowID, from group: WindowGroup, to frame: CGRect) {
        guard let window = group.windows.first(where: { $0.windowID == id }) else { return }
        remove(id, from: group, detach: false)
        // A parked tab may still have an old size: give it the group's.
        window.setFrame(frame)
        window.raise()
    }

    /// Called on every mouse drag event. Move notifications from the window's app arrive a few
    /// frames late, so while you drag a group's window its bar follows the window server's
    /// position instead, which is where the window really is right now.
    func followDrag(of id: CGWindowID) {
        guard let group = group(containing: id), group.activeID == id, !group.isPaused,
              let frame = WindowDriver.serverFrame(of: id)
        else { return }
        let first = draggingID != id
        draggingID = id
        group.bar.attach(above: id, frame: frame, placement: TabBarPanel.placement(for: frame) ?? .overlapping, reorder: first)
    }

    /// The button went up: the group catches up with wherever the window ended.
    func endDrag() {
        guard let id = draggingID else { return }
        draggingID = nil
        handle(.frameChanged(id))
    }

    /// While a window is carried with the grouping key held, its group stays put.
    func pauseSync(for id: CGWindowID) {
        syncPausedID = id
    }

    /// Drop ended. If the window is still the active tab somewhere, its group catches up with it.
    func resumeSync() {
        guard let id = syncPausedID else { return }
        syncPausedID = nil
        handle(.frameChanged(id))
    }

    /// Ends a group. Its parked tabs come back to the group's frame, behind the active one,
    /// and they all carry on as normal windows.
    func dissolve(_ group: WindowGroup) {
        for window in group.windows {
            watcher.unwatch(window.windowID)
            if window.windowID != group.activeID {
                window.setFrame(group.frame)
            }
        }
        group.bar.orderOut(nil)
        groups.removeAll { $0 === group }
        log.notice("Dissolved a group")
    }

    func dissolveAll() {
        groups.forEach(dissolve)
    }

    /// Ctrl+Option+←/→: previous or next tab of the group you're working in, wrapping around.
    func cycleTabs(by offset: Int) {
        guard let focused = WindowDriver.focusedWindow(),
              let group = group(containing: focused.windowID), !group.isPaused,
              let index = group.windows.firstIndex(where: { $0.windowID == group.activeID })
        else { return }
        let count = group.windows.count
        activate(group.windows[((index + offset) % count + count) % count].windowID, in: group)
    }

    // MARK: - Tab bar

    func refreshBar(of group: WindowGroup) {
        var windows = group.windows
        // A window pulled out mid-drag keeps its (collapsed) tab until you let go: removing the
        // tab would end the drag gesture.
        if let session = tearOff, session.isDetached, session.group === group {
            windows.insert(session.window, at: min(session.index, windows.count))
        }
        group.bar.model.tabs = windows.map { window in
            TabBarModel.Tab(id: window.windowID, title: window.title, icon: window.appIcon, tint: AppTint.color(for: window.app))
        }
        group.bar.model.activeID = group.activeID
        positionBar(of: group)
    }

    private func positionBar(of group: WindowGroup) {
        guard !group.isPaused else {
            group.bar.orderOut(nil)
            return
        }
        guard let active = group.active, let frame = active.frame else { return }
        if let placement = TabBarPanel.placement(for: frame) {
            shrinkAttempts[active.windowID] = nil
            group.bar.attach(above: active.windowID, frame: frame, placement: placement)
            return
        }
        // No room above or below (a window filling the screen). Overlap its top for now, and once
        // it has stopped moving (Fill and Zoom animate), make it one bar shorter.
        group.bar.attach(above: active.windowID, frame: frame, placement: .overlapping)
        guard (shrinkAttempts[active.windowID] ?? 0) < Self.maxShrinkAttempts,
              frame.height > TabBarPanel.height * 4
        else { return }
        pendingShrinks[active.windowID]?.cancel()
        let shrink = DispatchWorkItem { [weak self, weak group] in
            guard let self, let group else { return }
            self.makeRoomForBar(above: active, in: group)
        }
        pendingShrinks[active.windowID] = shrink
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: shrink)
    }

    private func makeRoomForBar(above window: ExternalWindow, in group: WindowGroup) {
        pendingShrinks[window.windowID] = nil
        guard group.activeID == window.windowID, !group.isPaused,
              let frame = window.frame, TabBarPanel.placement(for: frame) == nil
        else { return }
        shrinkAttempts[window.windowID, default: 0] += 1
        var shorter = frame
        shorter.origin.y += TabBarPanel.height
        shorter.size.height -= TabBarPanel.height
        window.setFrame(shorter)
        log.notice("No room for the tab bar, made \(window.description, privacy: .public) shorter")
        followActiveWindow(of: group)
    }

    private func checkFullScreen() {
        for group in groups where !group.isMinimized {
            updateFullScreen(of: group)
        }
    }

    /// Full screen gives the active window a Space of its own. Pause the group until it comes
    /// back: the bar hides and the other tabs keep their normal frame. Returns true while paused.
    @discardableResult
    private func updateFullScreen(of group: WindowGroup) -> Bool {
        guard let active = group.active else { return false }
        let fullScreen = active.isFullScreen
        guard fullScreen != group.isFullScreen else { return fullScreen }
        group.isFullScreen = fullScreen
        if fullScreen {
            log.notice("Group paused: \(active.description, privacy: .public) went full screen")
            positionBar(of: group)
        } else {
            log.notice("Group resumed after full screen")
            followActiveWindow(of: group)
        }
        return fullScreen
    }

    /// The active window moved or resized: the group is wherever it is now, and the bar goes with it.
    /// The parked tabs stay put; they get the new frame when you switch to them.
    private func followActiveWindow(of group: WindowGroup) {
        guard let frame = group.active?.frame else { return }
        group.frame = frame
        positionBar(of: group)
    }

    /// Not every app reports its closed windows reliably, so ask the window server what still exists.
    private func removeClosedWindows() {
        let existing = WindowDriver.existingWindowIDs()
        for group in groups {
            for window in group.windows where !existing.contains(window.windowID) {
                log.notice("Window \(window.windowID, privacy: .public) is gone, removing its tab")
                remove(window.windowID, from: group, detach: false)
            }
        }
    }

    // MARK: - Events

    private func handle(_ event: WindowEvent) {
        switch event {
        case .frameChanged(let id):
            // Only the active window leads. Parking the others sends move notifications
            // too, and those are ignored.
            guard id != syncPausedID, id != draggingID,
                  let group = group(containing: id), group.activeID == id, !group.isMinimized
            else { return }
            if updateFullScreen(of: group) { return }
            followActiveWindow(of: group)

        case .minimized(let id):
            // Minimizing the active tab sends the whole group to the Dock. The others' own
            // minimize notifications arrive while isMinimized is already set, and are ignored.
            guard let group = group(containing: id), group.activeID == id, !group.isMinimized else { return }
            group.isMinimized = true
            positionBar(of: group)
            for window in group.windows where window.windowID != id {
                window.setMinimized(true)
            }
            log.notice("Minimized a group of \(group.windows.count, privacy: .public)")

        case .restored(let id):
            // Restoring any of them brings the whole group back, with that one in front.
            guard let group = group(containing: id), group.isMinimized else { return }
            group.isMinimized = false
            for window in group.windows where window.windowID != id {
                window.setMinimized(false)
            }
            activate(id, in: group)
            // The others come out of the Dock with an animation, and the app may focus one of
            // them on the way. Once they've landed, put the one you restored back in front.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.activate(id, in: group)
            }
            log.notice("Restored a group of \(group.windows.count, privacy: .public)")

        case .titleChanged(let id):
            if let group = group(containing: id) {
                refreshBar(of: group)
            }

        case .closed(let id):
            if let group = group(containing: id) {
                remove(id, from: group, detach: false)
            }

        case .unidentifiedClose:
            removeClosedWindows()

        case .focusChanged:
            // Closing a window also moves focus, so this catches closes the watcher missed.
            removeClosedWindows()
            // Cmd-`, the Window menu or Mission Control may have focused a parked tab:
            // bring it into the group's frame. Minimizing the active tab hands focus to a
            // background tab just before the minimize notification arrives: don't switch,
            // or the whole group wouldn't follow.
            if let focused = WindowDriver.focusedWindow(),
               let group = group(containing: focused.windowID), !group.isPaused,
               group.activeID != focused.windowID,
               !(group.active?.isMinimized ?? false) {
                activate(focused.windowID, in: group)
            }
            checkFullScreen()
            // Any window may now cover a group, or a group window may be back on top:
            // keep every bar directly above its active window.
            groups.forEach(positionBar)
        }
    }
}

