import AppKit
import ApplicationServices

/// The Accessibility permission lets windowTABBED move, resize and raise other apps' windows.
final class Permissions {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system dialog that points the user to System Settings.
    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private var timer: Timer?

    /// macOS sends no notification when access is granted, so poll once a second until it is.
    func waitForAccess(onGranted: @escaping () -> Void) {
        guard !Self.isTrusted else {
            onGranted()
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard Self.isTrusted else { return }
            timer.invalidate()
            self?.timer = nil
            onGranted()
        }
    }
}
