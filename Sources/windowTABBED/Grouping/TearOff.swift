import AppKit
import SwiftUI

/// Pulling a tab out of its bar.
///
/// The bar is a 30 pt window, so a tab can't leave it on its own. Once a drag starts, the bar's
/// copy hides and `DragOverlay`, a click-through window over the display, draws the tab under the
/// pointer instead. Up to `threshold` away from the bar it stretches with resistance (rubber band),
/// past it it comes loose and follows the pointer. What happens then depends on
/// Settings › `tearOffStyle`:
///
/// - `.window`: the real window leaves the group right away and follows the pointer, with the tab
///   on top of it. Bring it back over the bar to put it back.
/// - `.outline`: a dashed outline shows where the window will land; it moves when you let go.
/// - `.tab`: just the tab; the window moves when you let go.
final class TearOffSession {
    let id: CGWindowID
    let window: ExternalWindow
    weak var group: WindowGroup?
    let style: TearOffStyle
    /// Pointer at the start of the drag, and where the tab was then (AX coordinates).
    let startMouse: CGPoint
    let startChip: CGRect
    /// The bar when the drag started: dropping back anywhere over it puts the tab back, even
    /// once the bar has closed the gap.
    let startBar: CGRect
    /// Where in the tab you grabbed it, so it stays under the pointer at the same spot.
    var grab: CGPoint { CGPoint(x: startMouse.x - startChip.minX, y: startMouse.y - startChip.minY) }
    /// The tab's place in the bar. It changes as you drag it sideways: the other tabs make room.
    var index: Int
    let wasActive: Bool

    /// Past the threshold: the tab is loose.
    var isLoose = false
    /// Window style: the window is out of the group right now.
    var isDetached = false
    /// Let go without coming loose: the tab glides into its slot, then the bar shows it again.
    var isSettling = false
    /// Where the tab was drawn last, and a short glide from there when it comes loose or snaps back.
    var chip: CGRect
    var glideFrom: CGPoint?
    var glideStart = Date()
    var glideTimer: Timer?

    init(id: CGWindowID, window: ExternalWindow, group: WindowGroup, style: TearOffStyle,
         startMouse: CGPoint, startChip: CGRect, startBar: CGRect, originalIndex: Int) {
        self.id = id
        self.window = window
        self.group = group
        self.style = style
        self.startMouse = startMouse
        self.startChip = startChip
        self.startBar = startBar
        index = originalIndex
        wasActive = group.activeID == id
        chip = startChip
    }
}

extension GroupManager {
    /// How far up or down a tab has to be pulled to come loose.
    static let tearThreshold: CGFloat = 24
    /// How long a loose tab takes to glide under the pointer.
    private static let glideDuration: TimeInterval = 0.14

    func tabDragChanged(_ id: CGWindowID, in group: WindowGroup) {
        let mouse = ScreenGeometry.mouseLocation
        if let settling = tearOff, settling.isSettling {
            finishSettling(settling)
        }
        if tearOff == nil {
            guard let index = group.windows.firstIndex(where: { $0.windowID == id }),
                  let chip = group.bar.tabFrame(of: id)
            else { return }
            tearOff = TearOffSession(id: id, window: group.windows[index], group: group,
                                     style: Settings.shared.tearOffStyle, startMouse: mouse,
                                     startChip: chip, startBar: group.bar.axFrame, originalIndex: index)
            group.bar.model.draggingID = id
        }
        guard let session = tearOff, session.id == id else { return }

        let dy = mouse.y - session.startMouse.y
        if !session.isLoose, abs(dy) > Self.tearThreshold {
            comeLoose(session, in: group)
        } else if session.isLoose, isOverBar(mouse, session: session, of: group) {
            snapBack(session, in: group)
        }
        updateTearOff()
        if !session.isLoose {
            reorderLive(session, in: group)
        }
    }

    /// The other tabs slide aside as the dragged one passes their middle, like browser tabs.
    private func reorderLive(_ session: TearOffSession, in group: WindowGroup) {
        let model = group.bar.model
        let step = model.width(isActive: false) + model.spacing
        let offset = session.chip.midX - group.bar.axFrame.minX
        let target = min(max(Int(offset / step), 0), group.windows.count - 1)
        guard target != session.index else { return }
        session.index = target
        move(session.id, to: target, in: group)
    }

