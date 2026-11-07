import ServiceManagement

/// Settings › General › Open at login. macOS keeps this state itself (System Settings › General ›
/// Login Items), so it's read back from there rather than saved in UserDefaults.
final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    @Published private(set) var status = SMAppService.mainApp.status

    /// On, or waiting for you to approve it in System Settings.
    var isOn: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Open at login \(on ? "on" : "off", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    /// It can change in System Settings while windowTABBED runs.
    func refresh() {
        status = SMAppService.mainApp.status
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
