import AppKit
import Carbon.HIToolbox
import Combine

/// Ctrl+Option+← / → switch to the previous / next tab of the group you're in.
///
/// Carbon hot keys work system-wide without extra permissions and swallow the key press,
/// so the app you're in doesn't also see it. Registered only while the setting is on.
final class TabShortcuts {
    private let groups: GroupManager
    private var hotKeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var subscription: AnyCancellable?

    private static let signature: OSType = 0x5754_6162 // "WTab"
    private enum ID: UInt32 { case previous = 1, next = 2 }

    init(groups: GroupManager) {
        self.groups = groups
        subscription = Settings.shared.$tabShortcutsEnabled.sink { [weak self] enabled in
            enabled ? self?.register() : self?.unregister()
        }
    }

    private func register() {
        guard hotKeys.isEmpty else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &type,
                            Unmanaged.passUnretained(self).toOpaque(), &handler)
        let modifiers = UInt32(controlKey | optionKey)
        for (key, id) in [(kVK_LeftArrow, ID.previous), (kVK_RightArrow, ID.next)] {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: id.rawValue)
            if RegisterEventHotKey(UInt32(key), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                hotKeys.append(ref)
            }
        }
        log.notice("Tab shortcuts on (\(self.hotKeys.count, privacy: .public) registered)")
    }

    private func unregister() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    fileprivate func pressed(_ id: UInt32) {
        groups.cycleTabs(by: id == ID.previous.rawValue ? -1 : 1)
    }
}

private let hotKeyCallback: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                      nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    Unmanaged<TabShortcuts>.fromOpaque(userData).takeUnretainedValue().pressed(hotKeyID.id)
    return noErr
}