    func tabDragEnded(_ id: CGWindowID, in group: WindowGroup) {
        guard let session = tearOff, session.id == id, !session.isSettling else { return }

        guard session.isLoose else {
            // Never came loose: it's already in its new place, so it only glides into the slot.
            session.isSettling = true
            startGlide(session)
            return
        }

        session.glideTimer?.invalidate()
        tearOff = nil
        overlay.hide()
        group.bar.model.draggingID = nil
        group.bar.model.collapsedID = nil

        let landing = landingFrame(for: session, in: group)
        switch session.style {
        case .window:
            // Already out of the group and in place.
            mover.move(session.window, to: landing.origin)
            if group.windows.count <= 1 {
                dissolve(group)
            } else {
                refreshBar(of: group)
            }
            log.notice("Tore \(session.window.description, privacy: .public) out of its group")
        case .outline, .tab:
            dragOut(id, from: group, to: landing)
            log.notice("Dragged \(session.window.description, privacy: .public) out of its group")
        }
    }

    // MARK: - States

    private func comeLoose(_ session: TearOffSession, in group: WindowGroup) {
        session.isLoose = true
        startGlide(session)
        guard session.style == .window else { return }
        detachForTearOff(session, from: group)
    }

    private func snapBack(_ session: TearOffSession, in group: WindowGroup) {
        session.isLoose = false
        startGlide(session)
        guard session.isDetached else { return }
        // Back in at its old place, and the active tab again.
        session.isDetached = false
        group.windows.insert(session.window, at: min(session.index, group.windows.count))
        watcher.watch(session.window)
        group.bar.model.collapsedID = nil
        activate(session.id, in: group)
    }

    /// Window style: the window leaves the group now, so you carry the real thing. The group keeps
    /// its bar (and this tab, collapsed) until you let go, even if only one window is left.
    private func detachForTearOff(_ session: TearOffSession, from group: WindowGroup) {
        guard let index = group.windows.firstIndex(where: { $0.windowID == session.id }) else { return }
        group.windows.remove(at: index)
        watcher.unwatch(session.id)
        session.isDetached = true
        if group.activeID == session.id, !group.windows.isEmpty {
            let next = group.windows[min(index, group.windows.count - 1)]
            group.activeID = next.windowID
            next.setFrame(group.frame)
            next.raise()
        }
        group.bar.model.collapsedID = session.id
        refreshBar(of: group)
        // A parked tab still has its old size.
        session.window.setFrame(landingFrame(for: session, in: group))
        session.window.raise()
    }

    /// Within the bar's height (plus some slack), and not far past either end.
    private func isOverBar(_ point: CGPoint, session: TearOffSession, of group: WindowGroup) -> Bool {
        group.bar.axFrame.union(session.startBar)
            .insetBy(dx: -40, dy: -Self.tearThreshold * 0.6).contains(point)
    }

    // MARK: - Drawing

    func updateTearOff() {
        guard let session = tearOff, let group = session.group else { return }
        let mouse = ScreenGeometry.mouseLocation
        var target: CGPoint
        if session.isSettling {
            target = group.bar.tabFrame(of: session.id)?.origin ?? session.chip.origin
        } else if session.isLoose {
            target = CGPoint(x: mouse.x - session.grab.x, y: mouse.y - session.grab.y)
        } else {
            let dx = mouse.x - session.startMouse.x
            let dy = mouse.y - session.startMouse.y
            target = CGPoint(x: session.startChip.minX + dx, y: session.startChip.minY + Self.rubberBand(dy))
        }
        if let from = session.glideFrom {
            let t = min(Date().timeIntervalSince(session.glideStart) / Self.glideDuration, 1)
            let eased = 1 - pow(1 - t, 3)
            target = CGPoint(x: from.x + (target.x - from.x) * eased, y: from.y + (target.y - from.y) * eased)
            if t >= 1 {
                session.glideFrom = nil
                session.glideTimer?.invalidate()
                session.glideTimer = nil
                if session.isSettling {
                    finishSettling(session)
                    return
                }
            }
        }
        session.chip.origin = target
        // Icon-only tabs are wider when active (room for ×).
        let isActive = !session.isSettling && session.isLoose || group.activeID == session.id
        session.chip.size.width = group.bar.model.width(isActive: isActive)

        let lift: CGFloat = session.isSettling ? 0
            : session.isLoose ? 1 : min(abs(mouse.y - session.startMouse.y) / Self.tearThreshold, 1)
        let landing = landingFrame(for: session, in: group)
        overlay.show(
            tab: group.bar.model.tabs.first { $0.id == session.id },
            isActive: isActive,
            chip: session.chip,
            outline: session.isLoose && session.style == .outline ? landing : nil,
            lift: lift,
            flipped: group.bar.model.flipped && !session.isLoose,
            iconOnly: group.bar.model.iconOnly,
            theme: group.bar.model.theme,
            scale: group.bar.model.scale)
        if session.isDetached {
            mover.move(session.window, to: landing.origin)
        }
    }

    /// The tab is in its slot: the bar draws it again.
    private func finishSettling(_ session: TearOffSession) {
        session.glideTimer?.invalidate()
        if tearOff === session { tearOff = nil }
        overlay.hide()
        session.group?.bar.model.draggingID = nil
    }

