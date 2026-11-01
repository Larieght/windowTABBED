import AppKit
import os

/// Read with: /usr/bin/log stream --predicate 'subsystem == "windowTABBED"'
let log = Logger(subsystem: "windowTABBED", category: "app")

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let permissions = Permissions()
    private var groups: GroupManager?
    #if DEBUG
    private var debugHooks: DebugHooks?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "windowTABBED")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        log.notice("Launched, Accessibility trusted: \(Permissions.isTrusted, privacy: .public)")
        if !Permissions.isTrusted {
            Permissions.requestAccess()
        }
        permissions.waitForAccess { [weak self] in
            self?.accessGranted()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        groups?.dissolveAll()
    }

    private func accessGranted() {
        log.notice("Accessibility access granted")
        let groups = GroupManager()
        self.groups = groups
        #if DEBUG
        debugHooks = DebugHooks(groups: groups)
        #endif
    }

    // MARK: - Menu

    // Rebuilt every time it opens, so the permission line is always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabledItem("windowTABBED"))
        menu.addItem(.separator())

        if let groups {
            // Temporary until Shift + drag grouping (step 4).
            let group = NSMenuItem(title: "Group with Window Behind", action: #selector(groupWithWindowBehind), keyEquivalent: "")
            group.target = self
            menu.addItem(group)

            let ungroup = NSMenuItem(title: "Ungroup All", action: groups.groups.isEmpty ? nil : #selector(ungroupAll), keyEquivalent: "")
            ungroup.target = self
            menu.addItem(ungroup)

            let count = groups.groups.count
            menu.addItem(disabledItem(count == 1 ? "1 group" : "\(count) groups"))
        } else {
            let allow = NSMenuItem(title: "Allow Accessibility…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            allow.target = self
            menu.addItem(allow)
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit windowTABBED", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func openAccessibilitySettings() {
        Permissions.openSettings()
    }

    /// Groups the window you're in with the window right behind it (or adds it to that window's group).
    @objc private func groupWithWindowBehind() {
        guard let groups, let front = WindowDriver.focusedWindow() else {
            return log.notice("Group: no focused window")
        }
        let ownGroup = groups.group(containing: front.windowID)
        let candidates = WindowDriver.allWindows().filter { $0 != front && !(ownGroup?.contains($0.windowID) ?? false) }        // Window-server order is front to back, so the first match is the window just behind.
        guard let behind = WindowDriver.normalWindowOrder().lazy
            .compactMap({ id in candidates.first { $0.windowID == id } })
            .first
        else {
            return log.notice("Group: no window behind \(front.description, privacy: .public)")
        }
        groups.add(front, to: behind)
    }

    @objc private func ungroupAll() {
        groups?.dissolveAll()
    }
}
