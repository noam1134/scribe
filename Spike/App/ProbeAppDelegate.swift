#if os(macOS)
import AppKit

/// Phase 0 only. macOS apps must register for remote notifications
/// explicitly, otherwise CloudKit pushes never reach the app and it only
/// imports changes when it becomes active.
final class ProbeAppDelegate: NSObject, NSApplicationDelegate {
    static let pushEvent = Notification.Name("ProbePushEvent")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        post("push registration succeeded")
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        post("push registration FAILED: \(error.localizedDescription)")
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        post("push received")
    }

    private func post(_ text: String) {
        NotificationCenter.default.post(name: Self.pushEvent, object: text)
    }
}
#endif
