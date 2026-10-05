import AppIntents
import ScribeCore
import os

private let log = Logger(subsystem: "com.noamchuri.scribe", category: "intents")

/// What Siri, Shortcuts and widgets say when an intent can't finish.
enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case storeUnavailable
    case noCategories
    case store(StoreError)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .storeUnavailable: "Scribe can’t open your notes right now. Open the app to try again."
        case .noCategories: "Add a category in Scribe first."
        case .store(let error): "\(error.localizedDescription)"
        }
    }
}

extension SharedStore {
    /// `open()` for intents: a failure becomes a sentence Siri can say.
    static func openForIntent() throws -> SwiftDataItemStore {
        do {
            return try open()
        } catch {
            log.error("Store failed to open in \(ProcessInfo.processInfo.processName, privacy: .public): \(String(describing: error), privacy: .public)")
            throw IntentError.storeUnavailable
        }
    }
}
