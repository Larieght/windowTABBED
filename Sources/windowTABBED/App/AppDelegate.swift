import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let permissions = Permissions()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "windowTABBED")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        if !Permissions.isTrusted {
            Permissions.requestAccess()
        }
        permissions.waitForAccess { [weak self] in
            self?.accessGranted()
        }
    }

    private func accessGranted() {
        // Window tracking and grouping start here in the next steps.
        NSLog("windowTABBED: Accessibility access granted")
    }

    // MARK: - Menu

    // Rebuilt every time it opens, so the permission line is always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabledItem("windowTABBED"))
        menu.addItem(.separator())

        if Permissions.isTrusted {
            menu.addItem(disabledItem("Accessibility: allowed ✓"))
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
}
