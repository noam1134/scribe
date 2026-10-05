import AppIntents
import Foundation
import ScribeCore
import os

private let log = Logger(subsystem: "com.noamchuri.scribe", category: "intents")

/// Opens the composer, optionally in a category: the "Add to Scribe"
/// Control, the small widget's "+", and Shortcuts (spec §8). It brings the
/// app forward and runs there, handing over the same link `scribe://add`
/// would.
struct OpenQuickAddIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Quick Add"
    static let description: IntentDescription? = IntentDescription("Opens Scribe’s quick-add composer, in a category if you pick one.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Category")
    var category: CategoryEntity?

    init() {}

    init(category: CategoryEntity?) {
        self.category = category
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        log.info("OpenQuickAddIntent runs in \(ProcessInfo.processInfo.processName, privacy: .public)")
        IntentLinkInbox.shared.link = .add(categoryID: category?.liveID)
        return .result()
    }
}
