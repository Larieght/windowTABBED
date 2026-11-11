import SwiftUI

/// The row of tabs. Design: https://www.figma.com/design/Ny6Db7XxBcnAkFWUHjaYnA
struct TabStripView: View {
    @ObservedObject var model: TabBarModel

    /// Fast with a small bounce, matching the Figma prototype's spring.
    static let spring = Animation.interpolatingSpring(mass: 1, stiffness: 700, damping: 18)

    var body: some View {
        HStack(alignment: model.flipped ? .top : .bottom, spacing: model.spacing) {
            ForEach(model.slots) { slot in
                let tab = slot.front
                let isActive = tab.id == model.activeID
                let collapsed = tab.id == model.collapsedID
                ZStack(alignment: model.flipped ? .top : .bottom) {
                    // Cards behind the front one, deepest first so nearer ones cover them. While
                    // the front one is pulled out, the nearest takes its place.
                    ForEach(Array(slot.behind.prefix(TabBarModel.maxBehind).enumerated()).reversed(), id: \.element.id) { depth, card in
                        peekingCard(card, depth: collapsed ? depth - 1 : depth,
                                    width: model.width(isActive: isActive && !collapsed), frontActive: isActive && !collapsed)
                    }
                TabChip(
                    tab: tab,
                    isActive: isActive,
                    flipped: model.flipped,
                    iconOnly: model.iconOnly,
                    theme: model.theme,
                    scale: model.scale,
                    width: collapsed ? 0 : model.width(isActive: isActive),
                    hidden: tab.id == model.draggingID,
                    onSelect: { model.onSelect?(tab.id) },
                    onClose: { model.onClose?(tab.id) },
                    onDragChanged: { model.onDragChanged?(tab.id) },
                    onDragEnded: { model.onDragEnded?(tab.id) }
                )
                }
                // A tab whose window was pulled out of the group keeps its (empty) place, so
                // its drag gesture lives on, but takes no room.
                .padding(.trailing, slot.isGone(model.collapsedID) ? -model.spacing : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.flipped ? .topLeading : .bottomLeading)
        .animation(Self.spring, value: model.activeID)
        .animation(Self.spring, value: model.tabs.map(\.id))
        .animation(Self.spring, value: model.iconOnly)
        .animation(Self.spring, value: model.collapsedID)
        .animation(Self.spring, value: model.theme)
        .animation(Self.spring, value: model.scale)
        .animation(Self.spring, value: model.stacked)
    }

    /// A tab peeking out of a pile, its top strip (icon and title) showing above the cards in
    /// front of it. Clicking it brings that window to the front.
    private func peekingCard(_ card: TabBarModel.Tab, depth: Int, width: CGFloat, frontActive: Bool) -> some View {
        let scale = model.scale
        let front = (model.theme.height(active: frontActive) * scale).rounded()
        let own = (model.theme.height(active: false) * scale).rounded()
        // Its outer edge sits one peek further out than the card in front of it. Depth −1: in the
        // front's place.
        let shift = depth < 0 ? 0 : front - own + TabBarModel.peek * CGFloat(depth + 1)
        return TabFace(tab: card, isActive: false, flipped: model.flipped, iconOnly: model.iconOnly, width: width,
                       theme: model.theme, scale: scale, peeking: depth >= 0)
            .offset(y: model.flipped ? shift : -shift)
            .onTapGesture { model.onSelect?(card.id) }
    }
}

/// One tab in the bar: the drawing (TabFace) plus clicks and drags. While it's being dragged,
/// the bar's copy is hidden and the drag overlay draws it under the pointer (TearOff.swift).
private struct TabChip: View {
    let tab: TabBarModel.Tab
    let isActive: Bool
    let flipped: Bool
    let iconOnly: Bool
    let theme: TabTheme
    let scale: CGFloat
    let width: CGFloat
    let hidden: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onDragChanged: () -> Void
    let onDragEnded: () -> Void

    var body: some View {
        TabFace(tab: tab, isActive: isActive, flipped: flipped, iconOnly: iconOnly, width: width, theme: theme, scale: scale, onClose: onClose)
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

/// How a tab looks: app icon + short title (or just the icon), drawn in the chosen theme
/// (TabTheme). The active tab is the prominent one and carries ×. Used by the bar and by the
/// drag overlay.
struct TabFace: View {
    let tab: TabBarModel.Tab
    let isActive: Bool
    let flipped: Bool
    let iconOnly: Bool
    let width: CGFloat
    var theme: TabTheme = Settings.shared.tabTheme.resolved
    /// Settings › Tabs › Size: every measurement is multiplied by it.
    var scale: CGFloat = TabBarPanel.scale
    /// Behind another tab in a pile: only its outer strip shows, so the icon and title sit there.
    var peeking = false
    var onClose: (() -> Void)?

    /// Background tabs keep only a hint of their app's color (Aqua).
    private static let neutral = NSColor(srgbRed: 0.173, green: 0.180, blue: 0.208, alpha: 1)
    private static let silver = Color(white: 0.75)

    var body: some View {
        HStack(spacing: 7 * scale) {
            Image(nsImage: tab.icon ?? NSImage())
                .resizable()
                .frame(width: 16 * scale, height: 16 * scale)
                // On the tinted themes the tab takes its color from this icon, so the icon's edge
                // needs a little shadow to stand out (an all-orange icon on an orange tab vanished).
                .shadow(color: .black.opacity(iconShadow), radius: 1, y: 0.5)
                .opacity(isActive ? 1 : iconOpacity)
            if !iconOnly {
                Text(title)
                    // Weight marks the active tab as well as color.
                    .font(.system(size: theme.fontSize * scale, weight: weight))
                    .foregroundStyle(textColor)
                    // Metallic: letters pressed into the steel, lit from above.
                    .shadow(color: .white.opacity(theme == .metallic ? 0.55 : 0), radius: 0, y: 1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if isActive {
                Button(action: { onClose?() }) { closeGlyph }
                    .buttonStyle(.plain)
                    .help("Remove from group")
            }
        }
        .padding(.leading, (theme == .pill ? 8 : 10) * scale)
        .padding(.trailing, (iconOnly && !isActive ? 10 : theme == .retro ? 3 : 8) * scale)
        .padding(flipped ? .bottom : .top, peeking ? max(0, (TabBarModel.peek - 16 * scale) / 2) : 0)
        .frame(width: width, height: (theme.height(active: isActive) * scale).rounded(),
               alignment: peeking ? (flipped ? .bottom : .top) : .center)
        .background(background)
        .clipShape(shape)
        .contentShape(shape)
        .padding(flipped ? .top : .bottom, (theme.float * scale).rounded())
        .help(iconOnly ? title : "")
    }

    private var title: String { tab.title.isEmpty ? "Untitled" : tab.title }

    // MARK: - Per theme

    private var radius: CGFloat {
        let base: CGFloat = switch theme {
        case .aqua: 8
        case .glass: 14
        case .flat: 6
        case .pill: 12
        case .metallic: 3
        case .retro: 0
        }
        return base * scale
    }

    private var shape: UnevenRoundedRectangle {
        let r = radius
        if theme == .pill {
            return UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
        }
        return flipped
            ? UnevenRoundedRectangle(bottomLeadingRadius: r, bottomTrailingRadius: r, style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: r, topTrailingRadius: r, style: .continuous)
    }

    private var weight: Font.Weight {
        switch theme {
        case .metallic: isActive ? .heavy : .semibold
        case .retro: isActive ? .bold : .regular
        case .glass, .pill: isActive ? .semibold : .medium
        case .aqua, .flat: isActive ? .semibold : .regular
        }
    }

    private var textColor: Color {
        switch theme {
        case .aqua: .white.opacity(isActive ? 1 : 0.45)
        case .glass: .white.opacity(isActive ? 1 : 0.7)
        case .flat: isActive ? Color(white: 0.95) : .white.opacity(0.5)
        case .pill: .white.opacity(isActive ? 1 : 0.75)
        case .metallic: isActive ? Color(white: 0.08) : Color(white: 0.2)
        case .retro: isActive ? .white : .black
        }
    }

    private var iconOpacity: Double {
        switch theme {
        case .aqua: 0.5
        case .glass: 0.75
        case .flat: 0.55
        case .pill: 0.8
        case .metallic: 0.8
        case .retro: 1
        }
    }

    private var iconShadow: Double {
        switch theme {
        case .metallic, .retro: 0
        default: isActive ? 0.55 : 0.35
        }
    }

    @ViewBuilder private var closeGlyph: some View {
        if theme == .retro {
            // A bevelled close box, like a title bar button of the era.
            Image(systemName: "xmark")
                .font(.system(size: 8 * scale, weight: .heavy))
                .foregroundStyle(.black)
                .frame(width: 16 * scale, height: 14 * scale)
                .background(Self.silver)
                .overlay(Bevel(light: .white, shade: Color(white: 0.5), outer: .black))
        } else {
            Image(systemName: "xmark")
                .font(.system(size: 9 * scale, weight: .bold))
                .foregroundStyle(closeColor)
                .frame(width: 14 * scale, height: 14 * scale)
                .contentShape(Rectangle())
        }
    }

    private var closeColor: Color {
        switch theme {
        case .metallic: Color(white: 0.1)
        case .glass: .white.opacity(0.85)
        case .pill: .white.opacity(0.8)
        case .flat: .white.opacity(0.6)
        default: .white.opacity(0.7)
        }
    }

    /// The edge facing away from the window: where the light hits.
    private var outer: UnitPoint { flipped ? .bottom : .top }
    private var inner: UnitPoint { flipped ? .top : .bottom }

    private var tint: NSColor { tab.tint.usingColorSpace(.sRGB) ?? tab.tint }

    /// The app color at full strength, for the themes that use it as an accent rather than a wash.
    private var vivid: NSColor {
        NSColor(hue: tint.hueComponent, saturation: min(max(tint.saturationComponent * 1.6, 0.55), 0.85),
                brightness: 0.82, alpha: 1)
    }

    @ViewBuilder private var background: some View {
        switch theme {
        case .aqua: aquaBackground
        case .glass: glassBackground
        case .flat: flatBackground
        case .pill: pillBackground
        case .metallic: metallicBackground
        case .retro: retroBackground
        }
    }

    @ViewBuilder private var aquaBackground: some View {
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
            outerHighlight(opacity: isActive ? 0.38 : 0.06)
            shape.strokeBorder(.black.opacity(isActive ? 0.45 : 0.3), lineWidth: 1)
        }
    }

    @ViewBuilder private var glassBackground: some View {
        if #available(macOS 26, *) {
            let glass: Glass = isActive ? .regular.tint(Color(nsColor: vivid).opacity(0.8)) : .regular
            shape.fill(.clear)
                .glassEffect(glass, in: shape)
                // A wash of the app color on top: the glass tint alone reads as grey.
                .overlay(shape.fill(Color(nsColor: vivid).opacity(isActive ? 0.32 : 0)))
                .overlay(shape.strokeBorder(.white.opacity(isActive ? 0.35 : 0.18), lineWidth: 1))
        } else {
            aquaBackground
        }
    }

    @ViewBuilder private var flatBackground: some View {
        ZStack {
            shape.fill(isActive ? Color(red: 0.235, green: 0.245, blue: 0.27) : Color(red: 0.16, green: 0.165, blue: 0.185))
            if isActive {
                // The app color as a 2 pt outline around the top and sides, open towards the window.
                OpenOutline(radius: radius, flipped: flipped)
                    .stroke(Color(nsColor: vivid), lineWidth: 2)
            }
        }
    }

    @ViewBuilder private var pillBackground: some View {
        if isActive {
            shape.fill(Color(nsColor: mix(vivid, .black, 0.12)))
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
        } else {
            shape.fill(Color(red: 0.2, green: 0.21, blue: 0.24))
                .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 1))
        }
    }

    @ViewBuilder private var metallicBackground: some View {
        ZStack {
            // Steel: bright where the light hits, falling off to a dark lower edge.
            shape.fill(LinearGradient(
                stops: isActive
                    ? [.init(color: Color(white: 0.86), location: 0), .init(color: Color(white: 0.7), location: 0.45),
                       .init(color: Color(white: 0.58), location: 0.55), .init(color: Color(white: 0.5), location: 1)]
                    : [.init(color: Color(white: 0.62), location: 0), .init(color: Color(white: 0.5), location: 0.5),
                       .init(color: Color(white: 0.4), location: 1)],
                startPoint: outer, endPoint: inner))
            BrushedGrain()
                .opacity(isActive ? 1 : 0.8)
            // Deep bevel: a bright lip on the outer edge, a dark one where it meets the window.
            Bevel(light: .white.opacity(isActive ? 0.85 : 0.45), shade: .black.opacity(0.45), outer: nil)
                .padding(1.5)
            shape.strokeBorder(Color(white: 0.12), lineWidth: 1.5)
        }
        // Text and icon sit pressed into the metal.
        .compositingGroup()
    }

    @ViewBuilder private var retroBackground: some View {
        ZStack {
            if isActive {
                // The era's active title bar: navy into blue.
                Rectangle().fill(LinearGradient(
                    colors: [Color(red: 0, green: 0, blue: 0.5), Color(red: 0.06, green: 0.52, blue: 0.82)],
                    startPoint: .leading, endPoint: .trailing))
            } else {
                Rectangle().fill(Self.silver)
            }
            Bevel(light: isActive ? Self.silver : .white, shade: Color(white: 0.5), outer: .black)
        }
    }

    private func outerHighlight(opacity: Double) -> some View {
        Rectangle()
            .fill(.white.opacity(opacity))
            .frame(height: 1)
            .padding(.horizontal, radius / 2)
            .frame(maxHeight: .infinity, alignment: flipped ? .bottom : .top)
    }

    private func mix(_ color: NSColor, _ other: NSColor, _ fraction: CGFloat) -> NSColor {
        color.blended(withFraction: fraction, of: other) ?? color
    }
}

/// A 1 pt raised edge: light along the top and left, shade along the bottom and right, and
/// optionally a dark outline outside the shade, as on late-90s controls.
struct Bevel: View {
    let light: Color
    let shade: Color
    let outer: Color?

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ color: Color) {
                var path = Path()
                path.move(to: CGPoint(x: x1, y: y1))
                path.addLine(to: CGPoint(x: x2, y: y2))
                context.stroke(path, with: .color(color), lineWidth: 1)
            }
            var inset: CGFloat = 0
            if let outer {
                line(0, h - 0.5, w, h - 0.5, outer)
                line(w - 0.5, 0, w - 0.5, h, outer)
                inset = 1
            }
            line(0, 0.5, w - inset, 0.5, light)
            line(0.5, 0, 0.5, h - inset, light)
            line(0, h - inset - 0.5, w - inset, h - inset - 0.5, shade)
            line(w - inset - 0.5, 0, w - inset - 0.5, h - inset, shade)
        }
        .allowsHitTesting(false)
    }
}

