import CoreData
import ScribeCore

/// Re-reads the store after iCloud imports and after writes from other
/// processes (widget, intents), so open screens update (spec §12).
@MainActor
final class SyncRefresher {
    private var observers: [NSObjectProtocol] = []

    init(store: SwiftDataItemStore) {
        let center = NotificationCenter.default
        // Every CloudKit event is posted when it starts and again when it
        // ends; only the end can bring new data.
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak store] note in
            let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            guard let event = note.userInfo?[key] as? NSPersistentCloudKitContainer.Event, event.endDate != nil else { return }
            MainActor.assumeIsolated { store?.refresh() }
        })
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak store] _ in
            MainActor.assumeIsolated { store?.refresh() }
        })
    }
}
