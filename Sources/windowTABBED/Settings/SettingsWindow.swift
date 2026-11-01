import AppKit
import SwiftUI

/// The Settings window. On first launch it doubles as the welcome screen where you pick your grouping key.
final class SettingsWindow {
    static let shared = SettingsWindow()

    private(set) var window: NSWindow?

    func show(welcome: Bool = false) {
        let window = self.window ?? makeWindow()
        self.window = window
        let view = SettingsView(welcome: welcome) { [weak window] in window?.close() }
        window.contentView = NSHostingView(rootView: view)
        window.center()
        // A menu bar app has to activate itself, or its window opens behind everything.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "windowTABBED Settings"
        window.isReleasedWhenClosed = false
        return window
    }
}

private struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    let welcome: Bool
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if welcome {
                Text("Welcome to windowTABBED")
                    .font(.title2.bold())
                Text("Pick the key you'll hold to group windows into tabs. You can change it here anytime.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
            }

            Text("Grouping key")
                .font(.headline)
            Text("Hold this key and drag a window onto another window. When the blue outline shows, let go to group them.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Grouping key", selection: $settings.groupingKey) {
                ForEach(GroupingKey.allCases) { key in
                    Text(key.label).tag(Optional(key))
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Divider()

            Text("Keyboard")
                .font(.headline)
            Toggle("Switch tabs with ⌃⌥← and ⌃⌥→", isOn: $settings.tabShortcutsEnabled)

            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .disabled(settings.groupingKey == nil)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
