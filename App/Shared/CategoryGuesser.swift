import FoundationModels
import NaturalLanguage
import ScribeCore
import SwiftUI
import os

private let log = Logger(subsystem: "com.noamchuri.scribe", category: "smartAdd")

/// The second layer of plain-language adds: when the words name no
/// category, Apple's on-device model picks one of the user's categories
/// and trims the title. It runs on the device only (`SystemLanguageModel`,
/// never Private Cloud Compute) and only where Apple Intelligence is on and
/// speaks the text's language; elsewhere — the simulator, older devices, UI
/// tests — the parser's layer works alone. `CategorySuggestion` checks
/// every answer.
@MainActor
enum CategoryGuesser {
    struct Answer: Sendable {
        /// nil: no category fits.
        let categoryName: String?
        let title: String?
    }

    static var isAvailable: Bool {
        !StoreLoader.isUITesting && SystemLanguageModel.default.availability == .available
    }

    /// nil when the model can't answer (unavailable, unsupported language,
    /// an error, cancelled). With a `delay` — the typing pause — the model
    /// warms up while it runs.
    static func answer(title: String, categoryNames: [String], after delay: Duration = .zero) async -> Answer? {
        guard isAvailable, !categoryNames.isEmpty, speaks(title) else { return nil }
        let none = noneChoice(avoiding: categoryNames)
        let session = LanguageModelSession(model: .default, instructions: instructions(none: none))
        if delay > .zero {
            session.prewarm()
            do {
                try await Task.sleep(for: delay)
            } catch {
                return nil
            }
        }
        do {
            let schema = try GenerationSchema(
                root: DynamicGenerationSchema(name: "Filing", properties: [
                    .init(
                        name: "category",
                        description: "The one category the entry clearly belongs to, or \(none)",
                        schema: DynamicGenerationSchema(name: "Category", anyOf: categoryNames + [none])
                    ),
                    .init(
                        name: "title",
                        description: "The entry without words that only say which category or list it goes in",
                        schema: DynamicGenerationSchema(type: String.self)
                    ),
                ]),
                dependencies: []
            )
            let prompt = "Entry: \(title)\nCategories:\n" + categoryNames.map { "- \($0)" }.joined(separator: "\n")
            let response = try await session.respond(
                to: prompt,
                schema: schema,
                includeSchemaInPrompt: true,
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 120)
            )
            let category = try response.content.value(String.self, forProperty: "category")
            let cleaned = try response.content.value(String.self, forProperty: "title")
            return Answer(categoryName: category == none ? nil : category, title: cleaned)
        } catch is CancellationError {
            return nil
        } catch {
            log.error("Category guess failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// For Siri: the checked suggestion, or nil after `timeout`.
    static func suggestion(for title: String, in categories: [CategorySnapshot], timeout: Duration) async -> CategorySuggestion? {
        let names = categories.map(\.name)
        let reply = await withTaskGroup(of: Answer?.self) { group in
            group.addTask { await Self.answer(title: title, categoryNames: names) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let reply else { return nil }
        return CategorySuggestion.checked(categoryName: reply.categoryName, suggestedTitle: reply.title, for: title, categories: categories)
    }

    /// Tried on a Mac against labelled entries (2026-10-06): asking for
    /// "obviously belongs" and saying none is fine cut the wild guesses
    /// ("think about life" → Health) from 6 in 18 to 2 in 18.
    private static func instructions(none: String) -> String {
        """
        You file one entry of a personal to-do list into one of the user's categories, or into none. \
        Choose a category only when the entry obviously belongs to it: the entry names it, or names something that is plainly part of it \
        (a city in that country, a colleague or a meeting for work, a food for groceries, a relative for family). \
        If you would have to guess, answer \(none). Answering \(none) is common and fine. \
        Also give the entry's title: the entry itself, minus any words that only say which category or list it goes in. \
        Keep the user's own words, spelling and language. Never translate, rephrase or add words.
        """
    }

    /// "none", unless a category is called that.
    private static func noneChoice(avoiding names: [String]) -> String {
        var none = "none"
        while names.contains(where: { $0.caseInsensitiveCompare(none) == .orderedSame }) { none = "(\(none))" }
        return none
    }

    /// Whether the model supports the text's language; unsure means try.
    private static func speaks(_ text: String) -> Bool {
        guard let language = NLLanguageRecognizer.dominantLanguage(for: text) else { return true }
        return SystemLanguageModel.default.supportsLocale(Locale(identifier: language.rawValue))
    }
}

extension View {
    /// Asks the model for a category once typing pauses, while nothing
    /// else picks one (`request`). A newer request cancels the older one;
    /// typing and saving never wait for it — a save before the answer saves
    /// what's shown.
    func suggestsCategory(for composer: QuickAddComposer, request: QuickAddComposer.SuggestionRequest?) -> some View {
        task(id: request) {
            guard let request else {
                composer.clearSuggestion()
                return
            }
            guard CategoryGuesser.isAvailable else { return }
            let answer = await CategoryGuesser.answer(title: request.title, categoryNames: request.categoryNames, after: .milliseconds(400))
            guard !Task.isCancelled else { return }
            composer.applySuggestion(categoryName: answer?.categoryName, title: answer?.title, for: request)
        }
    }
}
