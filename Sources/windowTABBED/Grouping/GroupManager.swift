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
            self?.positionBar(of: group)
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
            removed.raise()
        }
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
            guard let group = group(containing: id), group.activeID == id,
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
            // Any window may now cover a group, or a group window may be back on top:
            // keep every bar directly above its active window.
            groups.forEach(positionBar)
        }
    }
}
