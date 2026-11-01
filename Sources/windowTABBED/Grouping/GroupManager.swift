import AppKit

/// Windows that share one tab bar. All of them sit at the same frame; the active one is on top.
final class WindowGroup {
    var windows: [ExternalWindow]
    var activeID: CGWindowID
    let bar = TabBarPanel()

    init(window: ExternalWindow) {
        windows = [window]
        activeID = window.windowID
    }

    var active: ExternalWindow? { windows.first { $0.windowID == activeID } }

    func contains(_ id: CGWindowID) -> Bool { windows.contains { $0.windowID == id } }
}

/// The source of truth for all groups. Applies the rules in SPEC.md.
final class GroupManager {
    private(set) var groups: [WindowGroup] = []
    private let watcher = WindowWatcher()
    /// A window being carried with the grouping key held: its group doesn't follow it.
    private var syncPausedID: CGWindowID?

    /// Offset for a window that leaves its group with ×, so it doesn't vanish behind the group.
    private static let detachOffset: CGFloat = 30

    init() {
        watcher.onEvent = { [weak self] event in self?.handle(event) }
        // Safety net for apps that close windows without telling Accessibility (Finder).
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, !self.groups.isEmpty else { return }
            self.removeClosedWindows()
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
            group = WindowGroup(window: target)
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
                self.dragOut(id, from: group, to: ScreenGeometry.mouseLocation)
            }
            groups.append(group)
            watcher.watch(target)
        }

        guard let frame = group.active?.frame else { return }
        window.setFrame(frame)
        group.windows.append(window)
        watcher.watch(window)
        activate(window.windowID, in: group)
        log.notice("Grouped \(window.description, privacy: .public) with \(target.description, privacy: .public); \(group.windows.count) tabs")
    }

    /// Switches tabs: brings that window to the front. Its content shows instantly; only the tabs animate.
    func activate(_ id: CGWindowID, in group: WindowGroup) {
        guard let window = group.windows.first(where: { $0.windowID == id }) else { return }
        group.activeID = id
        window.raise()
        refreshBar(of: group)
        // The other app raises its window asynchronously; order the bar again once it has.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.fixStacking()
            self?.positionBar(of: group)
        }
    }

    /// Bringing an app to the front pulls ALL its windows forward, including ones sitting
    /// behind another group's active tab. Put each group's active window back on top of its
    /// own background tabs, then return the window you're actually using to the very top.
    private func fixStacking() {
        let order = WindowDriver.normalWindowOrder()
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        var restacked = false
        for group in groups {
            guard let active = group.active, let activeRank = rank[active.windowID] else { continue }
            let buried = group.windows.contains { $0.windowID != active.windowID && (rank[$0.windowID] ?? .max) < activeRank }
            if buried {
                active.raiseInPlace()
                positionBar(of: group)
                restacked = true
            }
        }
        if restacked {
            WindowDriver.focusedWindow()?.raiseInPlace()
            log.notice("Restacked groups after an app came forward")
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

        if detach, let frame = removed.frame {
            removed.setFrame(frame.offsetBy(dx: Self.detachOffset, dy: Self.detachOffset))
            raiseOnTop(removed)
        }
    }

    /// Raises a window that just left a group, then repairs whatever its app dragged forward with it.
    private func raiseOnTop(_ window: ExternalWindow) {
        window.raise()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.fixStacking()
        }
    }

    /// Reorders tabs.
    func move(_ id: CGWindowID, to index: Int, in group: WindowGroup) {
        guard let from = group.windows.firstIndex(where: { $0.windowID == id }) else { return }
        let window = group.windows.remove(at: from)
        group.windows.insert(window, at: min(max(index, 0), group.windows.count))
        refreshBar(of: group)
    }

    /// A tab dragged out of the bar: the window leaves the group and lands at `point`,
    /// with the pointer on its title bar as if you'd been carrying it there.
    func dragOut(_ id: CGWindowID, from group: WindowGroup, to point: CGPoint) {
        guard let window = group.windows.first(where: { $0.windowID == id }) else { return }
        remove(id, from: group, detach: false)
        window.setPosition(CGPoint(x: point.x - 60, y: point.y - 12))
        raiseOnTop(window)
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

    /// Ends a group. Its windows stay where they are as normal windows.
    func dissolve(_ group: WindowGroup) {
        for window in group.windows {
            watcher.unwatch(window.windowID)
        }
        group.bar.orderOut(nil)
        groups.removeAll { $0 === group }
        log.notice("Dissolved a group")
    }

    func dissolveAll() {
        groups.forEach(dissolve)
    }

    // MARK: - Tab bar

    private func refreshBar(of group: WindowGroup) {
        group.bar.model.tabs = group.windows.map { window in
            TabBarModel.Tab(id: window.windowID, title: window.title, icon: window.appIcon, tint: AppTint.color(for: window.app))
        }
        group.bar.model.activeID = group.activeID
        positionBar(of: group)
    }

    private func positionBar(of group: WindowGroup) {
        guard let active = group.active, let frame = active.frame else { return }
        group.bar.attach(above: active.windowID, frame: frame)
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
            // Only the active window leads. The others move because we move them,
            // and their own move notifications land here too and are ignored.
            guard id != syncPausedID,
                  let group = group(containing: id), group.activeID == id,
                  let frame = group.active?.frame
            else { return }
            for window in group.windows where window.windowID != id {
                window.setFrame(frame)
            }
            positionBar(of: group)

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
            // Cmd-Tab, the Dock or Mission Control may have brought a background tab forward.
            if let focused = WindowDriver.focusedWindow(),
               let group = group(containing: focused.windowID),
               group.activeID != focused.windowID {
                group.activeID = focused.windowID
                refreshBar(of: group)
            }
            // Cmd-Tab and the Dock bring every window of an app forward, background tabs included.
            fixStacking()
            // Any window may now cover a group, or a group window may be back on top:
            // keep every bar directly above its active window.
            groups.forEach(positionBar)
        }
    }
}
