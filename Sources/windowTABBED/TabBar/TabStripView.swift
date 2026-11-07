import SwiftUI

/// The row of tabs. Design: https://www.figma.com/design/Ny6Db7XxBcnAkFWUHjaYnA
struct TabStripView: View {
    @ObservedObject var model: TabBarModel

    /// Fast with a small bounce, matching the Figma prototype's spring.
    static let spring = Animation.interpolatingSpring(mass: 1, stiffness: 700, damping: 18)

    var body: some View {
        HStack(alignment: model.flipped ? .top : .bottom, spacing: TabBarPanel.tabSpacing) {
            ForEach(model.tabs) { tab in
                let isActive = tab.id == model.activeID
                let collapsed = tab.id == model.collapsedID
                TabChip(
                    tab: tab,
                    isActive: isActive,
                    flipped: model.flipped,
                    iconOnly: model.iconOnly,
                    width: collapsed ? 0 : model.width(isActive: isActive),
                    hidden: tab.id == model.draggingID,
                    onSelect: { model.onSelect?(tab.id) },
                    onClose: { model.onClose?(tab.id) },
                    onDragChanged: { model.onDragChanged?(tab.id) },
                    onDragEnded: { model.onDragEnded?(tab.id) }
                )
                // A tab whose window was pulled out of the group keeps its (empty) place, so
                // its drag gesture lives on, but takes no room.
                .padding(.trailing, collapsed ? -TabBarPanel.tabSpacing : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.flipped ? .topLeading : .bottomLeading)
        .animation(Self.spring, value: model.activeID)
        .animation(Self.spring, value: model.tabs.map(\.id))
        .animation(Self.spring, value: model.iconOnly)
        .animation(Self.spring, value: model.collapsedID)
    }
}

/// One tab in the bar: the drawing (TabFace) plus clicks and drags. While it's being dragged,
/// the bar's copy is hidden and the drag overlay draws it under the pointer (TearOff.swift).
private struct TabChip: View {
    let tab: TabBarModel.Tab
    let isActive: Bool
    let flipped: Bool
    let iconOnly: Bool
    let width: CGFloat
    let hidden: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onDragChanged: () -> Void
    let onDragEnded: () -> Void

    var body: some View {
        TabFace(tab: tab, isActive: isActive, flipped: flipped, iconOnly: iconOnly, width: width, onClose: onClose)
            .opacity(hidden ? 0 : 1)
            .onTapGesture(perform: onSelect)
            .gesture(
                // Global coordinates, and the pointer position is read from AppKit anyway: the
                // tab can shrink to nothing mid-drag, which would shift a local coordinate space.
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { _ in onDragChanged() }
                    .onEnded { _ in onDragEnded() })
    }
}

/// How a tab looks: app icon + short title (or just the icon). Active = taller, full tint, gloss
/// and ×. Background = short, dim, grey. Used by the bar and by the drag overlay.
struct TabFace: View {
    let tab: TabBarModel.Tab
    let isActive: Bool
    let flipped: Bool
    let iconOnly: Bool
    let width: CGFloat
    var onClose: (() -> Void)?

    static let activeHeight: CGFloat = 30
    static let inactiveHeight: CGFloat = 26
    private static let radius: CGFloat = 8
    /// Background tabs keep only a hint of their app's color.
    private static let neutral = NSColor(srgbRed: 0.173, green: 0.180, blue: 0.208, alpha: 1)

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: tab.icon ?? NSImage())
                .resizable()
                .frame(width: 16, height: 16)
                // The tab takes its color from this icon, so the icon's edge needs a little
                // shadow to stand out from it (an all-orange icon on an orange tab vanished).
                .shadow(color: .black.opacity(isActive ? 0.55 : 0.35), radius: 1, y: 0.5)
                .opacity(isActive ? 1 : 0.5)
            if !iconOnly {
                Text(title)
                    // Weight marks the active tab as well as color: semibold, the others regular.
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(isActive ? 1 : 0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if isActive {
                Button(action: { onClose?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove from group")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, iconOnly && !isActive ? 10 : 8)
        .frame(width: width, height: isActive ? Self.activeHeight : Self.inactiveHeight)
        .background(background)
        .clipShape(shape)
        .contentShape(shape)
        .help(iconOnly ? title : "")
    }

    private var title: String { tab.title.isEmpty ? "Untitled" : tab.title }

    private var shape: UnevenRoundedRectangle {
        let r = Self.radius
        return flipped
            ? UnevenRoundedRectangle(bottomLeadingRadius: r, bottomTrailingRadius: r, style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: r, topTrailingRadius: r, style: .continuous)
    }

    /// The edge facing away from the window: where the light hits.
    private var outer: UnitPoint { flipped ? .bottom : .top }
    private var inner: UnitPoint { flipped ? .top : .bottom }

    @ViewBuilder private var background: some View {
        let tint = tab.tint.usingColorSpace(.sRGB) ?? tab.tint
        ZStack {
            if isActive {
                shape.fill(LinearGradient(
                    colors: [Color(nsColor: mix(tint, .white, 0.28)), Color(nsColor: mix(tint, .black, 0.1))],
                    startPoint: outer, endPoint: inner))
                // Soft Aqua gloss over the outer half.
                shape.fill(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0)], startPoint: outer, endPoint: .center))
            } else {
                let base = mix(tint, Self.neutral, 0.8)
                shape.fill(LinearGradient(
                    colors: [Color(nsColor: mix(base, .white, 0.04)), Color(nsColor: mix(base, .black, 0.15))],
                    startPoint: outer, endPoint: inner))
                    .opacity(0.92)
            }
            // 1 pt highlight along the outer edge.
            Rectangle()
                .fill(.white.opacity(isActive ? 0.38 : 0.06))
                .frame(height: 1)
                .padding(.horizontal, Self.radius / 2)
                .frame(maxHeight: .infinity, alignment: flipped ? .bottom : .top)
            shape.strokeBorder(.black.opacity(isActive ? 0.45 : 0.3), lineWidth: 1)
        }
    }

    private func mix(_ color: NSColor, _ other: NSColor, _ fraction: CGFloat) -> NSColor {
        color.blended(withFraction: fraction, of: other) ?? color
    }
}
