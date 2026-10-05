import ScribeCore
import SwiftUI

/// Inbox, then categories with emoji, open count and color; inline add,
/// edit, reorder and delete with Undo (spec §9.2).
struct CategoriesView: View {
    let store: any ItemStore

    @Environment(AppRouter.self) private var router
    @Environment(UndoCenter.self) private var undo
    @State private var editingID: UUID?
    @State private var isAdding = false
    @State private var newName = ""
    @State private var addError: String?
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        List {
            NavigationLink(value: AppRouter.Destination.inbox) {
                HStack {
                    Label("Inbox", systemImage: "tray")
                    Spacer()
                    OpenCount(store.items(.inbox).filter { !$0.isDone }.count)
                }
            }
            .accessibilityIdentifier("inboxRow")

            Section("Categories") {
                ForEach(store.categories) { category in
                    if editingID == category.id {
                        CategoryEditRow(store: store, category: category) { editingID = nil }
                    } else {
                        NavigationLink(value: AppRouter.Destination.category(category.id)) {
                            HStack(spacing: 10) {
                                Circle().fill(category.color).frame(width: 10, height: 10)
                                Text(category.displayName)
                                Spacer()
                                OpenCount(category.openCount)
                            }
                        }
                        .accessibilityIdentifier("category-\(category.name)")
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(category) }
                            Button("Edit", systemImage: "pencil") { editingID = category.id }
                                .tint(.gray)
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editingID = category.id }
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(category) }
                        }
                    }
                }
                .onMove { source, destination in
                    router.perform { try store.moveCategories(fromOffsets: source, toOffset: destination) }
                }
                if isAdding {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("New category", text: $newName)
                            .focused($addFieldFocused)
                            .submitLabel(.done)
                            .onSubmit(add)
                            .onChange(of: newName) { addError = nil }
                            .accessibilityIdentifier("newCategoryField")
                        InlineError(message: addError)
                    }
                }
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Category", systemImage: "plus") {
                    isAdding = true
                    addFieldFocused = true
                }
            }
        }
    }

    private func add() {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else {
            isAdding = false
            return
        }
        do {
            let color = CategoryPalette.suggestedColorName(avoiding: store.categories.map(\.colorName))
            try store.addCategory(CategoryDraft(name: newName, colorName: color))
            newName = ""
            isAdding = false
        } catch {
            // Spec §13: say why in place and keep the field open to fix it.
            addError = error.localizedDescription
            addFieldFocused = true
        }
    }

    private func delete(_ category: CategorySnapshot) {
        router.perform {
            let deletion = try store.deleteCategory(category.id)
            undo.offer("Deleted “\(category.name)”") { try store.restoreCategory(deletion) }
        }
    }
}

/// A store refusal shown under the field that caused it (spec §13).
private struct InlineError: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityIdentifier("inlineError")
        }
    }
}

/// A row's open-item count, before the chevron; nothing when zero.
private struct OpenCount: View {
    let count: Int
    init(_ count: Int) { self.count = count }

    var body: some View {
        if count > 0 {
            Text(count, format: .number)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

/// Inline editor for a category's emoji, name and color.
private struct CategoryEditRow: View {
    let store: any ItemStore
    let category: CategorySnapshot
    let done: () -> Void

    @Environment(AppRouter.self) private var router
    @State private var emoji: String
    @State private var name: String
    @State private var colorName: String
    @State private var error: String?

    init(store: any ItemStore, category: CategorySnapshot, done: @escaping () -> Void) {
        self.store = store
        self.category = category
        self.done = done
        _emoji = State(initialValue: category.emoji)
        _name = State(initialValue: category.name)
        _colorName = State(initialValue: category.colorName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("🙂", text: $emoji)
                    .frame(width: 36)
                    .onChange(of: emoji) { _, value in emoji = String(value.suffix(1)) }
                TextField("Name", text: $name)
                    .onSubmit(save)
                    .onChange(of: name) { error = nil }
            }
            InlineError(message: error)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CategoryPalette.colorNames, id: \.self) { color in
                        let sample = CategorySnapshot(name: "", colorName: color)
                        Circle()
                            .fill(sample.color)
                            .frame(width: 26, height: 26)
                            .overlay { if color == colorName { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                            .onTapGesture { colorName = color }
                            .accessibilityLabel(color)
                    }
                }
                .padding(.vertical, 2)
            }
            HStack {
                Button("Cancel", action: done)
                Spacer()
                Button("Save", action: save).buttonStyle(.glassProminent)
            }
        }
    }

    private func save() {
        do {
            try store.updateCategory(category.id) {
                $0.emoji = emoji
                $0.name = name
                $0.colorName = colorName
            }
            done()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
