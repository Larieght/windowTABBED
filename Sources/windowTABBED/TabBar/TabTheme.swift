import AppKit

/// How tabs are drawn. Settings › Tabs › Theme. Designs: the Figma file's Themes page.
enum TabTheme: String, CaseIterable, Identifiable {
    /// The theme you get until you pick one.
    static let standard = TabTheme.glass

    /// Glossy gradient tinted by the app icon, tack-shaped tabs joined to the window (the original).
    case aqua
    /// Frosted glass tinted by the app color, the default. macOS 26+; earlier systems draw Aqua.
    case glass
    /// Solid neutral tabs; the active one is lighter with a stripe in the app color.
    case flat
    /// Separate capsules floating just above the window; the active one filled with the app color.
    case pill
    /// Heavy brushed steel: a fine horizontal grain, a deep bevel and embossed text.
    case metallic
    /// Late-90s PC desktop: square silver bevelled tabs, navy gradient on the active one.
    case retro

    var id: String { rawValue }

    var label: String {
        switch self {
        case .aqua: "Aqua"
        case .glass: "Liquid Glass"
        case .flat: "Flat"
        case .pill: "Pill"
        case .metallic: "Metallic"
        case .retro: "Retro 98"
        }
    }

    /// Not up to standard yet: only offered with Settings › Show experimental themes on.
    var isExperimental: Bool { self == .flat || self == .pill || self == .metallic }

    /// The order Settings shows them in: the finished themes first, the experimental ones after.
    static let displayOrder: [TabTheme] = allCases.filter { !$0.isExperimental } + allCases.filter(\.isExperimental)

    /// What actually gets drawn: Liquid Glass needs macOS 26.
    var resolved: TabTheme {
        if self == .glass, #unavailable(macOS 26) { return .aqua }
        return self
    }

    /// Space between tabs.
    var spacing: CGFloat {
        switch self {
        case .aqua, .retro: 2
        case .glass: 4
        case .flat: 1
        case .pill: 6
        case .metallic: 1
        }
    }

    /// Tab height, not counting `float`. The bar itself is always 30 pt.
    func height(active: Bool) -> CGFloat {
        switch self {
        case .aqua, .glass: active ? 30 : 26
        case .flat: 30
        case .pill: 24
        case .metallic: active ? 28 : 25
        case .retro: active ? 24 : 22
        }
    }

    /// Gap between the tabs and the window: pills float, the others sit on the window's edge.
    var float: CGFloat { self == .pill ? 3 : 0 }

    var fontSize: CGFloat {
        switch self {
        case .aqua, .glass, .flat: 13
        case .pill: 12
        case .metallic: 12.5
        case .retro: 11
        }
    }
}

/// How big tabs are drawn. Settings › Tabs › Size. Small is the original size.
enum TabSize: String, CaseIterable, Identifiable {
    case small, medium, large, extraLarge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }

    /// Every tab measurement (height, width, text, icon, corners) is multiplied by this.
    var scale: CGFloat {
        switch self {
        case .small: 1
        case .medium: 1.17
        case .large: 1.33
        case .extraLarge: 1.5
        }
    }
}
