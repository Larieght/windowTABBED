import AppKit
import SwiftUI

/// The Settings window: a page per tab (General, Appearance, Behavior, Experimental, About), so it
/// stays short however many settings there are. The tabs are WT's own glass strip rather than a
/// window toolbar, so a click gets a press, a sliding highlight and a little bounce. On first
/// launch it opens on General, which doubles as the welcome screen where you pick your grouping key.
final class SettingsWindow {
    static let shared = SettingsWindow()

    private(set) var window: NSWindow?
    let recorder = KeyRecorder()
    /// The page showing, and the one Settings opens on next time.
    let navigation = SettingsNavigation()

    func show(welcome: Bool = false, page: SettingsPage? = nil) {
        LoginItem.shared.refresh()
        let window = self.window ?? makeWindow()
        self.window = window
        if welcome {
            navigation.page = .general
        } else if let page {
            navigation.page = page
        }
        let root = SettingsRoot(welcome: welcome, recorder: recorder, navigation: navigation,
                                onDone: { [weak window] in window?.close() })
        let controller = SettingsHostingController(rootView: AnyView(root))
        window.contentViewController = controller
        controller.fitWindow(animate: false)
        window.center()
        // A menu bar app has to activate itself, or its window opens behind everything.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsPage.width, height: 380),
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

/// The Settings pages, one per tab.
enum SettingsPage: String, CaseIterable {
    case general, appearance, behavior, experimental, about

    static let width: CGFloat = 420

    var label: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .behavior: "Behavior"
        case .experimental: "Experimental"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .behavior: "hand.point.up.left"
        case .experimental: "flask"
        case .about: "info.circle"
        }
    }
}

/// Which page is showing. Held outside the views (no @State without Xcode's macros).
final class SettingsNavigation: ObservableObject {
    @Published var page = SettingsPage.general
    /// Counts clicks per tab, so its icon bounces each time you pick it.
    @Published var picks: [SettingsPage: Int] = [:]

    func pick(_ page: SettingsPage) {
        picks[page, default: 0] += 1
        withAnimation(SettingsTabStrip.spring) { self.page = page }
    }
}

/// Hosts the Settings view. The window takes the view's height, keeping its top edge where it
/// is, and follows it when a page grows or shrinks (another tab, or a setting that shows more).
private final class SettingsHostingController: NSHostingController<AnyView> {
    override init(rootView: AnyView) {
        super.init(rootView: rootView)
        sizingOptions = [.preferredContentSize]
    }

    @MainActor required init?(coder: NSCoder) { nil }

    override var preferredContentSize: NSSize {
        didSet { if preferredContentSize != oldValue { fitWindow(animate: true) } }
    }

    func fitWindow(animate: Bool) {
        guard let window = view.window ?? SettingsWindow.shared.window else { return }
        let height = preferredContentSize.height > 0 ? preferredContentSize.height : view.fittingSize.height
        let content = window.contentRect(forFrameRect: window.frame)
        let target = window.frameRect(forContentRect: NSRect(x: content.minX, y: content.maxY - height,
                                                             width: SettingsPage.width, height: height))
        guard target != window.frame else { return }
        if animate, window.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(target, display: true)
            }
        } else {
            window.setFrame(target, display: true)
        }
    }
}

/// The tab strip over the current page. The page fades in as the window resizes around it.
private struct SettingsRoot: View {
    let welcome: Bool
    @ObservedObject var recorder: KeyRecorder
    @ObservedObject var navigation: SettingsNavigation
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabStrip(navigation: navigation)
                .padding(.top, 10)
                .padding(.bottom, 4)
            ZStack(alignment: .top) {
                page(navigation.page)
                    .padding(20)
                    .frame(width: SettingsPage.width, alignment: .topLeading)
                    .id(navigation.page)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .frame(width: SettingsPage.width)
        .fixedSize(horizontal: false, vertical: true)
        // While the window animates to a new height, the page stays pinned to the top.
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private func page(_ page: SettingsPage) -> some View {
        switch page {
        case .general: GeneralPage(welcome: welcome, recorder: recorder, onDone: onDone)
        case .appearance: AppearancePage()
        case .behavior: BehaviorPage()
        case .experimental: ExperimentalPage()
        case .about: AboutPage()
        }
    }
}

/// Icon-and-label tabs. The chosen one sits on a glass plate that springs across to the tab you
/// click; a tab squashes while pressed and its icon bounces when picked.
private struct SettingsTabStrip: View {
    @ObservedObject var navigation: SettingsNavigation
    @Namespace private var plate

