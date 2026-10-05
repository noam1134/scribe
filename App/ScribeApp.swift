import ScribeCore
import SwiftUI

@main
struct ScribeApp: App {
    @State private var store: SwiftDataItemStore

    init() {
        do {
            _store = State(initialValue: SwiftDataItemStore(container: try StoreFactory.shared(syncsWithCloudKit: true)))
        } catch {
            // Phase 2 replaces this with the full-screen error + Retry from spec §13.
            fatalError("Store failed to open: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            StoreSmokeView(store: store)
        }
    }
}
