import AppIntents
import Foundation
import ScribeCore
import os

private let log = Logger(subsystem: "com.noamchuri.scribe", category: "intents")

/// "Add to Scribe" from Siri and Shortcuts (spec §8): saves without opening
/// the app. It's built into the app only, so it always runs in the app's
/// process with the iCloud-syncing store. Every item ends in a real
/// category (spec §19): the Category parameter, a `#tag`, a mention ("…
/// for work"), the on-device model's pick, or Siri asks. "Remind me to …"
/// leaves the title.
struct AddItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Scribe"
    static let description: IntentDescription? = IntentDescription(
        "Adds a task or memo. Understands dates, times and categories, like “book flights fri #thailand” or “remind me to call mom tomorrow 9am for family”."
    )

    @Parameter(title: "Text", requestValueDialog: "What should I add?")
    var text: String

    @Parameter(title: "Category")
    var category: CategoryEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to \(\.$category)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        log.info("AddItemIntent runs in \(ProcessInfo.processInfo.processName, privacy: .public)")
        let store = try SharedStore.openForIntent()
        let categories = store.categories
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent

        var draft: ItemDraft
        switch IntentAdd.resolve(text, categoryID: category?.liveID, categories: categories, now: now, calendar: calendar) {
        case .ready(let ready):
            draft = ready
        case .needsCategory(let partial):
            draft = partial
            if let suggestion = await CategoryGuesser.suggestion(for: partial.title, in: categories, timeout: .seconds(5)) {
                draft.categoryID = suggestion.categoryID
                draft.title = suggestion.title
            } else {
                let chosen = try await $category.requestDisambiguation(
                    among: categories.map(CategoryEntity.init),
                    dialog: "Which category should ‘\(partial.title)’ go in?"
                )
                draft.categoryID = chosen.id
            }
        case .noCategories:
            throw IntentError.noCategories
        case .emptyTitle:
            throw $text.needsValueError("What should I add?")
        }

        do {
            try store.addItem(draft)
        } catch let error as StoreError {
            throw IntentError.store(error)
        }
        await StoreChanged.notify()

        let name = categories.first { $0.id == draft.categoryID }?.name ?? ""
        let reply = IntentAdd.reply(title: draft.title, categoryName: name, due: draft.due, now: now, calendar: calendar, locale: .autoupdatingCurrent)
        return .result(dialog: "\(reply)")
    }
}
