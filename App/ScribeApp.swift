import ScribeCore
import SwiftUI

@main
struct ScribeApp: App {
    @State private var loader: StoreLoader
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var macDelegate
    #endif

    init() {
        let loader = StoreLoader()
        _loader = State(initialValue: loader)
        // Before launch finishes, so a notification tap or button that
        // launched the app reaches it.
        NotificationCoordinator.shared.install(loader: loader)
        #if os(macOS)
        // For the hotkey, installed when launch finishes.
        MacAppDelegate.launchLoader = loader
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                switch loader.state {
                case .loading:
                    ProgressView()
                case .failed(let message):
                    StoreFailedView(message: message, retry: loader.load)
                case .ready(let store):
                    RootView(store: store)
                }
            }
            .task {
                if case .loading = loader.state { loader.load() }
            }
            .onOpenURL { url in
                // On the always-present root, so a link that launches the app
                // isn't lost while the store opens.
                if let link = DeepLink(url: url) { loader.pendingLink = link }
            }
            .onChange(of: IntentLinkInbox.shared.link, initial: true) { _, link in
                // From the Control or a shortcut that opened the app.
                guard let link else { return }
                IntentLinkInbox.shared.link = nil
                loader.pendingLink = link
            }
            .environment(loader)
        }
        #if os(iOS)
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
        #endif
        #if os(macOS)
        .defaultSize(width: 960, height: 640)
        .commands { MacCommands() }
        #endif

        #if os(macOS)
        MacMenuBarScene(loader: loader)
        MacSettingsScene(loader: loader)
        #endif
    }
}
