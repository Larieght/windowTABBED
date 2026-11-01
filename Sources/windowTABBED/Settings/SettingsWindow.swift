import AppKit
import SwiftUI

/// The Settings window. On first launch it doubles as the welcome screen where you pick your grouping key.
final class SettingsWindow {
    static let shared = SettingsWindow()

    private(set) var window: NSWindow?
    let recorder = KeyRecorder()

    func show(welcome: Bool = false) {
        let window = self.window ?? makeWindow()
        self.window = window
        let view = SettingsView(welcome: welcome, recorder: recorder) { [weak window] in window?.close() }
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
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
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            self?.recorder.cancel()
        }
        return window
    }
}

/// Records a grouping key combination: hold the keys you want, then let go of them.
/// Esc cancels. Only works while the Settings window is in front, since it listens locally.
final class KeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    /// What's held right now, shown while recording.
    @Published private(set) var held = GroupingKey([])

    private var monitor: Any?
    /// Everything held at once during this recording: letting go of keys one by one keeps the combo.
    private var peak = GroupingKey([])
    private var onRecord: ((GroupingKey) -> Void)?

    func start(onRecord: @escaping (GroupingKey) -> Void) {
        cancel()
        self.onRecord = onRecord
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.cancel() } // Esc
                return nil // Don't let keys typed while recording reach the window.
            }
            let now = GroupingKey(event.modifierFlags)
            self.held = now
            self.peak = GroupingKey(self.peak.flags.union(now.flags))
            if now.isEmpty, !self.peak.isEmpty {
                let recorded = self.peak
                let onRecord = self.onRecord
                self.cancel()
                onRecord?(recorded)
            }
            return event
        }
    }

    func cancel() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        held = GroupingKey([])
        peak = GroupingKey([])
        onRecord = nil
    }
}

private struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    let welcome: Bool
    @ObservedObject var recorder: KeyRecorder
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
                ForEach(GroupingKey.presets, id: \.self) { key in
                    Text(key.label).tag(Optional(key))
                }
                if let custom = settings.customGroupingKey {
                    Text("Custom: \(custom.symbols)").tag(Optional(custom))
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            HStack(spacing: 8) {
                Button(recorder.isRecording ? "Cancel" : "Record Custom Combination…") {
                    recorder.isRecording ? recorder.cancel() : recorder.start(onRecord: settings.useRecorded)
                }
                .glassButton()
                if recorder.isRecording {
                    Text(recorder.held.isEmpty ? "Hold the keys you want, then let go" : recorder.held.symbols)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Any mix of ⇧ ⌃ ⌥ ⌘ and fn.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(settings.groupingKey?.conflicts ?? [], id: \.self) { note in
                Label(note, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Text("Tabs")
                .font(.headline)
            tabStylePicker

            Divider()

            Text("Keyboard")
                .font(.headline)
            Toggle("Switch tabs with ⌃⌥← and ⌃⌥→", isOn: $settings.tabShortcutsEnabled)

            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .glassButton(prominent: true)
                    .disabled(settings.groupingKey == nil || recorder.isRecording)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    /// On macOS 26+, a Liquid Glass segmented control. Earlier systems keep the standard one.
    @ViewBuilder private var tabStylePicker: some View {
        if #available(macOS 26, *) {
            GlassSegmentedPicker(selection: $settings.tabStyle)
        } else {
            Picker("Tab style", selection: $settings.tabStyle) {
                ForEach(TabStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

private extension View {
    /// Liquid Glass buttons, in Settings only: the tab bar keeps its Aqua look on purpose.
    /// Needs macOS 26; earlier systems keep the standard buttons.
    /// macOS draws prominent glass with rounded corners whatever the shape, so a set of buttons
    /// where one may be prominent asks for `capsule: false` to match it.
    @ViewBuilder func glassButton(prominent: Bool = false, capsule: Bool = true) -> some View {
        if #available(macOS 26, *) {
            Group {
                if prominent {
                    buttonStyle(.glassProminent)
                } else {
                    buttonStyle(.glass)
                }
            }
            .buttonBorderShape(capsule ? .capsule : .roundedRectangle)
            .controlSize(.large)
        } else {
            self
        }
    }
}

/// One glass capsule holding both tab styles. The chosen one sits on a tinted glass pill
/// that springs across when you pick the other.
@available(macOS 26, *)
private struct GlassSegmentedPicker: View {
    @Binding var selection: TabStyle
    @Namespace private var thumb

    private static let spring = Animation.spring(response: 0.32, dampingFraction: 0.72)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TabStyle.allCases) { style in
                let isSelected = selection == style
                Text(style.label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(.clear)
                                .glassEffect(.regular.tint(.accentColor).interactive(), in: Capsule())
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(Self.spring) { selection = style }
                    }
            }
        }
        .padding(3)
        .glassEffect(.regular, in: Capsule())
        .animation(Self.spring, value: selection)
    }
}
