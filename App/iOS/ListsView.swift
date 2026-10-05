import ScribeCore
import SwiftUI

/// The iPhone's home (spec §20): every category as a collapsible section —
/// open tasks, then memos, then done items when Show Completed is on — with
/// the Inbox first while it holds something. Edit shows only the category
/// rows, to reorder, edit and delete them.
struct ListsView: View {
    let store: any ItemStore

    @Environment(AppRouter.self) private var router
    @Environment(UndoCenter.self) private var undo
    /// The category showing its inline editor.
    @State private var editingCategoryID: UUID?
    @State private var isAdding = false
    @State private var newName = ""
    @State private var addError: String?
    @FocusState private var addFieldFocused: Bool

    private static let addRowID = "addCategory"

    var body: some View {
        let categories = store.categories
        let sections = ListSections.make(
            items: store.items(.all),
            categories: categories,
            showsCompleted: router.lists.showsCompleted,
            keeping: router.expandedItemID
        )
        ScrollViewReader { proxy in
            List {
                if router.isEditingLists {
                    Section {
                        categoryRows(categories)
                        if isAdding { addRow }
                    }
                } else {
                    ForEach(sections) { section in
                        sectionView(section, categories: categories)
                    }
                    if isAdding {
                        Section { addRow }
                    }
                }
            }
            .environment(\.editMode, .constant(router.isEditingLists ? .active : .inactive))
            .listSectionSpacing(.compact)
            .scrollDismissesKeyboard(.immediately)
            .overlay {
                if sections.isEmpty && !isAdding {
                    ContentUnavailableView(
                        "No lists yet",
                        systemImage: "list.bullet",
                        description: Text("Add a category with +, or type #name in the bar below.")
                    )
                }
            }
            .onChange(of: isAdding) { _, adding in
                if adding { withAnimation(.snappy) { proxy.scrollTo(Self.addRowID, anchor: .bottom) } }
            }
            .task(id: router.listsScrollTarget) {
                guard let id = router.listsScrollTarget else { return }
                // After its section has opened; again once the rows have
                // settled, since a scroll during the insertion can fall short.
                for delay in [200, 300] {
                    guard (try? await Task.sleep(for: .milliseconds(delay))) != nil else { return }
                    withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
                }
                router.listsScrollTarget = nil
            }
        }
        .navigationTitle("Lists")
        .toolbar { toolbar }
        .onChange(of: editedSectionID(in: sections)) { _, id in
            // The row being edited moved (its category chip): follow it.
            if let id, router.lists.isCollapsed(id) {
                withAnimation(.snappy) { router.lists.expand(id) }
            }
        }
        .onChange(of: addFieldFocused) { _, focused in
            // Tapping away from an empty field puts it away.
            if !focused && newName.trimmingCharacters(in: .whitespaces).isEmpty {
                isAdding = false
                addError = nil
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func sectionView(_ section: ListSection, categories: [CategorySnapshot]) -> some View {
        let isCollapsed = router.lists.isCollapsed(section.id)
        Section {
            if let category = section.category, editingCategoryID == category.id {
                CategoryEditRow(store: store, category: category) { editingCategoryID = nil }
            }
            if !isCollapsed {
                if section.items.isEmpty {
                    Text("No items")
                        .foregroundStyle(.tertiary)
                }
                ForEach(section.items) { item in
                    ItemRow(
                        store: store, item: item, categories: categories, showsCategory: false,
                        offersUndoOnComplete: !router.lists.showsCompleted
                    )
                    .id(item.id)
                }
            }
        } header: {
            ListSectionHeader(
                section: section,
                isCollapsed: isCollapsed,
                toggle: { toggle(section) },
                add: {
                    router.lists.expand(section.id)
                    router.compose(in: section.category?.id)
                },
                rename: { editingCategoryID = section.category?.id },
                delete: { section.category.map(delete) }
            )
        }
    }

    private func editedSectionID(in sections: [ListSection]) -> ListSectionID? {
        guard let id = router.expandedItemID else { return nil }
        return sections.first { $0.items.contains { $0.id == id } }?.id
    }

    private func toggle(_ section: ListSection) {
        withAnimation(.snappy) {
            // The open editor's row is about to go: close it with its section.
            if !router.lists.isCollapsed(section.id), section.items.contains(where: { $0.id == router.expandedItemID }) {
                router.expandedItemID = nil
            }
            router.lists.toggle(section.id)
        }
    }

    // MARK: Edit mode

    private func categoryRows(_ categories: [CategorySnapshot]) -> some View {
        ForEach(categories) { category in
            if editingCategoryID == category.id {
                CategoryEditRow(store: store, category: category) { editingCategoryID = nil }
                    .moveDisabled(true)
                    .deleteDisabled(true)
            } else {
                Button { editingCategoryID = category.id } label: {
                    HStack(spacing: 10) {
                        Circle().fill(category.color).frame(width: 10, height: 10)
                        // Colors, not `.primary`: in a button that is the tint.
                        Text(category.displayName)
                            .foregroundStyle(Color.primary)
                        Spacer()
                        if category.openCount > 0 {
                            Text(category.openCount, format: .number)
                                .foregroundStyle(Color.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .accessibilityIdentifier("category-\(category.name)")
                .contextMenu {
                    Button("Edit", systemImage: "pencil") { editingCategoryID = category.id }
                    Button("Delete", systemImage: "trash", role: .destructive) { delete(category) }
                }
            }
        }
        .onMove { source, destination in
            router.perform { try store.moveCategories(fromOffsets: source, toOffset: destination) }
        }
        .onDelete { offsets in
            offsets.map { categories[$0] }.forEach(delete)
        }
    }

    private func toggleEditing() {
        withAnimation(.snappy) {
            router.isEditingLists.toggle()
            router.expandedItemID = nil
            editingCategoryID = nil
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            SettingsButton()
            Button(router.isEditingLists ? "Done" : "Edit", action: toggleEditing)
                .accessibilityIdentifier("editLists")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu("More", systemImage: "ellipsis") {
                Toggle("Show Completed", systemImage: "checkmark.circle", isOn: Bindable(router).lists.showsCompleted.animation(.snappy))
            }
            .disabled(router.isEditingLists)
            .accessibilityIdentifier("listsMenu")
            Button("Add Category", systemImage: "plus") {
                isAdding = true
                addFieldFocused = true
            }
        }
    }

    // MARK: Categories

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("New category", text: $newName)
                .focused($addFieldFocused)
                .submitLabel(.done)
                .onSubmit(add)
                .onChange(of: newName) { addError = nil }
                .accessibilityIdentifier("newCategoryField")
            InlineError(message: addError)
        }
        .id(Self.addRowID)
    }

    private func add() {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else {
            newName = ""
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
            if editingCategoryID == category.id { editingCategoryID = nil }
            undo.offer("Deleted “\(category.name)”") { try store.restoreCategory(deletion) }
        }
    }
}

/// A section's header: dot (or tray), name, open count and chevron — a tap
/// collapses or expands — then **+** to add into it. Pressing and holding a
/// category asks Rename or Delete, in a dialog pointing at the header. (A
/// context menu can't open on a list header — SwiftUI gives only rows one —
/// and a `Menu` label lost its tap on some headers.)
private struct ListSectionHeader: View {
    let section: ListSection
    let isCollapsed: Bool
    let toggle: () -> Void
    let add: () -> Void
    let rename: () -> Void
    let delete: () -> Void

    @State private var asksForAction = false

    private var name: String { section.category?.name ?? "Inbox" }

    var body: some View {
        HStack(spacing: 4) {
            label
                .onTapGesture(perform: toggle)
                .onLongPressGesture {
                    if section.category != nil { asksForAction = true }
                }
                .sensoryFeedback(.impact, trigger: asksForAction) { _, asks in asks }
                .confirmationDialog(section.category?.displayName ?? "", isPresented: $asksForAction, titleVisibility: .visible) {
                    Button("Rename", action: rename)
                    Button("Delete", role: .destructive, action: delete)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.default, toggle)
                .accessibilityActions {
                    if section.category != nil {
                        Button("Rename", action: rename)
                        Button("Delete", action: delete)
                    }
                }
                .accessibilityIdentifier("section-\(name)")
                .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
            if section.category == nil {
                // Keeps the Inbox's count and chevron in line with the others.
                Color.clear.frame(width: 44, height: 44)
            } else {
                Button("Add to \(name)", systemImage: "plus", action: add)
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("addTo-\(name)")
            }
        }
        .textCase(nil)
    }

    private var label: some View {
        HStack(spacing: 10) {
            marker
            // Color.primary: in a header `.primary` is the header's grey.
            Text(section.category?.displayName ?? "Inbox")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if section.openCount > 0 {
                Text(section.openCount, format: .number)
                    .foregroundStyle(Color.secondary)
                    .monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.secondary)
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
    }

    @ViewBuilder private var marker: some View {
        if let category = section.category {
            Circle().fill(category.color).frame(width: 10, height: 10)
        } else {
            Image(systemName: "tray")
                .foregroundStyle(Color.secondary)
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

/// Inline editor for a category's emoji, name and color.
private struct CategoryEditRow: View {
    let store: any ItemStore
    let category: CategorySnapshot
    let done: () -> Void

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
                TextField("", text: $emoji)
                    .frame(width: 36)
                    .overlay {
                        // An emoji placeholder draws as a missing-glyph box, so
                        // show a symbol until one is typed.
                        if emoji.isEmpty {
                            Image(systemName: "face.smiling")
                                .foregroundStyle(.tertiary)
                                .allowsHitTesting(false)
                        }
                    }
                    .onChange(of: emoji) { _, value in emoji = String(value.suffix(1)) }
                    .accessibilityLabel("Emoji")
                TextField("Name", text: $name)
                    .onSubmit(save)
                    .onChange(of: name) { error = nil }
                    .accessibilityIdentifier("categoryNameField")
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
                // Borderless: a plain button would take every tap in the row.
                Button("Cancel", action: done)
                    .buttonStyle(.borderless)
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