    static let spring = Animation.spring(response: 0.34, dampingFraction: 0.72)
    private static let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsPage.allCases, id: \.self) { page in
                let selected = navigation.page == page
                Button { navigation.pick(page) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: page.symbol)
                            .font(.system(size: 17, weight: .medium))
                            .symbolEffect(.bounce, value: navigation.picks[page, default: 0])
                            .frame(height: 22)
                        Text(page.label)
                            .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    }
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 76, height: 52)
                    .background {
                        if selected {
                            plateView.matchedGeometryEffect(id: "plate", in: plate)
                        }
                    }
                    .contentShape(Self.shape)
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(4)
        .animation(Self.spring, value: navigation.page)
    }

    @ViewBuilder private var plateView: some View {
        if #available(macOS 26, *) {
            Self.shape
                .fill(.clear)
                .glassEffect(.regular.tint(.accentColor.opacity(0.22)).interactive(), in: Self.shape)
        } else {
            Self.shape.fill(Color.primary.opacity(0.1))
        }
    }
}

/// Squashes a little while pressed and springs back.
private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
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


// MARK: - Pages

private struct GeneralPage: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var loginItem = LoginItem.shared
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

            Text("Keyboard")
                .font(.headline)
            Toggle("Switch tabs with ⌃⌥← and ⌃⌥→", isOn: $settings.tabShortcutsEnabled)

            Divider()

            Text("Startup")
                .font(.headline)
            Toggle("Open windowTABBED at login", isOn: Binding(get: { loginItem.isOn }, set: loginItem.set))
            if loginItem.needsApproval {
                HStack(spacing: 8) {
                    Text("Waiting for your OK in Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Login Items…", action: loginItem.openSystemSettings)
                        .controlSize(.small)
                }
            }

            if welcome {
                HStack {
                    Spacer()
                    Button("Done", action: onDone)
                        .keyboardShortcut(.defaultAction)
                        .glassButton(prominent: true)
                        .disabled(settings.groupingKey == nil || recorder.isRecording)
                }
            }
        }
    }
}

