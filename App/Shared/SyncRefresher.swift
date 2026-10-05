import CoreData
import ScribeCore

/// Re-reads the store after iCloud imports and after writes from other
/// processes (widget, intents), so open screens update (spec §12).
@MainActor
final class SyncRefresher {
    private var observers: [NSObjectProtocol] = []

    init(store: SwiftDataItemStore) {
        let center = NotificationCenter.default
        let names = [NSPersistentCloudKitContainer.eventChangedNotification, .NSPersistentStoreRemoteChange]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak store] _ in
                MainActor.assumeIsolated { store?.refresh() }
            })
        }
    }
}
