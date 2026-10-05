import ScribeCore
import SwiftUI

@main
struct ScribeApp: App {
    @State private var loader = StoreLoader()

    var body: some Scene {
        WindowGroup {
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
    }
}