private struct AppearancePage: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tabs")
                .font(.headline)
            segmentedPicker($settings.tabStyle, label: "Tab style")
            SizeSlider()

            Divider()

            Text("Theme")
                .font(.headline)
            ThemeGrid(selection: $settings.tabTheme, showExperimental: settings.showExperimentalThemes)
            Toggle("Show experimental themes", isOn: $settings.showExperimentalThemes)
                .font(.callout)
            if settings.tabTheme == .glass, settings.tabTheme.resolved != .glass {
                Text("Liquid Glass needs macOS 26. Tabs use Aqua until then.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct BehaviorPage: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dragging a tab out")
                .font(.headline)
            segmentedPicker($settings.tearOffStyle, label: "Dragging a tab out")
            note(tearOffNote)

            Divider()

            Text("Pinned tab bars")
                .font(.headline)
            segmentedPicker($settings.pinnedLook, label: "Pinned tab bars")
            note("Right-click a tab bar to pin it on top of other windows. This is how it looks while they cover its group.")

            Divider()

            Text("Scrolling")
                .font(.headline)
            note("Scroll over a tab bar to switch tabs: up for the previous one, down for the next.")
            segmentedPicker($settings.scrollArea, label: "Scroll to switch tabs")
            if settings.scrollArea == .anywhere {
                HStack(spacing: 10) {
                    Text("Key to hold")
                    Picker("Key to hold", selection: $settings.scrollKey) {
                        ForEach(GroupingKey.presets, id: \.self) { key in
                            Text(key.label).tag(key)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                note(scrollKeyNote)
            }
            HStack(spacing: 10) {
                Text("At the first and last tab")
                segmentedPicker($settings.scrollEnds, label: "At the first and last tab")
            }
        }
    }

    private var scrollKeyNote: String {
        switch settings.scrollKey.flags {
        case .shift: "With ⇧ held, many apps scroll sideways instead. Over a grouped window, WT takes the scroll."
        case .control: "⌃ and scroll may zoom the whole screen if Accessibility Zoom is on."
        default: "With the key held, scrolling over a grouped window switches its tabs instead of scrolling it."
        }
    }

    private var tearOffNote: String {
        switch settings.tearOffStyle {
        case .window: "The window itself follows the pointer. Bring it back over the bar to undo."
        case .outline: "A floating tab and an outline of where the window will land."
        case .tab: "Just a floating tab. The window moves when you let go."
        }
    }
}

/// Features still being worked on, each off until you turn it on.
private struct ExperimentalPage: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Experimental")
                    .font(.headline)
                ExperimentalBadge()
            }
            note("Features that aren't finished yet. They may change, or go away, in a later version.")

            Divider()

            Toggle("Stack Tabs by App", isOn: $settings.stackingEnabled)
            note("Adds Stack Tabs by App to a tab bar's right-click menu: each app's tabs pile up like cards in a wallet, each peeking out with its title.")

            Divider()

            Toggle("Show experimental themes", isOn: $settings.showExperimentalThemes)
            note("Adds Flat, Pill and Metallic to Appearance › Theme.")
        }
    }
}

private struct AboutPage: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 96, height: 96)
            Text("windowTABBED")
                .font(.title2.bold())
            Text("Version \(AppDelegate.versionDescription)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                linkButton("GitHub", to: Links.repository)
                linkButton("Check for Updates", to: Links.releases)
                linkButton("Report a Bug", to: Links.newIssue)
            }
            .padding(.top, 4)
            Text("© 2026 Larieght · Free and open source under the MIT license")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func linkButton(_ title: String, to url: URL) -> some View {
        Button(title) { NSWorkspace.shared.open(url) }
            .controlSize(.small)
            .glassButton()
    }
}

// MARK: - Shared pieces

/// A small grey explanation under a setting.
private func note(_ text: String) -> some View {
    Text(text)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
}

/// The orange tag on experimental things.
private struct ExperimentalBadge: View {
    var body: some View {
        Text("EXPERIMENTAL")
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(.black)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(.orange))
    }
}

/// Four sizes on a slider with a stop for each; Small is the original size.
private struct SizeSlider: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let sizes = TabSize.allCases
        let index = Binding<Double>(
            get: { Double(sizes.firstIndex(of: settings.tabSize) ?? 0) },
            set: { settings.tabSize = sizes[min(max(Int($0.rounded()), 0), sizes.count - 1)] })
        HStack(spacing: 10) {
            Text("Size")
            Slider(value: index, in: 0...Double(sizes.count - 1), step: 1) {
                Text("Size")
            } minimumValueLabel: {
                Image(systemName: "textformat.size.smaller")
            } maximumValueLabel: {
                Image(systemName: "textformat.size.larger")
            }
            .labelsHidden()
            Text(settings.tabSize.label)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .trailing)
        }
    }
}

