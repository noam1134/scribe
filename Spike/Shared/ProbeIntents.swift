import AppIntents

/// Phase 0 only. Used by the widget button, the Control and Shortcuts/Siri.
struct AddProbeNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Probe Note"

    @Parameter(title: "Source", default: "shortcut")
    var source: String

    init() {}

    init(source: String) {
        self.source = source
    }

    func perform() async throws -> some IntentResult {
        try ProbeStore.add(source: source)
        return .result()
    }
}
