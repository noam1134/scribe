import SwiftUI

@main
struct ScribeApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(ProbeAppDelegate.self) private var appDelegate
    #endif
    // Created before the store so the log sees the CloudKit "setup" event.
    @State private var log = SyncEventLog()

    init() {
        _ = ProbeStore.container
    }

    var body: some Scene {
        WindowGroup {
            ProbeRootView(log: log)
        }
    }
}
