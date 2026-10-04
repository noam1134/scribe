import CoreData
import Foundation
import Observation

/// Phase 0 only. Answers spec §14 Q3: can we observe CloudKit sync events
/// and remote-change notifications while using SwiftData?
@MainActor
@Observable
final class SyncEventLog {
    struct Entry: Identifiable {
        let id = UUID()
        let at: Date
        let text: String
    }

    private(set) var entries: [Entry] = []
    private(set) var remoteChangeCount = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] note in
            let text = Self.describe(note)
            MainActor.assumeIsolated { self?.append(text) }
        })
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.remoteChangeCount += 1
                self.append("remote change #\(self.remoteChangeCount)")
            }
        })
    }

    nonisolated static func describe(_ note: Notification) -> String {
        guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
            return "cloudkit event (unreadable)"
        }
        let type = switch event.type {
        case .setup: "setup"
        case .import: "import"
        case .export: "export"
        @unknown default: "other"
        }
        guard event.endDate != nil else { return "\(type) started" }
        return event.succeeded ? "\(type) succeeded" : "\(type) FAILED: \(event.error?.localizedDescription ?? "unknown")"
    }

    private func append(_ text: String) {
        entries.insert(Entry(at: .now, text: text), at: 0)
    }
}
