import ScribeCore
import SwiftUI

/// Temporary Phase 1 screen: proves the real schema opens with CloudKit on
/// and that records reach the CloudKit development environment. Phase 2
/// replaces it with the real UI.
struct StoreSmokeView: View {
    let store: SwiftDataItemStore
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Add sample item") { addSample() }
                    Button("Refresh") { store.refresh() }
                    Button("Delete sample data", role: .destructive) { deleteSamples() }
                    if let errorText {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
                Section("Categories: \(store.categories.count)") {
                    ForEach(store.categories) { Text("\($0.emoji) \($0.name) (\($0.openCount))") }
                }
                Section("Inbox") {
                    ForEach(store.items(.inbox)) { Text($0.title) }
                }
            }
            .navigationTitle("Scribe store check")
        }
    }

    private func deleteSamples() {
        do {
            for item in store.items(.inbox) where item.title.hasPrefix("Sample ") {
                try store.deleteItem(item.id)
            }
            for category in store.categories where category.name == "Smoke test" {
                try store.deleteCategory(category.id)
            }
            errorText = nil
        } catch {
            errorText = "\(error)"
        }
    }

    private func addSample() {
        do {
            if store.categories.isEmpty {
                try store.addCategory(CategoryDraft(name: "Smoke test", emoji: "🧪", colorName: "gray"))
            }
            try store.addItem(ItemDraft(title: "Sample \(Date.now.formatted(date: .omitted, time: .standard))"))
            errorText = nil
        } catch {
            errorText = "\(error)"
        }
    }
}
