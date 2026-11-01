import AppKit
import os

/// Read with: /usr/bin/log stream --predicate 'subsystem == "windowTABBED"'
let log = Logger(subsystem: "windowTABBED", category: "app")

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let permissions = Permissions()

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

    private func accessGranted() {
        // Window tracking and grouping start here in the next steps.
        log.notice("Accessibility access granted")
    }

    // MARK: - Menu

    // Rebuilt every time it opens, so the permission line is always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabledItem("windowTABBED"))
        menu.addItem(.separator())

        if Permissions.isTrusted {
            menu.addItem(disabledItem("Accessibility: allowed ✓"))
            menu.addItem(.separator())
            addDebugItems(to: menu)
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

    // MARK: - Debug (temporary, to check WindowDriver by hand)

    private var lastDebugResult: String?

    private func addDebugItems(to menu: NSMenu) {
        menu.addItem(disabledItem("Debug"))

        let windowsItem = NSMenuItem(title: "Raise a window", action: nil, keyEquivalent: "")
        let windowsMenu = NSMenu()
        for window in WindowDriver.allWindows() {
            let item = NSMenuItem(title: "\(window.appName) — \(window.title)", action: #selector(debugRaise(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = window.windowID
            if let icon = window.appIcon {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            windowsMenu.addItem(item)
        }
        if windowsMenu.items.isEmpty {
            windowsMenu.addItem(disabledItem("No windows found"))
        }
        windowsItem.submenu = windowsMenu
        menu.addItem(windowsItem)

        let nudge = NSMenuItem(title: "Nudge focused window", action: #selector(debugNudge), keyEquivalent: "")
        nudge.target = self
        menu.addItem(nudge)

        let stack = NSMenuItem(title: "Stack 2nd window onto focused one", action: #selector(debugStack), keyEquivalent: "")
        stack.target = self
        menu.addItem(stack)

        if let lastDebugResult {
            menu.addItem(disabledItem(lastDebugResult))
        }
    }

    private func report(_ message: String) {
        lastDebugResult = message
        log.notice("debug: \(message, privacy: .public)")
    }

    @objc private func debugRaise(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? CGWindowID,
              let window = WindowDriver.allWindows().first(where: { $0.windowID == id })
        else { return report("Raise: window is gone") }
        window.raise()
        report("Raised \(window)")
    }

    /// Moves the focused window 80 pt right, then back, to prove we can drive it.
    @objc private func debugNudge() {
        guard let window = WindowDriver.focusedWindow(), let start = window.frame else {
            return report("Nudge: no focused window")
        }
        let moved = window.setFrame(start.offsetBy(dx: 80, dy: 0))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let back = window.setFrame(start)
            self?.report("Nudged \(window.appName): \(Self.describe(start)) → \(Self.describe(moved)) → \(Self.describe(back))")
        }
    }

    /// The core trick behind tabs: put another window at exactly the same frame, behind the focused one.
    @objc private func debugStack() {
        guard let front = WindowDriver.focusedWindow(), let target = front.frame else {
            return report("Stack: no focused window")
        }
        // Window-server order is front to back, so the first other standard window is the one just behind.
        let order = WindowDriver.normalWindowOrder()
        let candidates = WindowDriver.allWindows().filter { $0 != front }
        guard let second = order.lazy.compactMap({ id in candidates.first { $0.windowID == id } }).first else {
            return report("Stack: no second window on screen")
        }
        let result = second.setFrame(target)
        front.raise()
        let matched = result.map { $0.integral == target.integral } ?? false
        report("Stacked \(second.appName) onto \(front.appName): \(matched ? "exact match ✓" : "got \(Self.describe(result)), wanted \(Self.describe(target))")")
    }

    private static func describe(_ rect: CGRect?) -> String {
        guard let rect else { return "?" }
        return "(\(Int(rect.minX)), \(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height)))"
    }
}
