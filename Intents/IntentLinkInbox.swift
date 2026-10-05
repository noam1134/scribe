import Observation
import ScribeCore

/// Where an intent that brings the app forward (`OpenQuickAddIntent`)
/// leaves the screen to show. `ScribeApp` moves it into
/// `StoreLoader.pendingLink`, the path every `scribe://` link takes.
@MainActor
@Observable
final class IntentLinkInbox {
    static let shared = IntentLinkInbox()

    var link: DeepLink?
}
