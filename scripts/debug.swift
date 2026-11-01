// Sends a command to a running debug build of windowTABBED. See DebugHooks.swift.
// Usage: swift scripts/debug.swift "select 1"
import Foundation

guard CommandLine.arguments.count > 1 else {
    print("usage: swift scripts/debug.swift \"select 1\" | \"close 0\" | snapshot")
    exit(1)
}
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("windowTABBED.debug"),
    object: CommandLine.arguments[1],
    userInfo: nil,
    deliverImmediately: true
)
