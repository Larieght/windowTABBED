import AppKit
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

    let model = TabBarModel()

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
    }

    // Clicking a tab must never pull keyboard focus away from the app you're in.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Places the bar on the window's top edge, or under it when there's no room above,
    /// and orders it just above that window.
    func attach(above windowID: CGWindowID, frame: CGRect) {
        let visible = ScreenGeometry.visibleFrame(containing: frame)
        let height = Self.height
        let roomAbove = frame.minY - height >= visible.minY
        let roomBelow = frame.maxY + height <= visible.maxY
        // TODO: no room either way → shrink the window by `height` (SPEC.md, later step).
        let flipped = !roomAbove && roomBelow
        if model.flipped != flipped { model.flipped = flipped }

        let count = CGFloat(max(model.tabs.count, 1))
        let available = max(frame.width - Self.inset * 2, Self.minTabWidth)
        let spacing = Self.tabSpacing * (count - 1)
        let tabWidth = min(Self.maxTabWidth, max(Self.minTabWidth, (available - spacing) / count))
        if model.tabWidth != tabWidth { model.tabWidth = tabWidth }

        let barFrame = CGRect(
            x: frame.minX + Self.inset,
            y: flipped ? frame.maxY : frame.minY - height,
            width: min(available, tabWidth * count + spacing),
            height: height
        )
        setFrame(ScreenGeometry.appKitRect(fromAX: barFrame), display: true)
        order(.above, relativeTo: Int(windowID))
    }
}

/// Lets the first click on an inactive bar hit the tab instead of only focusing the window.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
