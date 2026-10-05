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

    /// A `scribe://` link that arrived before or while the UI was getting
    /// ready — a link can cold-launch the app while the store is still
    /// opening. The iPhone `RootView` takes it once it appears.
    var pendingLink: DeepLink?

    @ObservationIgnored private var refresher: SyncRefresher?
    @ObservationIgnored private var widgetRefresher: WidgetRefresher?

    /// UI tests launch with `-uiTesting`: a fresh in-memory store, no iCloud.
    static var isUITesting: Bool { CommandLine.arguments.contains("-uiTesting") }

    func load() {
        do {
            // One store per process, shared with App Intents running in the app.
            let store = try SharedStore.open()
            refresher = SyncRefresher(store: store)
            widgetRefresher = WidgetRefresher()
            state = .ready(store)
        } catch {
            state = .failed(String(describing: error))
        }
    }
}
