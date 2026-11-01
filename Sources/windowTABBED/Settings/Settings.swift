import AppKit

/// The keys you hold while dragging a window onto another one to group them: any mix of
/// ⇧ ⌃ ⌥ ⌘ and fn. Modifiers only, so holding them never types into the app you're dragging.
struct GroupingKey: Hashable {
    static let allowed: NSEvent.ModifierFlags = [.shift, .control, .option, .command, .function]

    /// One modifier each, the choices Settings offers before you record your own.
    static let presets = [NSEvent.ModifierFlags.shift, .option, .control, .command, .function].map(GroupingKey.init)

    private let rawFlags: UInt
    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: rawFlags) }

    init(_ flags: NSEvent.ModifierFlags) {
        rawFlags = flags.intersection(Self.allowed).rawValue
    }

    var isEmpty: Bool { rawFlags == 0 }
    var isPreset: Bool { Self.presets.contains(self) }

    /// In the order macOS menus show them.
    var symbols: String {
        let parts: [(NSEvent.ModifierFlags, String)] = [(.function, "fn"), (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return parts.filter { flags.contains($0.0) }.map(\.1).joined()
    }

    var label: String {
        switch flags {
        case .shift: "⇧ Shift"
        case .option: "⌥ Option"
        case .control: "⌃ Control"
        case .command: "⌘ Command"
        case .function: "fn / 🌐 Globe"
        default: symbols
        }
    }

    /// Why this key may not work for dragging windows: macOS uses some modifiers itself.
    var conflicts: [String] {
        var notes: [String] = []
        if flags.contains(.control) {
            notes.append("⌃ turns your click into a right-click, so most windows won't move while it's held.")
        }
        if flags.contains(.option) {
            notes.append("⌥ turns on macOS window tiling while you drag, so windows may snap to the side of the screen.")
        }
        return notes
    }

    /// True if `event` has all of these keys down. Extra ones don't matter.
    func isHeld(in event: NSEvent) -> Bool {
        !isEmpty && event.modifierFlags.contains(flags)
    }
}

/// How tabs look: icon and title (the default), or just the icon.
enum TabStyle: String, CaseIterable, Identifiable {
    case full, icon

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full: "Icon and title"
        case .icon: "Icon only"
        }
    }
}

/// User preferences, saved in UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()

    private enum Key {
        static let groupingKey = "groupingKeyFlags"
        static let customGroupingKey = "customGroupingKeyFlags"
        /// Before custom combos: one modifier saved by name.
        static let legacyGroupingKey = "groupingKey"
        static let tabShortcuts = "tabShortcutsEnabled"
        static let tabStyle = "tabStyle"
    }

    /// No default on purpose: you pick it on first launch (SPEC.md).
    @Published var groupingKey: GroupingKey? {
        didSet { Self.save(groupingKey, forKey: Key.groupingKey) }
    }

    /// The last combination you recorded, kept so Settings can still offer it after you pick a preset.
    @Published var customGroupingKey: GroupingKey? {
        didSet { Self.save(customGroupingKey, forKey: Key.customGroupingKey) }
    }

    /// Ctrl+Option+←/→ to switch tabs. Off by default so it never steals those keys from your apps.
    @Published var tabShortcutsEnabled: Bool {
        didSet { UserDefaults.standard.set(tabShortcutsEnabled, forKey: Key.tabShortcuts) }
    }

    @Published var tabStyle: TabStyle {
        didSet { UserDefaults.standard.set(tabStyle.rawValue, forKey: Key.tabStyle) }
    }

    private init() {
        let defaults = UserDefaults.standard
        groupingKey = Self.load(forKey: Key.groupingKey) ?? Self.legacyGroupingKey()
        customGroupingKey = Self.load(forKey: Key.customGroupingKey)
        tabShortcutsEnabled = defaults.bool(forKey: Key.tabShortcuts)
        tabStyle = defaults.string(forKey: Key.tabStyle).flatMap(TabStyle.init(rawValue:)) ?? .full
    }

    /// A recorded combination. A single modifier is one of the presets already; anything else
    /// becomes the custom choice.
    func useRecorded(_ key: GroupingKey) {
        if !key.isPreset {
            customGroupingKey = key
        }
        groupingKey = key
    }

    private static func save(_ key: GroupingKey?, forKey name: String) {
        if let key {
            UserDefaults.standard.set(Int(key.flags.rawValue), forKey: name)
        } else {
            UserDefaults.standard.removeObject(forKey: name)
        }
    }

    private static func load(forKey name: String) -> GroupingKey? {
        guard let raw = UserDefaults.standard.object(forKey: name) as? Int else { return nil }
        let key = GroupingKey(NSEvent.ModifierFlags(rawValue: UInt(raw)))
        return key.isEmpty ? nil : key
    }

    private static func legacyGroupingKey() -> GroupingKey? {
        let flags: NSEvent.ModifierFlags? = switch UserDefaults.standard.string(forKey: Key.legacyGroupingKey) {
        case "shift": .shift
        case "option": .option
        case "control": .control
        case "command": .command
        case "fn": .function
        default: nil
        }
        return flags.map(GroupingKey.init)
    }
}
