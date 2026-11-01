import AppKit

/// The key you hold while dragging a window onto another one to group them.
enum GroupingKey: String, CaseIterable, Identifiable {
    case shift, option, control, command, fn

    var id: String { rawValue }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift: .shift
        case .option: .option
        case .control: .control
        case .command: .command
        case .fn: .function
        }
    }

    var label: String {
        switch self {
        case .shift: "⇧ Shift"
        case .option: "⌥ Option"
        case .control: "⌃ Control"
        case .command: "⌘ Command"
        case .fn: "fn / 🌐 Globe"
        }
    }
}

/// User preferences, saved in UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()

    private enum Key {
        static let groupingKey = "groupingKey"
        static let tabShortcuts = "tabShortcutsEnabled"
    }

    /// No default on purpose: you pick it on first launch (SPEC.md).
    @Published var groupingKey: GroupingKey? {
        didSet { UserDefaults.standard.set(groupingKey?.rawValue, forKey: Key.groupingKey) }
    }

    /// Ctrl+Option+←/→ to switch tabs. Off by default so it never steals those keys from your apps.
    @Published var tabShortcutsEnabled: Bool {
        didSet { UserDefaults.standard.set(tabShortcutsEnabled, forKey: Key.tabShortcuts) }
    }

    private init() {
        groupingKey = UserDefaults.standard.string(forKey: Key.groupingKey).flatMap(GroupingKey.init(rawValue:))
        tabShortcutsEnabled = UserDefaults.standard.bool(forKey: Key.tabShortcuts)
    }
}
