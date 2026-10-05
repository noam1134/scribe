import ScribeCore
import SwiftUI

@main
struct ScribeApp: App {
    @State private var loader = StoreLoader()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var macDelegate
    #endif

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
                #if os(macOS)
                macDelegate.start(loader: loader)
                #endif
            }
            .onOpenURL { url in
                // On the always-present root, so a link that launches the app
                // isn't lost while the store opens.
                if let link = DeepLink(url: url) { loader.pendingLink = link }
            }
            .environment(loader)
        }
        #if os(macOS)
        .defaultSize(width: 960, height: 640)
        .commands { MacCommands() }
        #endif

        #if os(macOS)
        MacMenuBarScene(loader: loader)
        #endif
    }
}
