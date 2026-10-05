import AppIntents
import ScribeCore
import SwiftUI
import WidgetKit

/// The agenda widget (spec §10): what's coming up, from every category or
/// one, on the iPhone home and lock screens and the Mac desktop.
struct AgendaWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKinds.agenda, intent: AgendaWidgetIntent.self, provider: AgendaProvider()) { entry in
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

struct AgendaWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Upcoming"
    static let description: IntentDescription? = IntentDescription("What’s coming up, from every category or just one.")

    /// A deleted category arrives as `CategoryEntity.deleted`, and the
    /// widget says so (spec §10.1 scope; no silent switch to all).
    @Parameter(title: "Category", description: "Leave empty to show every category.")
    var category: CategoryEntity?

    init() {}
}

struct AgendaEntry: TimelineEntry {
    let entry: WidgetEntry

    var date: Date { entry.date }
}

struct AgendaProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AgendaEntry {
        AgendaEntry(entry: WidgetSamples.entry())
    }

    func snapshot(for configuration: AgendaWidgetIntent, in context: Context) async -> AgendaEntry {
        // The widget gallery shows an example rather than an empty list.
        if context.isPreview { return placeholder(in: context) }
        let categoryID = configuration.category?.id
        let plan = await MainActor.run { Self.plan(categoryID: categoryID, now: Date()) }
        return AgendaEntry(entry: plan.entries[0])
    }

    func timeline(for configuration: AgendaWidgetIntent, in context: Context) async -> Timeline<AgendaEntry> {
        let categoryID = configuration.category?.id
        let plan = await MainActor.run { Self.plan(categoryID: categoryID, now: Date()) }
        return Timeline(entries: plan.entries.map(AgendaEntry.init), policy: .after(plan.refreshAt))
    }

    @MainActor
    private static func plan(categoryID: UUID?, now: Date) -> WidgetTimeline {
        let builder = WidgetEntryBuilder()
        guard let store = try? SharedStore.open() else { return builder.unavailable(now: now) }
        return builder.timeline(
            items: store.datedOpenItems(),
            categories: store.categories,
            categoryID: categoryID,
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