/// On macOS 26+, a Liquid Glass segmented control. Earlier systems keep the standard one.
@ViewBuilder private func segmentedPicker<Option: PickerOption>(_ selection: Binding<Option>, label: String) -> some View {
    if #available(macOS 26, *) {
        GlassSegmentedPicker(selection: selection)
    } else {
        Picker(label, selection: selection) {
            ForEach(Array(Option.allCases)) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
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
private struct GlassSegmentedPicker<Option: PickerOption>: View {
    @Binding var selection: Option
    @Namespace private var thumb

    private static var spring: Animation { .spring(response: 0.32, dampingFraction: 0.72) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Option.allCases)) { style in
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

/// A choice shown as one segment of a picker.
protocol PickerOption: CaseIterable, Identifiable, Hashable {
    var label: String { get }
}

extension TabStyle: PickerOption {}
extension TearOffStyle: PickerOption {}
extension PinnedLook: PickerOption {}
extension ScrollArea: PickerOption {}
extension ScrollEnds: PickerOption {}

/// The themes as a grid of small live previews: each card draws real tabs in that theme. The
/// chosen card sits on a tinted glass plate that slides across when you pick another (macOS 26+;
/// earlier systems outline it in the accent color).
private struct ThemeGrid: View {
    @Binding var selection: TabTheme
    let showExperimental: Bool
    @Namespace private var plate

    private static var spring: Animation { .spring(response: 0.32, dampingFraction: 0.72) }
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    /// Two sample tabs, from apps every Mac has.
    private static let samples: [TabBarModel.Tab] = ["com.apple.Safari", "com.apple.mail"].enumerated().map { index, id in
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            .map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSApp.applicationIconImage ?? NSImage()
        return TabBarModel.Tab(id: CGWindowID(index + 1), title: "", icon: icon,
                               tint: AppTint.dominantColor(of: icon) ?? AppTint.fallback)
    }

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: 8) {
            // Two rows: Aqua, Liquid Glass and Retro 98, then the experimental three.
            ForEach(TabTheme.displayOrder.filter { showExperimental || !$0.isExperimental }) { theme in
                card(theme)
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture {
                        withAnimation(Self.spring) { selection = theme }
                    }
            }
        }
        .animation(Self.spring, value: selection)
        .animation(Self.spring, value: showExperimental)
    }

    private func card(_ theme: TabTheme) -> some View {
        let isSelected = selection == theme
        return VStack(spacing: 5) {
            preview(theme.resolved)
                .overlay(alignment: .topTrailing) {
                    if theme.isExperimental {
                        Text("EXPERIMENTAL")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(.orange))
                            .padding(3)
                    }
                }
            Text(theme.label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(5)
        .background {
            if isSelected {
                if #available(macOS 26, *) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular.tint(.accentColor.opacity(0.45)).interactive(),
                                     in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .matchedGeometryEffect(id: "plate", in: plate)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .matchedGeometryEffect(id: "plate", in: plate)
                }
            }
        }
    }

    /// An active and a background tab sitting on a window's top edge, over a colorful backdrop
    /// so glass has something to show.
    private func preview(_ theme: TabTheme) -> some View {
        let scale: CGFloat = 0.8
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: (theme.spacing * scale).rounded()) {
                TabFace(tab: Self.samples[0], isActive: true, flipped: false, iconOnly: true,
                        width: (56 * scale).rounded(), theme: theme, scale: scale)
                TabFace(tab: Self.samples[1], isActive: false, flipped: false, iconOnly: true,
                        width: (36 * scale).rounded(), theme: theme, scale: scale)
            }
            .frame(height: (30 * scale).rounded(), alignment: .bottom)
            .padding(.leading, 8)
            .allowsHitTesting(false)
            UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6)
                .fill(Color(white: 0.13))
                .frame(height: 14)
        }
        .padding(.top, 8)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Color(red: 0.12, green: 0.45, blue: 0.55), Color(red: 0.32, green: 0.28, blue: 0.62),
                                            Color(red: 0.85, green: 0.45, blue: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// The project on GitHub.
enum Links {
    static let repository = URL(string: "https://github.com/Larieght/windowTABBED")!
    /// Releases: where a newer version shows up.
    static let releases = URL(string: "https://github.com/Larieght/windowTABBED/releases")!
    static let newIssue = URL(string: "https://github.com/Larieght/windowTABBED/issues/new")!
}
