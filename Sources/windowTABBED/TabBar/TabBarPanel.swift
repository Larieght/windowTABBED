import AppKit
import Combine
import SwiftUI

/// What one group's tab strip shows.
final class TabBarModel: ObservableObject {
    struct Tab: Identifiable {
        let id: CGWindowID
        var title: String
        let icon: NSImage?
        let tint: NSColor
    }

    @Published var tabs: [Tab] = []
    @Published var activeID: CGWindowID?
    /// True when the bar sits under the window because there is no room above it.
    @Published var flipped = false
    @Published var tabWidth: CGFloat = TabBarPanel.maxTabWidth
    /// Settings › Tabs › Icon only: tabs show just the app icon (and × on the active one).
    @Published var iconOnly = false
    /// Settings › Tabs › Theme, already resolved for this macOS.
    @Published var theme: TabTheme = Settings.shared.tabTheme.resolved
    /// Settings › Tabs › Size.
    @Published var scale: CGFloat = TabBarPanel.scale
    /// The tab being dragged: the drag overlay draws it, so the bar's copy is hidden.
    @Published var draggingID: CGWindowID?
    /// A tab whose window was pulled out mid-drag (Window style): kept so its drag gesture
    /// lives on, but drawn with no width.
    @Published var collapsedID: CGWindowID?

    /// Space between tabs for this theme and size.
    var spacing: CGFloat { (theme.spacing * scale).rounded() }

    /// Tabs that take up room in the bar.
    var visibleCount: Int { tabs.filter { $0.id != collapsedID }.count }

    /// How wide a tab is drawn.
    func width(isActive: Bool) -> CGFloat {
        guard iconOnly else { return tabWidth }
        return isActive ? TabBarPanel.iconActiveTabWidth : TabBarPanel.iconTabWidth
    }

    var onSelect: ((CGWindowID) -> Void)?
    var onClose: ((CGWindowID) -> Void)?
    /// Tab dragged sideways to a new position.
    var onMove: ((CGWindowID, Int) -> Void)?
    /// Tab dragged up or down out of the bar and let go (debug hook).
    var onDragOut: ((CGWindowID) -> Void)?
    /// A tab drag moved, or the button went up. GroupManager reads the pointer itself.
    var onDragChanged: ((CGWindowID) -> Void)?
    var onDragEnded: ((CGWindowID) -> Void)?
}

/// The tab strip window. One per group, owned by windowTABBED, ordered directly above the
/// group's active window so other apps' windows can still cover it normally.
final class TabBarPanel: NSPanel {
    /// Settings › Tabs › Size: every measurement below grows with it.
    static var scale: CGFloat { Settings.shared.tabSize.scale }
    static var height: CGFloat { (30 * scale).rounded() }
    static var maxTabWidth: CGFloat { (184 * scale).rounded() }
    static var minTabWidth: CGFloat { (60 * scale).rounded() }
    /// Space between tabs: each theme has its own.
    static var tabSpacing: CGFloat { (Settings.shared.tabTheme.resolved.spacing * scale).rounded() }
    /// Distance from the window's left edge to the first tab.
    static let inset: CGFloat = 16
    /// Icon-only tabs: padding, a 16 pt icon, padding. The active one also fits its ×.
    static var iconTabWidth: CGFloat { (36 * scale).rounded() }
    static var iconActiveTabWidth: CGFloat { (56 * scale).rounded() }

    let model = TabBarModel()
    /// Where the bar was last put, so a change of tab style can lay it out again right away.
    private var lastAttach: (windowID: CGWindowID, frame: CGRect, placement: Placement)?
    /// Where the bar is, in AX coordinates.
    private(set) var axFrame: CGRect = .zero
    private var styleSubscription: AnyCancellable?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .normal
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // Dragging the bar's empty space does nothing (SPEC.md); move the group by its window.
        isMovable = false
        // Keep it out of Cmd-` and Mission Control's window list.
        collectionBehavior = [.managed, .ignoresCycle]
        contentView = FirstMouseHostingView(rootView: TabStripView(model: model))
        styleSubscription = Settings.shared.$tabStyle.combineLatest(Settings.shared.$tabTheme, Settings.shared.$tabSize).sink { [weak self] style, theme, size in
            guard let self else { return }
            self.model.iconOnly = style == .icon
            self.model.theme = theme.resolved
            self.model.scale = size.scale
            // @Published sends before the new value is stored, and the bar's measurements read
            // Settings: lay it out again once it has.
            DispatchQueue.main.async {
                if let last = self.lastAttach, self.isVisible {
                    self.attach(above: last.windowID, frame: last.frame, placement: last.placement)
                }
            }
        }
    }

    // Clicking a tab must never pull keyboard focus away from the app you're in.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    enum Placement {
        /// On the window's top edge (normal).
        case above
        /// Under the window, tabs upside down: no room above.
        case below
        /// Over the top of the window: no room anywhere and the window wouldn't shrink.
        case overlapping
    }

    /// Where the bar fits for a window at `frame`, or nil if it fits neither above nor below.
    static func placement(for frame: CGRect) -> Placement? {
        let visible = ScreenGeometry.visibleFrame(containing: frame)
        if frame.minY - height >= visible.minY { return .above }
        if frame.maxY + height <= visible.maxY { return .below }
        return nil
    }

    /// Positions the bar for that window and orders it just above it.
    /// `reorder: false` skips putting the bar back above the window, for repeat moves during a
    /// drag: the stacking can't change then, and every saved call keeps the bar smooth.
    func attach(above windowID: CGWindowID, frame: CGRect, placement: Placement, reorder: Bool = true) {
        lastAttach = (windowID, frame, placement)
        let height = Self.height
        let flipped = placement == .below
        if model.flipped != flipped { model.flipped = flipped }

        let count = CGFloat(max(model.visibleCount, 1))
        let available = max(frame.width - Self.inset * 2, Self.minTabWidth)
        let spacing = Self.tabSpacing * (count - 1)
        let tabWidth = min(Self.maxTabWidth, max(Self.minTabWidth, (available - spacing) / count))
        if model.tabWidth != tabWidth { model.tabWidth = tabWidth }

        let y = switch placement {
        case .above: frame.minY - height
        case .below: frame.maxY
        case .overlapping: frame.minY
        }
        let tabsWidth = model.iconOnly
            ? Self.iconTabWidth * (count - 1) + Self.iconActiveTabWidth + spacing
            : tabWidth * count + spacing
        let barFrame = CGRect(x: frame.minX + Self.inset, y: y, width: min(available, tabsWidth), height: height)
        axFrame = barFrame
        let target = ScreenGeometry.appKitRect(fromAX: barFrame)
        if target.size == self.frame.size {
            // Only moving: no relayout or redraw.
            setFrameOrigin(target.origin)
        } else {
            setFrame(target, display: true)
        }
        if reorder {
            order(.above, relativeTo: Int(windowID))
        }
    }

    /// Where a tab is drawn, in AX coordinates, at the active tab's height.
    func tabFrame(of id: CGWindowID) -> CGRect? {
        guard model.tabs.contains(where: { $0.id == id }) else { return nil }
        var x = axFrame.minX
        for tab in model.tabs where tab.id != model.collapsedID {
            if tab.id == id { break }
            x += model.width(isActive: tab.id == model.activeID) + Self.tabSpacing
        }
        let height = Self.height
        let y = model.flipped ? axFrame.minY : axFrame.maxY - height
        return CGRect(x: x, y: y, width: model.width(isActive: id == model.activeID), height: height)
    }
}

/// Lets the first click on an inactive bar hit the tab instead of only focusing the window.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
