import ScribeCore
import SwiftUI

/// Overdue tasks, then today and the next six days (spec §6).
struct UpcomingView: View {
    let store: any ItemStore

    /// The row swiped open to show Done or Delete.
    @State private var swipedItemID: UUID?

    var body: some View {
        let now = Date()
        let agenda = store.agenda(.all, now: now)
        let categories = store.categories
        let labels = DueLabels()
        let today = LocalDay(now, calendar: labels.calendar)
        CardScroll {
            if !agenda.overdue.isEmpty {
                CardSection {
                    Text("Overdue").foregroundStyle(.red)
                } content: {
                    ItemCardRows(
                        store: store, items: agenda.overdue, categories: categories,
                        offersUndoOnComplete: true, swiped: $swipedItemID
                    )
                }
            }
            ForEach(agenda.days, id: \.day) { day in
                CardSection {
                    Text(labels.dayTitle(day.day, today: today)).foregroundStyle(.secondary)
                } content: {
                    ItemCardRows(
                        store: store, items: day.items, categories: categories, showsDay: false,
                        offersUndoOnComplete: true, swiped: $swipedItemID
                    )
                }
            }
        }
        .overlay {
            if agenda.isEmpty {
                ContentUnavailableView(
                    "Nothing coming up",
                    systemImage: "calendar",
                    description: Text("Items with a date in the next 7 days show up here.")
                )
            }
        }
        .navigationTitle("Upcoming")
        .navigationBarTitleDisplayMode(.inline)
    }
}
