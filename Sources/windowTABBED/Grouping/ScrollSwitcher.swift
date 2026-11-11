import AppKit

/// Turns scroll events into tab steps: −1 for the previous tab, +1 for the next one.
/// Pushing up (a mouse wheel away from you, two fingers up a trackpad) goes back, whatever
/// the Natural scrolling setting is.
final class ScrollStepper {
    /// How far a trackpad scroll goes for one tab, in points.
    private static let preciseStep: CGFloat = 24
    private var accumulated: CGFloat = 0

    func steps(for event: NSEvent) -> Int {
        // Coasting after a flick would race through the tabs.
        guard event.momentumPhase.isEmpty else { return 0 }
        if event.phase.contains(.began) { accumulated = 0 }
        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        guard abs(dy) > abs(dx) else { return 0 }
        // In the device's own direction: positive is up.
        let up = event.isDirectionInvertedFromDevice ? -dy : dy
        guard event.hasPreciseScrollingDeltas else {
            // A mouse wheel: one notch, one tab.
            return up > 0 ? -1 : up < 0 ? 1 : 0
        }
        accumulated += up
        guard abs(accumulated) >= Self.preciseStep else { return 0 }
        let step = accumulated > 0 ? -1 : 1
        accumulated = 0
        return step
    }
}

/// Settings › Scrolling › Anywhere, holding a key: scrolling over a group's window with that key
/// held switches tabs instead of scrolling the window. A global monitor can't stop the window
/// from scrolling too, so this is an event tap (allowed by the Accessibility permission).
final class ScrollTap {
    private let groups: GroupManager
    private let stepper = ScrollStepper()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    init(groups: GroupManager) {
        self.groups = groups
    }

    var isRunning: Bool { tap != nil }

    func start() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<ScrollTap>.fromOpaque(info).takeUnretainedValue()
            return me.handle(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            log.error("Couldn't watch the scroll wheel (Accessibility?)")
            return
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        self.tap = nil
        source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS switches a tap off if it ever answers too slowly: turn it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel,
              Settings.shared.scrollKey.flags.isSubset(of: NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))),
              let window = WindowDriver.serverWindow(at: event.location),
              let group = groups.group(containing: window.id), group.activeID == window.id, !group.isPaused,
              let nsEvent = NSEvent(cgEvent: event)
        else { return Unmanaged.passUnretained(event) }
        let step = stepper.steps(for: nsEvent)
        if step != 0 { groups.scrollTabs(by: step, in: group) }
        // Swallowed, steps or not: the window shouldn't scroll while the key is held.
        return nil
    }
}
