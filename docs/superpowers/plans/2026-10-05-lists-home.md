# Scribe — Lists Home Tab Implementation Plan

**Goal:** The iPhone opens on **Lists**: every category on one screen as a collapsible section (open tasks, then memos; done items on request), replacing the Categories tab and the per-category screen. Taps outside a text field close the keyboard. The quick-add composer gains a Notes field. Approved by the author on 2026-10-05; spec §20.

**Architecture:** The grouping, visibility and per-device collapse state are pure Core types in `Presentation/ListSections.swift` with Swift Testing tests (`ListSections.make`, `ListSectionID`, `ListsPreferences`). `QuickAddComposer` gains `notes`. The app gets one new screen, `App/iOS/ListsView.swift`, that reads `store.items(.all)` + `store.categories` once per render, and one UIKit hook, `App/iOS/KeyboardDismissal.swift`: a window tap recognizer that never cancels touches, ignores touches inside text inputs, and ends editing. `AppRouter` owns the Lists state that links change (tab, collapse state, Show Completed, Edit mode, scroll target) and persists the per-device part to `UserDefaults` (a throwaway suite under `-uiTesting`). `CategoriesView` and `CategoryDetailView` go away; their category rows and inline editor move into `ListsView`.

**Spec:** §9.2, §13, §19; new §20. **Not in this work:** Settings (Phase 6 builds `SettingsButton` in parallel — the Lists toolbar keeps a marked spot for it), the Mac app, Upcoming, Search (except scroll-to-dismiss), widgets.

## Global Constraints

Phase 2's constraints apply (Swift 6, iOS/macOS 26, ScribeCore imports only Foundation/Observation/SwiftData, no model changes, zero warnings, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`). Additionally:

- Branch `lists-home` in `.worktrees/lists-home`, from `main` b29c8fa. Simulator "Scribe P4", id `FBFE7176-C36B-470A-9ED0-D2E10AE74C27` (derived data `build/dd-sim`).
- Links stay exactly `scribe://item/<id>`, `scribe://add[?category=]`, `scribe://upcoming`; notifications, widgets and the Control reach the app through `StoreLoader.pendingLink` → `AppRouter.open`.
- Collapse state and Show Completed are per device (`UserDefaults`), never synced, never in the model.

## File Map

| File | Responsibility | Task |
|---|---|---|
| `Core/Sources/ScribeCore/Presentation/ListSections.swift` | `ListSectionID`, `ListSection`, `ListSections.make(items:categories:showsCompleted:keeping:)`, `sectionID(for:categories:)` | 1 |
| `Core/Sources/ScribeCore/Presentation/ListsPreferences.swift` | Collapsed sections + Show Completed; `UserDefaults` encoding | 1 |
| `Core/Sources/ScribeCore/Presentation/QuickAddComposer.swift` | `notes` → item body; cleared on reset | 2 |
| `App/iOS/AppRouter.swift` | Tabs Lists · Upcoming · Search; Lists state; item links open Lists | 3 |
| `App/iOS/ListsView.swift` (new) | Sections, headers, Edit mode, inline category add/edit/delete | 3 |
| `App/iOS/RootView.swift`, `QuickAddBar.swift` | Tab wiring; the capsule preselects nothing | 3 |
| `App/iOS/CategoriesView.swift`, `CategoryDetailView.swift` | Deleted | 3 |
| `App/Shared/DemoData.swift` (moved from `App/macOS/`) | `-uiTesting -demoData` seed for both platforms; two items with fixed ids for link tests | 3 |
| `App/iOS/KeyboardDismissal.swift` (new), `UpcomingView.swift`, `SearchView.swift` | Tap-outside and scroll-to-dismiss | 4 |
| `App/iOS/QuickAddSheet.swift`, `App/Shared/ItemEditor.swift` | Notes field, growing detent; `notesField` identifier | 5 |
| `UITests/ScribeUITests.swift`, `UITests/NotificationUITests.swift` | Tests follow the new tabs; new Lists, keyboard and notes tests | 3–5 |
| `UITests/ListsScreenshots.swift` (new, opt-in) | Walks the Lists states and attaches screenshots | 6 |
| Spec §9.2/§20, `README.md`, `docs/backlog.md` | Docs | 6 |

## Tasks

### Task 1: Lists sections and preferences (Core, TDD)

```swift
public enum ListSectionID: Hashable, Sendable { case inbox, category(UUID) }   // + storageKey / init?(storageKey:)
public struct ListSection: Identifiable, Equatable, Sendable {
    public let id: ListSectionID
    public let category: CategorySnapshot?   // nil: the Inbox
    public let items: [ItemSnapshot]         // open tasks, memos, then the visible done items
    public let openCount: Int                // open tasks + memos
}
public enum ListSections {
    public static func make(items:categories:showsCompleted:keeping:) -> [ListSection]
    public static func sectionID(for item: ItemSnapshot, categories: [CategorySnapshot]) -> ListSectionID
}
public struct ListsPreferences: Equatable, Sendable {
    public var showsCompleted: Bool
    public func isCollapsed(_:) -> Bool; mutating toggle(_:), expand(_:)
    public init(from: UserDefaults); public func save(to: UserDefaults)   // keys lists.collapsed, lists.showsCompleted
}
```
Tests: categories in sort order, empty ones included; open tasks then memos in store order; done hidden unless Show Completed, then last and most recent first; Inbox first and only while it shows something; an item of an unknown category lands in the Inbox; the kept (edited) done item stays visible; open counts; preferences default (expanded, done hidden), toggle, expand, round trip, malformed stored values ignored.

