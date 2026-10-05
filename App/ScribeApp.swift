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
        }
    }
}
