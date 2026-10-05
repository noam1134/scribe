import WidgetKit

/// The one "the store changed" signal of a process (spec §4.3).
///
/// Writers outside the app's screens — intents, background refresh — call
/// `notify()` before they return (the system may suspend them right after):
/// it reloads the widgets and the Control, then awaits every observer (in
/// the app: notification rescheduling).
///
/// The app's own saves, iCloud imports and other processes' writes only
/// need `reloadWidgets()` (sent by `StoreChangeRelay`): the notification
/// scheduler already watches the store for those, so running observers
/// again would plan twice.
@MainActor
enum StoreChanged {
    private static var observers: [@MainActor () async -> Void] = []

    static func observe(_ observer: @escaping @MainActor () async -> Void) {
        observers.append(observer)
    }

    static func notify() async {
        reloadWidgets()
        for observer in observers { await observer() }
    }

    static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
        // A renamed or deleted category changes the Control's label.
        ControlCenter.shared.reloadControls(ofKind: WidgetKinds.addControl)
    }
}

/// Kinds shared by the widget extension and the app's reloads.
enum WidgetKinds {
    static let agenda = "Agenda"
    static let addControl = "com.noamchuri.scribe.add"
}