### Task 2: Notes in the composer (Core, TDD)

`QuickAddComposer.notes` (trimmed of surrounding whitespace, saved as `ItemDraft.body`, kept when save returns nil, cleared by `reset()`). Tests: task with notes, memo with notes, trimmed, reset, no title keeps notes.

### Task 3: Lists screen, router, links

- `AppRouter.Tab` = `.lists` (default), `.upcoming`, `.search`. Removed: `Destination`, `categoriesPath`, `visibleCategoryID`. Added: `lists: ListsPreferences` (saved on change), `isEditingLists`, `listsScrollTarget`.
- `open(.item(id))`: close the composer, show Lists, leave Edit mode, expand the item's section, open its editor, scroll to it. A done item stays visible while its editor is open (the `keeping:` rule), whatever Show Completed says.
- `ListsView`: per section a header (dot or tray, emoji + name, open count, chevron, **+** → `compose(in:)`; tap toggles; long-press → a Rename / Delete dialog, Delete with Undo), then `ItemRow`s, or a faint "No items". Toolbar: Edit/Done (leading, Settings slot before it), ⋯ with a Show Completed toggle, **+** for an inline category field (duplicate name explained inline; an empty field closes when it loses focus). Edit mode lists only category rows: drag to reorder, tap or Rename to edit inline, delete with Undo.
- UI tests: tabs; section collapse; section **+** preselects; Show Completed; Edit mode; delete + undo; item link into a collapsed section; link to a done item. Existing tests that meant Upcoming tap Upcoming first.

### Task 4: Keyboard dismissal

`View.closesKeyboardOnTapOutside()` on the root installs one `UITapGestureRecognizer` per window: `cancelsTouchesInView = false`, recognizes alongside every other gesture, ignores touches inside a `UITextField`/`UITextView` (so another field takes focus without the keyboard dropping), and calls `endEditing(true)`. Lists, Upcoming and Search use `.scrollDismissesKeyboard(.immediately)`. UI test: in the composer, Notes takes focus in one tap, an empty-area tap closes the keyboard, a chip works on the first tap; in Lists, a tap on empty space closes the keyboard of an inline editor.

### Task 5: Notes in the sheet

Under the main line, aligned with its text: `TextField("Notes", axis: .vertical)` (callout, its own text direction). Focusing it moves the sheet from its compact height to `.large`; Return in the main line still saves; Add saves title + notes. UI test: add with notes → the item's editor shows them.

### Task 6: Screenshots and docs

Opt-in `ListsScreenshots` (`TEST_RUNNER_SCRIBE_SCREENSHOTS=<folder>`) saves and attaches: Lists, collapsed, Show Completed, inline editor, header long press, inline rename, Edit mode, composer, composer with Notes, keyboard closed. Spec §20 + §9.2 pointers, README feature line, backlog.

## Decisions

1. **Done item from a link:** the item stays visible (struck through, at the end of its section) while its editor is open — the general rule "the row being edited never disappears", which also covers ticking an item while editing it. Show Completed is not switched on; closing the editor hides it again.
2. **Ticking a task with Show Completed off** hides it at once, as on Upcoming (no linger, no Undo toast; Show Completed brings it back).
3. **Inbox** shows while it has something visible: open items, or done ones when Show Completed is on (or the edited one). No **+**, no Rename/Delete, not in Edit mode; it collapses like the others.
4. **Collapse state** is stored as the set of collapsed section ids, so new categories start expanded; ids of deleted categories stay (a restored category keeps its state). Collapsing the section that holds the open editor closes the editor.
5. **Header long press** opens a confirmation dialog with Rename and Delete — SwiftUI only gives list rows a context menu (tried: a menu on the header, and on its button, never opens). Rename opens the inline category editor as the first row of that section (shown even when collapsed); Edit mode opens the same editor in place of the category row.
6. **Keyboard:** any tap outside a text input closes the keyboard and still does what it would have done (buttons and chips work on the first tap); a tap on another text field moves focus without the keyboard dropping. Scrolling any list closes it.
7. **Composer detents:** compact height (fits the Notes line) and `.large`; focusing Notes switches to `.large`; the sheet stays large until dragged down.
8. **Item links** always land in Lists (not Upcoming), leave Edit mode, and expand only the item's section.
9. **The quick-add capsule** preselects nothing on any tab; a section's **+** preselects its category (§19 still requires one).
10. **Mac demo data** moved to `App/Shared` unchanged except two items seeded through `restoreItem` with fixed ids (for link UI tests); the Mac-only launch state stays `#if os(macOS)`.
