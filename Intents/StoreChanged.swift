import WidgetKit

/// The one "the store changed" signal of a process (spec §4.3): reloads the
/// widgets and the Control, then runs whatever else the process asked to
/// hear about (in the app, e.g., rescheduling notifications).
///
/// Writers outside the app's screens — intents, background refresh — call
/// `notify()` themselves, before the system may suspend them. In the app,
/// its own saves, iCloud imports and other processes' writes arrive here
/// through `StoreChangeRelay`.
@MainActor
enum StoreChanged {
    private static var observers: [@MainActor () async -> Void] = []

    static func observe(_ observer: @escaping @MainActor () async -> Void) {
        observers.append(observer)
    }

    static func notify() async {
        WidgetCenter.shared.reloadAllTimelines()
        // A renamed or deleted category changes the Control's label.
        ControlCenter.shared.reloadControls(ofKind: WidgetKinds.addControl)
        for observer in observers { await observer() }
    }
}

/// Kinds shared by the widget extension and the app's reloads.
enum WidgetKinds {
    static let agenda = "Agenda"
    static let addControl = "com.noamchuri.scribe.add"
}
