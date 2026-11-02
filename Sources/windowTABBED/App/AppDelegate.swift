import AppKit
import os

/// Read with: /usr/bin/log stream --predicate 'subsystem == "windowTABBED"'
let log = Logger(subsystem: "windowTABBED", category: "app")

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let permissions = Permissions()
    private var groups: GroupManager?
    private var dragWatcher: DragWatcher?
    private var tabShortcuts: TabShortcuts?
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
        dragWatcher = DragWatcher(groups: groups)
        tabShortcuts = TabShortcuts(groups: groups)
        if Settings.shared.groupingKey == nil {
            SettingsWindow.shared.show(welcome: true)
        }
        #if DEBUG
        debugHooks = DebugHooks(groups: groups)
        #endif
    }

    // MARK: - Menu

    #if DEBUG
    /// The menu as it would show right now, for the `menu` debug command.
    func currentMenuTitles() -> [String] {
        guard let menu = statusItem.menu else { return [] }
        menuNeedsUpdate(menu)
        return menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
    }
    #endif

    // Rebuilt every time it opens, so the permission line is always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabledItem("windowTABBED \(Self.versionDescription)"))
        menu.addItem(.separator())

        if let groups {
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
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(withTitle: "Quit windowTABBED", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// "1.0.0 (5b945aa)", plus ", debug" for debug builds. The commit comes from build.sh.
    private static var versionDescription: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        var details = [info["WTCommit"] as? String ?? "unknown"]
        if info["WTBuildConfig"] as? String == "debug" { details.append("debug") }
        return "\(version) (\(details.joined(separator: ", ")))"
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func openAccessibilitySettings() {
        Permissions.openSettings()
    }

    @objc private func openSettings() {
        SettingsWindow.shared.show()
    }

    @objc private func ungroupAll() {
        groups?.dissolveAll()
    }
}
