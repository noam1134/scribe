import ScribeCore
import SwiftUI

/// Overdue tasks, then today and the next six days (spec §6).
struct UpcomingView: View {
    let store: any ItemStore

    var body: some View {
        let now = Date()
        let agenda = store.agenda(.all, now: now)
        let categories = store.categories
        let labels = DueLabels()
        let today = LocalDay(now, calendar: labels.calendar)
        List {
            if !agenda.overdue.isEmpty {
                Section {
                    ForEach(agenda.overdue) { ItemRow(store: store, item: $0, categories: categories) }
                } header: {
                    Text("Overdue").foregroundStyle(.red)
                }
            }
            ForEach(agenda.days, id: \.day) { day in
                Section(labels.dayTitle(day.day, today: today)) {
                    ForEach(day.items) { ItemRow(store: store, item: $0, categories: categories, showsDay: false) }
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
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
    }
}
