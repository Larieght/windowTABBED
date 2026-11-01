import SwiftUI

/// The row of tabs. Design: https://www.figma.com/design/Ny6Db7XxBcnAkFWUHjaYnA
struct TabStripView: View {
    @ObservedObject var model: TabBarModel

    /// Fast with a small bounce, matching the Figma prototype's spring.
    private static let spring = Animation.interpolatingSpring(mass: 1, stiffness: 700, damping: 18)

    var body: some View {
        HStack(alignment: model.flipped ? .top : .bottom, spacing: TabBarPanel.tabSpacing) {
            ForEach(model.tabs) { tab in
                TabChip(
                    tab: tab,
                    isActive: tab.id == model.activeID,
                    flipped: model.flipped,
                    width: model.tabWidth,
                    onSelect: { model.onSelect?(tab.id) },
                    onClose: { model.onClose?(tab.id) },
                    onDragEnd: { translation in dragEnded(tab.id, translation) }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.flipped ? .topLeading : .bottomLeading)
        .animation(Self.spring, value: model.activeID)
        .animation(Self.spring, value: model.tabs.map(\.id))
    }

    /// Out of the bar (up or down) detaches the window; sideways reorders.
    private func dragEnded(_ id: CGWindowID, _ translation: CGSize) {
        if abs(translation.height) > TabChip.dragOutDistance {
            model.onDragOut?(id)
            return
        }
        guard let from = model.tabs.firstIndex(where: { $0.id == id }) else { return }
        let step = model.tabWidth + TabBarPanel.tabSpacing
        let to = from + Int((translation.width / step).rounded())
        if to != from {
            model.onMove?(id, to)
        }
    }
}

/// One tab: app icon + short title. Active = taller, full tint, gloss and ×. Background = short, dim, grey.
private struct TabChip: View {
    let tab: TabBarModel.Tab
    let isActive: Bool
    let flipped: Bool
    let width: CGFloat
    let onSelect: () -> Void
    let onClose: () -> Void
    let onDragEnd: (CGSize) -> Void

    /// How far up or down a tab has to be pulled to come out of the bar.
    static let dragOutDistance: CGFloat = 24

    // @GestureState rather than @State: it resets on release, and @State needs a compiler
    // plugin that only ships with full Xcode, not the command-line tools.
    @GestureState private var dragOffset: CGSize = .zero

    private static let activeHeight: CGFloat = 30
    private static let inactiveHeight: CGFloat = 26
    private static let radius: CGFloat = 8
    /// Background tabs keep only a hint of their app's color.
    private static let neutral = NSColor(srgbRed: 0.173, green: 0.180, blue: 0.208, alpha: 1)

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: tab.icon ?? NSImage())
                .resizable()
                .frame(width: 16, height: 16)
                .opacity(isActive ? 1 : 0.5)
            Text(tab.title.isEmpty ? "Untitled" : tab.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(isActive ? 1 : 0.45))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isActive {
                Button(action: onClose) {
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
        .padding(.trailing, 8)
        .frame(width: width, height: isActive ? Self.activeHeight : Self.inactiveHeight)
        .background(background)
        .clipShape(shape)
        .contentShape(shape)
        // Follows the pointer sideways; fades once it's far enough up or down to come out.
        .offset(x: dragOffset.width)
        .opacity(abs(dragOffset.height) > Self.dragOutDistance ? 0.5 : 1)
        .zIndex(dragOffset == .zero ? 0 : 1)
        .onTapGesture(perform: onSelect)
        .gesture(
            DragGesture(minimumDistance: 4)
                .updating($dragOffset) { value, offset, _ in offset = value.translation }
                .onEnded { onDragEnd($0.translation) })
    }

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
