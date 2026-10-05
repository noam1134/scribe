import ScribeCore
import SwiftUI

@main
struct ScribeApp: App {
    @State private var loader: StoreLoader

    init() {
        let loader = StoreLoader()
        _loader = State(initialValue: loader)
        // Before launch finishes, so a notification tap or button that
        // launched the app reaches it.
        NotificationCoordinator.shared.install(loader: loader)
    }

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
            .environment(loader)
        }
    }
}
