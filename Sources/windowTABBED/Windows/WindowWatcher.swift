import AppKit
import ApplicationServices

enum WindowEvent {
    /// A watched window was moved or resized (by the user, its app, or us).
    case frameChanged(CGWindowID)
    case titleChanged(CGWindowID)
    /// Sent to the Dock (yellow button, Cmd-M) or back out of it.
    case minimized(CGWindowID)
    case restored(CGWindowID)
    /// A watched window closed, or its app quit. It is no longer watched.
    case closed(CGWindowID)
    /// Some window of a watched app was destroyed, but we couldn't tell which (Finder does this).
    case unidentifiedClose
    /// Some app became active or changed its focused window.
    case focusChanged
}

/// Delivers Accessibility notifications for the windows windowTABBED manages.
///
/// macOS needs one AXObserver per app (process), so observers are created lazily
/// per pid and dropped again when that app has no watched windows left.
final class WindowWatcher {
    var onEvent: ((WindowEvent) -> Void)?

    private struct Watched {
        let element: AXUIElement
        let id: CGWindowID
        let pid: pid_t
    }

    private var observers: [pid_t: AXObserver] = [:]
    private var watched: [Watched] = []

    private static let windowNotifications = [
        kAXMovedNotification,
        kAXResizedNotification,
        kAXTitleChangedNotification,
        kAXUIElementDestroyedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]

    init() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onEvent?(.focusChanged)
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            for entry in self.watched where entry.pid == app.processIdentifier {
                self.unwatch(entry.id)
                self.onEvent?(.closed(entry.id))
            }
        }
    }

    func watch(_ window: ExternalWindow) {
        guard !watched.contains(where: { $0.id == window.windowID }),
              let observer = observer(for: window.pid)
        else { return }
        for name in Self.windowNotifications {
            AXObserverAddNotification(observer, window.element, name as CFString, refcon)
        }
        watched.append(Watched(element: window.element, id: window.windowID, pid: window.pid))
    }

    func unwatch(_ id: CGWindowID) {
        guard let index = watched.firstIndex(where: { $0.id == id }) else { return }
        let entry = watched.remove(at: index)
        guard let observer = observers[entry.pid] else { return }
        for name in Self.windowNotifications {
            AXObserverRemoveNotification(observer, entry.element, name as CFString)
        }
        if !watched.contains(where: { $0.pid == entry.pid }) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observers[entry.pid] = nil
        }
    }

    private var refcon: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    private func observer(for pid: pid_t) -> AXObserver? {
        if let existing = observers[pid] { return existing }
        var created: AXObserver?
        guard AXObserverCreate(pid, axCallback, &created) == .success, let observer = created else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        // App-level: fires when you switch windows inside that app (Cmd-`, Window menu, clicks).
        AXObserverAddNotification(observer, AXUIElementCreateApplication(pid), kAXFocusedWindowChangedNotification as CFString, refcon)
        observers[pid] = observer
        return observer
    }

    fileprivate func handle(element: AXUIElement, notification: String) {
        if notification == kAXFocusedWindowChangedNotification {
            onEvent?(.focusChanged)
            return
        }
        // A destroyed element can no longer tell us its window ID, so match the element itself.
        guard let entry = watched.first(where: { CFEqual($0.element, element) }) else {
            if notification == kAXUIElementDestroyedNotification {
                onEvent?(.unidentifiedClose)
            }
            return
        }
        switch notification {
        case kAXMovedNotification, kAXResizedNotification:
            onEvent?(.frameChanged(entry.id))
        case kAXTitleChangedNotification:
            onEvent?(.titleChanged(entry.id))
        case kAXWindowMiniaturizedNotification:
            onEvent?(.minimized(entry.id))
        case kAXWindowDeminiaturizedNotification:
            onEvent?(.restored(entry.id))
        case kAXUIElementDestroyedNotification:
            unwatch(entry.id)
            onEvent?(.closed(entry.id))
        default:
            break
        }
    }
}

private let axCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let watcher = Unmanaged<WindowWatcher>.fromOpaque(refcon).takeUnretainedValue()
    watcher.handle(element: element, notification: notification as String)
}
