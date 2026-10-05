import Observation
import ScribeCore
import SwiftData

/// Opens the store once at launch (spec §13: a failure shows a screen with
/// Retry; the store file is never deleted or reset).
@MainActor
@Observable
final class StoreLoader {
    enum State {
        case loading
        case ready(SwiftDataItemStore)
        case failed(String)
    }

    private(set) var state: State = .loading
    @ObservationIgnored private var refresher: SyncRefresher?

    /// UI tests launch with `-uiTesting`: a fresh in-memory store, no iCloud.
    static var isUITesting: Bool { CommandLine.arguments.contains("-uiTesting") }

    func load() {
        do {
            let container = Self.isUITesting
                ? try StoreFactory.inMemory()
                : try StoreFactory.shared(syncsWithCloudKit: true)
            let store = SwiftDataItemStore(container: container)
            refresher = SyncRefresher(store: store)
            state = .ready(store)
        } catch {
            state = .failed(String(describing: error))
        }
    }
}