    /// Where the window goes if you let go now: under the loose tab, as if it were its first tab.
    private func landingFrame(for session: TearOffSession, in group: WindowGroup) -> CGRect {
        CGRect(x: session.chip.minX - TabBarPanel.inset, y: session.chip.maxY,
               width: group.frame.width, height: group.frame.height)
    }

    /// Pulling up to the threshold moves the tab less and less, so it feels held by the bar.
    private static func rubberBand(_ offset: CGFloat) -> CGFloat {
        let limit = tearThreshold * 0.55
        return limit * tanh(offset / tearThreshold) * (offset == 0 ? 0 : 1)
    }

    /// Glides the tab from where it is to where it should be, even while the pointer holds still.
    private func startGlide(_ session: TearOffSession) {
        session.glideFrom = session.chip.origin
        session.glideStart = Date()
        session.glideTimer?.invalidate()
        session.glideTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            self?.updateTearOff()
        }
    }
}

// MARK: - Overlay

final class DragOverlayModel: ObservableObject {
    @Published var tab: TabBarModel.Tab?
    @Published var isActive = true
    /// In the overlay's own coordinates (top-left origin).
    @Published var chip: CGRect = .zero
    @Published var outline: CGRect?
    /// 0 in the bar, 1 once loose: shadow and a slight lift.
    @Published var lift: CGFloat = 0
    @Published var flipped = false
    @Published var iconOnly = false
    @Published var theme: TabTheme = .aqua
    @Published var scale: CGFloat = 1
}

/// A click-through window over the display, above other windows, that draws a dragged tab.
final class DragOverlay: NSPanel {
    let model = DragOverlayModel()
    private var screenFrame: CGRect = .null

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: DragOverlayView(model: model))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// All rects in AX coordinates.
    func show(tab: TabBarModel.Tab?, isActive: Bool, chip: CGRect, outline: CGRect?, lift: CGFloat, flipped: Bool, iconOnly: Bool, theme: TabTheme, scale: CGFloat) {
        let screen = ScreenGeometry.screenFrame(containing: chip)
        if screen != screenFrame {
            screenFrame = screen
            setFrame(ScreenGeometry.appKitRect(fromAX: screen), display: false)
        }
        let local = { (rect: CGRect) in rect.offsetBy(dx: -screen.minX, dy: -screen.minY) }
        if model.tab?.id != tab?.id || model.tab?.title != tab?.title { model.tab = tab }
        model.chip = local(chip)
        model.outline = outline.map(local)
        if model.lift != lift { model.lift = lift }
        if model.isActive != isActive { model.isActive = isActive }
        if model.flipped != flipped { model.flipped = flipped }
        if model.iconOnly != iconOnly { model.iconOnly = iconOnly }
        if model.theme != theme { model.theme = theme }
        if model.scale != scale { model.scale = scale }
        if !isVisible { orderFrontRegardless() }
    }

    func hide() {
        orderOut(nil)
        model.tab = nil
        model.outline = nil
    }
}

private struct DragOverlayView: View {
    @ObservedObject var model: DragOverlayModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let outline = model.outline {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
                    .frame(width: outline.width, height: outline.height)
                    .offset(x: outline.minX, y: outline.minY)
            }
            if let tab = model.tab {
                // Bottom-aligned in the chip's frame like in the bar (top when flipped), since a
                // background tab is shorter than the active one.
                TabFace(tab: tab, isActive: model.isActive, flipped: model.flipped, iconOnly: model.iconOnly, width: model.chip.width, theme: model.theme, scale: model.scale)
                    .frame(height: model.chip.height, alignment: model.flipped ? .top : .bottom)
                    .shadow(color: .black.opacity(0.35 * model.lift), radius: 8 * model.lift, y: 3 * model.lift)
                    .scaleEffect(1 + 0.04 * model.lift)
                    .offset(x: model.chip.minX, y: model.chip.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Moving another app's window

/// Moves a window through Accessibility off the main thread, always to the latest position:
/// the other app answers each move in its own time, and the drag shouldn't wait for it.
final class WindowMover {
    private let queue = DispatchQueue(label: "windowTABBED.mover", qos: .userInteractive)
    private let lock = NSLock()
    private var pending: (ExternalWindow, CGPoint)?
    private var busy = false

    func move(_ window: ExternalWindow, to origin: CGPoint) {
        lock.lock()
        pending = (window, origin)
        let start = !busy
        busy = true
        lock.unlock()
        guard start else { return }
        queue.async { [weak self] in self?.drain() }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let (window, origin) = pending else {
                busy = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            window.setPosition(origin)
        }
    }
}
