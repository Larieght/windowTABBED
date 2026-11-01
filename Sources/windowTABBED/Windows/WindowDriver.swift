import AppKit
import ApplicationServices

// Private but long-stable: maps an Accessibility window to its window-server ID.
// Used by Rectangle, AltTab and yabai. We need the ID to order the tab bar above a window.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// A window that belongs to another app, driven through the Accessibility API.
///
/// Coordinates are global screen coordinates with the origin at the top-left of the
/// main display (the same space as `CGWindowListCopyWindowInfo`), not AppKit's bottom-left.
struct ExternalWindow: Hashable, CustomStringConvertible {
    let element: AXUIElement
    let pid: pid_t
    let windowID: CGWindowID

    init?(element: AXUIElement) {
        var pid: pid_t = 0
        var windowID: CGWindowID = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              _AXUIElementGetWindow(element, &windowID) == .success,
              windowID != 0
        else { return nil }
        // A frozen app would otherwise block us for the default 6 seconds.
        AXUIElementSetMessagingTimeout(element, 1)
        self.element = element
        self.pid = pid
        self.windowID = windowID
    }

    static func == (lhs: ExternalWindow, rhs: ExternalWindow) -> Bool { lhs.windowID == rhs.windowID }
    func hash(into hasher: inout Hasher) { hasher.combine(windowID) }

    var description: String { "#\(windowID) \(appName) — \(title)" }

    // MARK: - Reading

    var app: NSRunningApplication? { NSRunningApplication(processIdentifier: pid) }
    var appName: String { app?.localizedName ?? "pid \(pid)" }
    var appIcon: NSImage? { app?.icon }

    var title: String { attribute(kAXTitleAttribute) ?? "" }

    var frame: CGRect? {
        guard let position: CGPoint = axValue(kAXPositionAttribute, type: .cgPoint),
              let size: CGSize = axValue(kAXSizeAttribute, type: .cgSize)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    var isMinimized: Bool { attribute(kAXMinimizedAttribute) ?? false }
    var isFullScreen: Bool { attribute("AXFullScreen") ?? false }

    /// Ordinary document/app windows, as opposed to panels, sheets and popovers.
    var isStandard: Bool { (attribute(kAXSubroleAttribute) as String?) == kAXStandardWindowSubrole }

    // MARK: - Driving

    /// Moves and resizes the window. Returns the frame the app actually accepted,
    /// which can differ when the app enforces a minimum or maximum size.
    @discardableResult
    func setFrame(_ target: CGRect) -> CGRect? {
        // Size, position, size: the first resize keeps a big window from being clamped
        // by the screen edge during the move, the second one fixes the size after it.
        setAXValue(kAXSizeAttribute, target.size, type: .cgSize)
        setAXValue(kAXPositionAttribute, target.origin, type: .cgPoint)
        setAXValue(kAXSizeAttribute, target.size, type: .cgSize)
        return frame
    }

    func setPosition(_ origin: CGPoint) {
        setAXValue(kAXPositionAttribute, origin, type: .cgPoint)
    }

    /// Brings the window in front of its app's other windows and makes that app active.
    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        // Since macOS 14 a background app's activate() request can be ignored, e.g. after a click
        // on our non-activating tab bar. Setting the app frontmost through Accessibility still works.
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app?.activate()
    }

    func setMinimized(_ minimized: Bool) {
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, minimized as CFBoolean)
    }

    // MARK: - AX plumbing

    private func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private func axValue<T>(_ name: String, type: AXValueType) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        return AXValueGetValue(value as! AXValue, type, pointer) ? pointer.pointee : nil
    }

    private func setAXValue<T>(_ name: String, _ value: T, type: AXValueType) {
        guard let axValue = withUnsafePointer(to: value, { AXValueCreate(type, $0) }) else { return }
        AXUIElementSetAttributeValue(element, name as CFString, axValue)
    }
}

/// Finding windows.
enum WindowDriver {
    /// The window you are working in right now.
    static func focusedWindow() -> ExternalWindow? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value
        else { return nil }
        return ExternalWindow(element: value as! AXUIElement)
    }

    /// Standard windows of one app, front to back.
    static func windows(of pid: pid_t) -> [ExternalWindow] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement]
        else { return [] }
        return elements.compactMap(ExternalWindow.init(element:)).filter(\.isStandard)
    }

    /// Standard windows of every app that shows in the Dock, skipping windowTABBED itself
    /// and floating windows (always-on-top panels and overlays), which can't be tabs.
    static func allWindows() -> [ExternalWindow] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let floating = Set(windowInfo(onScreenOnly: false).filter { !$0.isNormalLayer }.map(\.id))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID }
            .flatMap { windows(of: $0.processIdentifier) }
            .filter { !floating.contains($0.windowID) }
    }

    /// Every window the window server knows about, on screen or not (minimized, other Spaces).
    static func existingWindowIDs() -> Set<CGWindowID> {
        Set(windowInfo(onScreenOnly: false).map(\.id))
    }

    /// IDs of on-screen, normal-layer windows, front to back.
    static func normalWindowOrder() -> [CGWindowID] {
        windowInfo(onScreenOnly: true).filter(\.isNormalLayer).map(\.id)
    }

    private struct WindowInfo {
        let id: CGWindowID
        let layer: Int
        var isNormalLayer: Bool { layer == 0 }
    }

    private static func windowInfo(onScreenOnly: Bool) -> [WindowInfo] {
        let options: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll]
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { entry in
            guard let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let layer = entry[kCGWindowLayer as String] as? Int
            else { return nil }
            return WindowInfo(id: id, layer: layer)
        }
    }
}
