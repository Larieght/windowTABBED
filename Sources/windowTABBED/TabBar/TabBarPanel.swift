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

    /// How wide a tab is drawn.
    func width(isActive: Bool) -> CGFloat {
        guard iconOnly else { return tabWidth }
        return isActive ? TabBarPanel.iconActiveTabWidth : TabBarPanel.iconTabWidth
    }

    var onSelect: ((CGWindowID) -> Void)?
    var onClose: ((CGWindowID) -> Void)?
    /// Tab dragged sideways to a new position.
    var onMove: ((CGWindowID, Int) -> Void)?
    /// Tab dragged up or down out of the bar and let go.
    var onDragOut: ((CGWindowID) -> Void)?
}

/// The tab strip window. One per group, owned by windowTABBED, ordered directly above the
/// group's active window so other apps' windows can still cover it normally.
final class TabBarPanel: NSPanel {
    static let height: CGFloat = 30
    static let maxTabWidth: CGFloat = 184
    static let minTabWidth: CGFloat = 60
    static let tabSpacing: CGFloat = 2
    /// Distance from the window's left edge to the first tab.
    static let inset: CGFloat = 16
    /// Icon-only tabs: padding, a 16 pt icon, padding. The active one also fits its ×.
    static let iconTabWidth: CGFloat = 36
    static let iconActiveTabWidth: CGFloat = 56

    let model = TabBarModel()
    /// Where the bar was last put, so a change of tab style can lay it out again right away.
    private var lastAttach: (windowID: CGWindowID, frame: CGRect, placement: Placement)?
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
        styleSubscription = Settings.shared.$tabStyle.sink { [weak self] style in
            guard let self else { return }
            self.model.iconOnly = style == .icon
            if let last = self.lastAttach, self.isVisible {
                self.attach(above: last.windowID, frame: last.frame, placement: last.placement)
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
    func attach(above windowID: CGWindowID, frame: CGRect, placement: Placement) {
        lastAttach = (windowID, frame, placement)
        let height = Self.height
        let flipped = placement == .below
        if model.flipped != flipped { model.flipped = flipped }

        let count = CGFloat(max(model.tabs.count, 1))
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
        setFrame(ScreenGeometry.appKitRect(fromAX: barFrame), display: true)
        order(.above, relativeTo: Int(windowID))
    }
}

/// Lets the first click on an inactive bar hit the tab instead of only focusing the window.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