/// A tab's outline without the edge that meets the window: up one side, around the rounded corners
/// and down the other. Drawn inside its frame, for a stroke of up to 2 pt.
struct OpenOutline: Shape {
    let radius: CGFloat
    let flipped: Bool

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 1, dy: 1)
        let corner = max(radius - 1, 0)
        var path = Path()
        if flipped {
            path.move(to: CGPoint(x: r.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: r.minX, y: r.maxY - corner))
            path.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX + corner, y: r.maxY), radius: corner)
            path.addLine(to: CGPoint(x: r.maxX - corner, y: r.maxY))
            path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX, y: r.maxY - corner), radius: corner)
            path.addLine(to: CGPoint(x: r.maxX, y: rect.minY))
        } else {
            path.move(to: CGPoint(x: r.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: r.minX, y: r.minY + corner))
            path.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + corner, y: r.minY), radius: corner)
            path.addLine(to: CGPoint(x: r.maxX - corner, y: r.minY))
            path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + corner), radius: corner)
            path.addLine(to: CGPoint(x: r.maxX, y: rect.maxY))
        }
        return path
    }
}

/// Brushed metal: fine horizontal streaks of varying brightness, the same every time it's drawn.
struct BrushedGrain: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func random() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(1 << 31)
            }
            var y: CGFloat = 0
            while y < size.height {
                let height = 0.5 + random() * 0.5
                var x: CGFloat = -random() * 40
                while x < size.width {
                    let length = 30 + random() * 120
                    let light = random() > 0.5
                    let rect = CGRect(x: x, y: y, width: length, height: height)
                    context.fill(Path(rect), with: .color(light ? .white.opacity(0.06 + random() * 0.12)
                                                                : .black.opacity(0.04 + random() * 0.08)))
                    x += length + random() * 6
                }
                y += height
            }
        }
        .allowsHitTesting(false)
    }
}
