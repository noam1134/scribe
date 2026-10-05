import ScribeCore
import SwiftUI
import WidgetKit

/// The agenda widget (spec §10): what's coming up in every category, on
/// the iPhone home and lock screens and the Mac desktop.
///
/// Static, not intent-configured: on the iPhone the system handed the
/// configured widget no intent at all ("Intent configuration is required but
/// was not provided", CHSErrorDomain 1103), so it never left the
/// placeholder. A static widget needs none, and widgets already on the home
/// screen keep their kind and start working.
struct AgendaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.agenda, provider: AgendaProvider()) { entry in
            AgendaWidgetView(entry: entry.entry)
        }
        .configurationDisplayName("Upcoming")
        .description("What’s coming up in the next 7 days.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular]
        #else
        [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }
}

struct AgendaEntry: TimelineEntry {
    let entry: WidgetEntry

    var date: Date { entry.date }
}

struct AgendaProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgendaEntry {
        AgendaEntry(entry: WidgetSamples.entry())
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (AgendaEntry) -> Void) {
        // The widget gallery shows an example rather than an empty list.
        if context.isPreview { return completion(placeholder(in: context)) }
        Task { @MainActor in
            completion(AgendaEntry(entry: Self.plan(now: Date()).entries[0]))
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<AgendaEntry>) -> Void) {
        Task { @MainActor in
            let plan = Self.plan(now: Date())
            completion(Timeline(entries: plan.entries.map(AgendaEntry.init), policy: .after(plan.refreshAt)))
        }
    }

    @MainActor
    private static func plan(now: Date) -> WidgetTimeline {
        let builder = WidgetEntryBuilder()
        guard let store = try? SharedStore.open() else { return builder.unavailable(now: now) }
        return builder.timeline(
            items: store.datedOpenItems(),
            categories: store.categories,
            categoryID: nil,
            now: now,
            freshAt: FreshnessStamp.date
        )
    }
}

/// Example content for the gallery and placeholders.
enum WidgetSamples {
    static func entry(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> WidgetEntry {
        let trip = CategorySnapshot(name: "Thailand", emoji: "🇹🇭", colorName: "teal", sortIndex: 0)
        let work = CategorySnapshot(name: "Work", colorName: "orange", sortIndex: 1)
        let today = LocalDay(now, calendar: calendar)
        let items = [
            ItemSnapshot(title: "Book flights", categoryID: trip.id, due: DueDate(day: today)),
            ItemSnapshot(title: "Call the bank", categoryID: work.id, due: DueDate(day: today, minute: 23 * 60 + 30)),
            ItemSnapshot(title: "Passport photos", kind: .memo, categoryID: trip.id, due: DueDate(day: today.adding(days: 1, calendar: calendar))),
            ItemSnapshot(title: "Send the report", categoryID: work.id, due: DueDate(day: today.adding(days: 2, calendar: calendar))),
        ]
        let plan = WidgetEntryBuilder(calendar: calendar).timeline(items: items, categories: [trip, work], categoryID: nil, now: now, freshAt: nil)
        return plan.entries[0]
    }
}
