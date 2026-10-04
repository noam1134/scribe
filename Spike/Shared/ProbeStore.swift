import Foundation
import ScribeCore
import SwiftData
import WidgetKit

struct ProbeSummary: Sendable {
    let total: Int
    let latest: [String]
}

/// Phase 0 only. One container per process: the main app syncs with
/// CloudKit, the widget extension only reads/writes the shared file.
enum ProbeStore {
    static let isMainApp = Bundle.main.bundleURL.pathExtension == "app"
    static let processLabel = isMainApp ? "app" : "extension"

    static let container: ModelContainer = {
        let config = ModelConfiguration(
            "ScribeProbe",
            groupContainer: .identifier(ScribeIDs.appGroup),
            cloudKitDatabase: isMainApp ? .private(ScribeIDs.cloudKitContainer) : .none
        )
        do {
            return try ModelContainer(for: ProbeNote.self, configurations: config)
        } catch {
            fatalError("Probe store failed to open: \(error)")
        }
    }()

    /// Text records who wrote it, from which process, and when.
    static func add(source: String) throws {
        let context = ModelContext(container)
        let stamp = Date.now.formatted(date: .omitted, time: .standard)
        context.insert(ProbeNote(text: "\(source) via \(processLabel) @ \(stamp)"))
        try context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func summary() -> ProbeSummary {
        let context = ModelContext(container)
        var latest = FetchDescriptor<ProbeNote>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        latest.fetchLimit = 3
        let total = (try? context.fetchCount(FetchDescriptor<ProbeNote>())) ?? -1
        let texts = ((try? context.fetch(latest)) ?? []).map(\.text)
        return ProbeSummary(total: total, latest: texts)
    }
}
