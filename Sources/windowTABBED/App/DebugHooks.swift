#if DEBUG
import AppKit

/// Debug builds only: lets scripts drive the tab bars, since UI-testing tools can't click
/// a menu bar app's own windows. Trigger with scripts/debug.swift.
///
///   select <n>    click tab n (0-based) of the first group
///   close <n>     click × on tab n of the first group
///   snapshot      save each bar as build/tabbar-<k>.png
final class DebugHooks {
    static let notification = Notification.Name("windowTABBED.debug")

    private let groups: GroupManager

    init(groups: GroupManager) {
        self.groups = groups
        DistributedNotificationCenter.default().addObserver(forName: Self.notification, object: nil, queue: .main) { [weak self] note in
            guard let command = note.object as? String else { return }
            self?.run(command)
        }
    }

    private func run(_ command: String) {
        let parts = command.split(separator: " ")
        let index = parts.count > 1 ? Int(parts[1]) : nil
        let group = groups.groups.first
        switch (parts.first, index, group) {
        case ("select", let n?, let group?) where group.windows.indices.contains(n):
            group.bar.model.onSelect?(group.windows[n].windowID)
        case ("close", let n?, let group?) where group.windows.indices.contains(n):
            group.bar.model.onClose?(group.windows[n].windowID)
        case ("snapshot", _, _):
            snapshot()
        default:
            log.notice("debug: can't run \(command, privacy: .public)")
            return
        }
        log.notice("debug: ran \(command, privacy: .public)")
    }

    private func snapshot() {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build")
        for (k, group) in groups.groups.enumerated() {
            guard let view = group.bar.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = folder.appendingPathComponent("tabbar-\(k).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            log.notice("debug: saved \(url.path, privacy: .public)")
        }
    }
}
#endif
