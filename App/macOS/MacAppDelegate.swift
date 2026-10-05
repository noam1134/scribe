import AppKit
import CloudKit
import ScribeCore

/// App-level Mac work: remote-notification registration (spec §18), the
/// quick-add hotkey (spec §8), and a refresh whenever the app becomes active.
@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    /// Set by `ScribeApp.init`, which creates the one loader before launch
    /// finishes.
    static var launchLoader: StoreLoader?

    private weak var loader: StoreLoader?
    private var syncLog: SyncEventLog?
    private(set) var quickAddPanel: QuickAddPanelController?

    private var store: SwiftDataItemStore? {
        if case .ready(let store) = loader?.state { return store }
        return nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // At launch, not when a window first appears: the hotkey must work
        // even if no window is open.
        if let loader = Self.launchLoader { start(loader: loader) }
        guard !StoreLoader.isUITesting else { return }
        syncLog = SyncEventLog()
        // Phase 0 never saw a CloudKit push reach the Mac app, even with this
        // registration; the callbacks below log what a signed build gets.
        MacLog.push.info("Registering for remote notifications")
        NSApp.registerForRemoteNotifications()
    }

    private func start(loader: StoreLoader) {
        guard self.loader == nil else { return }
        self.loader = loader
        let panel = QuickAddPanelController(loader: loader)
        quickAddPanel = panel
        #if DEBUG
        if DemoData.isRequested, CommandLine.arguments.contains("-showQuickAddPanel") {
            Task {
                try? await Task.sleep(for: .seconds(1))
                panel.show()
            }
        }
        #endif
        // A test run must not take a global shortcut from the user.
        guard !StoreLoader.isUITesting else { return }
        QuickAddHotkey.install { panel.toggle() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // The Mac imports from iCloud ~2 s after activation (spec §18); the
        // import itself refreshes again through `SyncRefresher`.
        MacLog.sync.info("App became active")
        store?.refresh()
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MacLog.push.info("Registered for remote notifications (\(deviceToken.count) byte token)")
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        MacLog.push.error("Remote notification registration failed: \(String(describing: error), privacy: .public)")
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        let note = CKNotification(fromRemoteNotificationDictionary: userInfo)
        let kind = note.map { String(describing: $0.notificationType.rawValue) } ?? "not CloudKit"
        let subscription = note?.subscriptionID ?? "none"
        MacLog.push.info("Push received: type \(kind, privacy: .public), subscription \(subscription, privacy: .public)")
        store?.refresh()
    }
}
