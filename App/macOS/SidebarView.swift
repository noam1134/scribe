import ScribeCore
import SwiftUI

/// Upcoming, then the Categories section: the Inbox while something is in
/// it (spec §19) and the categories with color dot, emoji and open count.
/// Categories are added, edited (Return saves, Esc cancels) and deleted in
/// place and reordered by dragging; ⌘Z undoes a delete.
struct SidebarView: View {
    let store: any ItemStore

    @Environment(MacRouter.self) private var router
    @State private var editingID: UUID?
    @State private var isAdding = false
    @State private var newName = ""
    @State private var addError: String?
    @FocusState private var addFieldFocused: Bool

    private var selection: Binding<SidebarEntry?> {
        Binding(get: { router.sidebar }, set: { if let entry = $0 { router.sidebar = entry } })
    }

    var body: some View {
        let categories = store.categories
        let inbox = store.items(.inbox)
        List(selection: selection) {
            Label("Upcoming", systemImage: "calendar")
                .tag(SidebarEntry.upcoming)
            Section("Categories") {
                // Inside the section: a row appearing above it in the same
                // update as the categories trips AppKit's reentrancy warning
                // ("…will become an assert") when a first sync fills the list.
                if Sidebar.showsInbox(itemCount: inbox.count, selection: router.sidebar) {
                    Label("Inbox", systemImage: "tray")
                        .badge(inbox.filter { !$0.isDone }.count)
                        .tag(SidebarEntry.inbox)
                }
                ForEach(categories) { category in
                    if editingID == category.id {
                        SidebarCategoryEditor(store: store, category: category) { editingID = nil }
                    } else {
                        CategoryLabel(category: category)
                            .badge(category.openCount)
                            .tag(SidebarEntry.category(category.id))
                            .contextMenu {
                                Button("Edit Category…") { editingID = category.id }
                                Button("Delete Category", role: .destructive) { delete(category, from: categories) }
                            }
                    }
                }
                .onMove { source, destination in
                    router.perform { try store.moveCategories(fromOffsets: source, toOffset: destination) }
                }
                if isAdding {
                    addField
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                newName = ""
                addError = nil
                isAdding = true
            } label: {
                Label("New Category", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .onChange(of: categories.map(\.id)) {
            // Read the store again: this action can run after later changes
            // (an import or a batch of writes) than the value it reports.
            let valid = Sidebar.validated(router.sidebar, categoryIDs: store.categories.map(\.id))
            if valid != router.sidebar { router.sidebar = valid }
        }
    }

    private var addField: some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField("New category", text: $newName)
                .textFieldStyle(.plain)
                .focused($addFieldFocused)
                .onSubmit(add)
                .onExitCommand { isAdding = false }
                .onChange(of: newName) { addError = nil }
                .onChange(of: addFieldFocused) { _, focused in
                    if !focused && newName.trimmingCharacters(in: .whitespaces).isEmpty { isAdding = false }
                }
                .onAppear { addFieldFocused = true }
            if let addError {
                Text(addError)
                    .font(.caption)
                    .foregroundStyle(.red)
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
            let id = try store.addCategory(CategoryDraft(name: newName, colorName: color))
            newName = ""
            isAdding = false
            router.sidebar = .category(id)
        } catch {
            // Spec §13: say why in place and keep the field open to fix it.
            addError = error.localizedDescription
            addFieldFocused = true
        }
    }

    private func delete(_ category: CategorySnapshot, from categories: [CategorySnapshot]) {
        let wasSelected = router.sidebar == .category(category.id)
        router.perform {
            try router.undoable.deleteCategory(category.id)
            if wasSelected { router.sidebar = Sidebar.selection(afterDeleting: category.id, from: categories) }
        }
    }
}

/// Color dot, emoji and name.
private struct CategoryLabel: View {
    let category: CategorySnapshot

    var body: some View {
        Label {
            Text(category.displayName)
        } icon: {
            Circle()
                .fill(category.color)
                .frame(width: 9, height: 9)
        }
    }
}

/// Inline editor for a category's color, emoji and name. Return saves, Esc
/// cancels; a color applies at once.
private struct SidebarCategoryEditor: View {
    let store: any ItemStore
    let category: CategorySnapshot
    let done: () -> Void

    @State private var emoji: String
    @State private var name: String
    @State private var error: String?
    @FocusState private var nameFocused: Bool

    init(store: any ItemStore, category: CategorySnapshot, done: @escaping () -> Void) {
        self.store = store
        self.category = category
        self.done = done
        _emoji = State(initialValue: category.emoji)
        _name = State(initialValue: category.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                colorMenu
                TextField("", text: $emoji)
                    .textFieldStyle(.plain)
                    .frame(width: 22)
                    .overlay {
                        // An emoji placeholder draws as a missing-glyph box.
                        if emoji.isEmpty {
                            Image(systemName: "face.smiling")
                                .foregroundStyle(.tertiary)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .onChange(of: emoji) { _, value in emoji = String(value.suffix(1)) }
                    .onSubmit(save)
                    .accessibilityLabel("Emoji")
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .focused($nameFocused)
                    .onSubmit(save)
                    .onChange(of: name) { error = nil }
            }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onExitCommand(perform: done)
        .onAppear { nameFocused = true }
    }

    private var colorMenu: some View {
        Menu {
            ForEach(CategoryPalette.colorNames, id: \.self) { color in
                Toggle(isOn: Binding(get: { color == category.colorName }, set: { _ in setColor(color) })) {
                    Label {
                        Text(color.capitalized)
                    } icon: {
                        Self.swatch(CategorySnapshot(name: "", colorName: color).color)
                    }
                }
            }
        } label: {
            Circle()
                .fill(category.color)
                .frame(width: 11, height: 11)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Color")
    }

    /// Menu item images draw as monochrome templates; a palette-colored
    /// symbol keeps its color.
    private static func swatch(_ color: Color) -> Image {
        let symbol = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [NSColor(color)]))
        return symbol.map { Image(nsImage: $0) } ?? Image(systemName: "circle.fill")
    }

    private func setColor(_ color: String) {
        do {
            try store.updateCategory(category.id) { $0.colorName = color }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() {
        do {
            try store.updateCategory(category.id) {
                $0.emoji = emoji
                $0.name = name
            }
            done()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
