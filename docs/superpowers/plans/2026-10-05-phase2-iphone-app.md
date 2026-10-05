# Scribe Phase 2 — iPhone App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn ScribeCore into an iPhone app the author can use every day: a floating glass tab bar (Upcoming · Categories · Search), the quick-add capsule with live parse chips, inline row editing with glass chips, swipe actions with Undo, deep links, and a store-failure screen.

**Architecture:** Core gains a small `Presentation/` layer — pure, unit-tested types the views lean on (deep links, text direction, due labels, date presets, list grouping, the undo timer, the quick-add composer, error sentences) — plus three store/parser additions (category-delete undo, `onMove`-shaped reordering, day-part times). The app target splits its sources into `App/` (both platforms), `App/iOS/` and `App/macOS/` with XcodeGen `destinationFilters`; the Mac gets a placeholder screen until Phase 3. Views read snapshots from the `@Observable` store and write through `AppRouter.perform`, which turns a refused write into an alert (category-name problems show inline instead).

**Tech Stack:** Swift 6, SwiftUI with the iOS 26 Liquid Glass APIs (`Tab(value:role: .search)`, `.tabBarMinimizeBehavior`, `.tabViewBottomAccessory`, `.glassEffect`, `.buttonStyle(.glass/.glassProminent)` — all verified present in the Xcode 27 SDK), SwiftData + CloudKit through ScribeCore, Swift Testing, XCTest UI tests, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-05-scribe-v1-design.md` (§6 Agenda, §8 quick-add capsule + deep links, §9.1 design language, §9.2 iPhone, §9.4 bidirectional text, §12 data flow, §13 error handling, §15 testing, §18 amendments). Deferred inputs: `docs/backlog.md` → "Phase 2 (iPhone app)".

**Prerequisites:** `main` contains Phases 0–1 (commit `c39eb18` or later); `cd Core && swift test` is green. The author answered the backlog's product questions: bare hours stay 24-hour ("at 5" = 05:00); morning = 09:00, evening = 19:00; "בצהרים" is accepted as noon alongside "בצהריים".

**Not in this phase:** Settings screen and its toolbar button (Phase 6), widgets/Control/Siri (Phase 4), notifications (Phase 5), the Mac UI (Phase 3).

## Global Constraints

- Deployment targets iOS 26.0 / macOS 26.0; Swift 6 language mode; `Core/Package.swift` stays `swift-tools-version: 6.2`.
- `ScribeCore` imports only Foundation, Observation and SwiftData — never SwiftUI. Anything that needs SwiftUI lives under `App/`.
- No SwiftData model changes in this phase (`Item`, `Category` are untouched — the CloudKit schema stays as is).
- iPhone only: `TARGETED_DEVICE_FAMILY: "1"`. The macOS destination must keep building (it shows a placeholder).
- Liquid Glass (spec §9.1): standard components first; custom glass only for floating controls (composer chips, editor chips, undo toast). Lists and rows are never glass. Category color is an accent (dot, checkbox tint), never a row background. At most one prominent button per screen.
- Every title and notes view lays out in its own text's direction (spec §9.4) via `View.layoutDirection(of:)`.
- Store writes go through `AppRouter.perform` (alert titled "Couldn’t Save" showing `StoreError`'s sentence). Category name errors show inline under the field instead (spec §13). No `try!`, no `fatalError` in app code.
- Deep links are exactly `scribe://add[?category=<uuid>]`, `scribe://item/<uuid>`, `scribe://upcoming`.
- The undo toast lasts 5 seconds.
- UI tests launch with `-uiTesting` (in-memory store, no iCloud) and find controls by `accessibilityIdentifier`.
- Every command runs with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Core tests: `cd Core && swift test`. Run `xcodegen generate` after any `project.yml` change; the `.xcodeproj` is not committed, the generated `Info.plist` files are.
- Simulator for app tests: iPhone 17 Pro, iOS 26.3, id `E4ABB0FF-1B3F-43D4-A4AB-AA656FCEA434`. Derived data: `build/dd` (unsigned builds), `build/dd-sim` (simulator tests), `build/dd-signed` (device).
- Swift Testing argument tables are typed `static let` arrays; inside a `@MainActor` suite they are `nonisolated static let`.
- Builds finish with zero warnings from our code. (`appintentsmetadataprocessor … Metadata extraction skipped` is Xcode noise.)
- Work on branch `phase2-iphone`, created from `main`. The repo is public: never commit secrets.

## Review Focus

Inputs the spec implies but doesn't spell out, most likely to bite first. Each has a test in the task named.

1. **Dragging a category downward in Edit mode** must land where it was dropped — SwiftUI's `onMove` reports the destination as a pre-move index (Task 1 `moveCategoriesMatchesOnMove`).
2. **Undo after the user already re-filed some of the deleted category's items** must not steal them back, and a second Undo is a no-op (Task 1 `restoreLeavesItemsTheUserRefiled`, `deleteThenRestoreKeepsIdentityPositionAndItems`).
3. **A `#tag` that matches no category** keeps "#tag" in the saved title instead of silently dropping it, and the composer offers to create the category (Task 5 `unknownTagLeftAloneStaysInTheTitle`, `unknownTagCanBecomeACategory`).
4. **A duplicate category name** gets a plain sentence under the field, the field stays open, and no alert appears (Task 3 `StoreErrorMessagesTests`, Task 9 `testDuplicateCategoryNameIsExplainedInline`).
5. **A mangled `scribe://` link, or one pointing at something deleted on another device**, is ignored without a crash; a malformed category in an add link still opens the composer (Task 3 `DeepLinkTests.rejects`, `addIgnoresAMalformedCategory`).

## File Map

| File | Responsibility | Task |
|---|---|---|
| `Core/Sources/ScribeCore/Store/ItemStore.swift` | `CategoryDeletion`; protocol gains `moveCategories`, `restoreCategory`; `deleteCategory` returns what undo needs | 1 |
| `Core/Sources/ScribeCore/Store/SwiftDataItemStore.swift` | Implementations of the above | 1 |
| `Core/Sources/ScribeCore/Parsing/TimePhrases.swift`, `QuickAddParser.swift` | Day-part times; doc comment on two `.time` tokens | 2 |
| `Core/Sources/ScribeCore/Presentation/DeepLink.swift` | Parse/build `scribe://` URLs | 3 |
| `…/Presentation/TextDirection.swift` | First strong character → LTR/RTL | 3 |
| `…/Presentation/DueLabels.swift` | "Today", "Fri, 9 Oct", "18:00", "Tomorrow · 09:00" | 3 |
| `…/Presentation/DatePreset.swift` | Today / Tomorrow / Next Week for menus and chips | 3 |
| `…/Presentation/StoreErrorMessages.swift` | `StoreError` → user-facing sentence | 3 |
| `Core/Sources/ScribeCore/Models/CategoryPalette.swift` | `suggestedColorName(avoiding:)` for new categories | 3 |
| `…/Presentation/ItemGroups.swift` | Category screen sections; search groups | 4 |
| `…/Presentation/UndoCenter.swift` | One 5-second undo offer at a time | 4 |
| `…/Presentation/QuickAddComposer.swift` | Composer state: text, chips, dismiss, unknown tag, save | 5 |
| `project.yml`, `App/Info.plist` | Platform source folders, `scribe` URL scheme, UI test target + scheme | 6 |
| `App/ScribeApp.swift`, `App/Shared/*` | Store loading + failure screen, sync refresh, colors, text direction modifier | 6 |
| `App/macOS/RootView.swift` | Mac placeholder | 6 |
| `App/iOS/AppRouter.swift`, `UndoToast.swift`, `RootView.swift` | Navigation state, toast, tab shell | 6 (RootView grows in 7–10) |
| `App/iOS/QuickAddBar.swift`, `QuickAddSheet.swift` | Capsule and composer | 7 |
| `App/iOS/UpcomingView.swift`, `ItemRow.swift`, `ItemEditor.swift` | Agenda, rows, inline editor | 8 |
| `App/iOS/CategoriesView.swift`, `CategoryDetailView.swift` | Categories list, category screen | 9 |
| `App/iOS/SearchView.swift` | Search tab | 10 |
| `UITests/ScribeUITests.swift` | Smoke tests (spec §15) | 6–9 |
| `README.md`, `docs/backlog.md` | Status and remaining items | 11 |

---

### Task 1: Category-delete undo and drag reordering in the store

**Files:**
- Modify: `Core/Sources/ScribeCore/Store/ItemStore.swift`
- Modify: `Core/Sources/ScribeCore/Store/SwiftDataItemStore.swift`
- Test: `Core/Tests/ScribeCoreTests/StoreCategoryTests.swift` (append a suite)

**Interfaces:**
- Consumes: `SwiftDataItemStore` internals from Phase 1 — `ModelContext(container)`, `fetchCategories(_:)`, `categoryModel(_:in:)`, `itemModel(_:in:)`, `save(_:)`, `Category.snapshot(openCount:)`, `Item.snapshot`; test helper `makeStore()`.
- Produces:
  - `public struct CategoryDeletion: Equatable, Sendable { public let category: CategorySnapshot; public let itemIDs: [UUID]; public init(category:itemIDs:) }`
  - `ItemStore.moveCategories(fromOffsets source: IndexSet, toOffset destination: Int) throws` — same meaning as SwiftUI `onMove`.
  - `@discardableResult ItemStore.deleteCategory(_ id: UUID) throws -> CategoryDeletion`
  - `ItemStore.restoreCategory(_ deletion: CategoryDeletion) throws` — same id, name, emoji, color, sortIndex; re-attaches only items still in the Inbox; no-op if the category exists.

- [ ] **Step 1: Create the branch**

```bash
cd /Users/noamchuri/Documents/GitHub/scribe
git checkout main && git pull && git checkout -b phase2-iphone
```

- [ ] **Step 2: Write the failing tests** — append to `Core/Tests/ScribeCoreTests/StoreCategoryTests.swift`:

```swift
@MainActor
struct StoreCategoryUndoTests {
    @Test func deleteThenRestoreKeepsIdentityPositionAndItems() throws {
        let store = try makeStore()
        let a = try store.addCategory(CategoryDraft(name: "A"))
        let b = try store.addCategory(CategoryDraft(name: "B", emoji: "🏝️", colorName: "teal"))
        let c = try store.addCategory(CategoryDraft(name: "C"))
        let first = try store.addItem(ItemDraft(title: "one", categoryID: b))
        let second = try store.addItem(ItemDraft(title: "two", categoryID: b))
        let before = try #require(store.categories.first { $0.id == b })

        let deletion = try store.deleteCategory(b)
        #expect(deletion.category == before)
        #expect(Set(deletion.itemIDs) == [first, second])
        #expect(store.categories.map(\.id) == [a, c])

        try store.restoreCategory(deletion)
        #expect(store.categories.map(\.id) == [a, b, c])
        #expect(store.categories.first { $0.id == b } == before)
        #expect(Set(store.items(.category(b)).map(\.id)) == [first, second])

        try store.restoreCategory(deletion) // second restore is a no-op
        #expect(store.categories.count == 3)
    }

    @Test func restoreLeavesItemsTheUserRefiled() throws {
        let store = try makeStore()
        let home = try store.addCategory(CategoryDraft(name: "Home"))
        let trip = try store.addCategory(CategoryDraft(name: "Trip"))
        let moved = try store.addItem(ItemDraft(title: "moved", categoryID: trip))
        let kept = try store.addItem(ItemDraft(title: "kept", categoryID: trip))
        let deletion = try store.deleteCategory(trip)
        try store.updateItem(moved) { $0.categoryID = home }
        try store.restoreCategory(deletion)
        #expect(store.items(.category(trip)).map(\.id) == [kept])
        #expect(store.items(.category(home)).map(\.id) == [moved])
    }

    nonisolated static let moveCases: [(IndexSet, Int, [String])] = [
        (IndexSet(integer: 0), 2, ["B", "A", "C"]),
        (IndexSet(integer: 0), 3, ["B", "C", "A"]),
        (IndexSet(integer: 2), 0, ["C", "A", "B"]),
        (IndexSet([0, 2]), 1, ["A", "C", "B"]),
        (IndexSet(integer: 1), 1, ["A", "B", "C"]),
    ]

    /// Same results as `Array.move(fromOffsets:toOffset:)`, which SwiftUI's
    /// `onMove` reports.
    @Test(arguments: moveCases)
    func moveCategoriesMatchesOnMove(source: IndexSet, destination: Int, expected: [String]) throws {
        let store = try makeStore()
        for name in ["A", "B", "C"] { try store.addCategory(CategoryDraft(name: name)) }
        try store.moveCategories(fromOffsets: source, toOffset: destination)
        #expect(store.categories.map(\.name) == expected)
        #expect(store.categories.map(\.sortIndex) == [0, 1, 2])
    }
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `cd Core && swift test --filter StoreCategoryUndoTests`
Expected: build error — `CategoryDeletion`, `restoreCategory` and `moveCategories` don't exist.

- [ ] **Step 4: Extend the protocol** — in `ItemStore.swift`, insert directly above `public enum StoreError`:

```swift
/// What `deleteCategory` removed — everything `restoreCategory` needs.
public struct CategoryDeletion: Equatable, Sendable {
    public let category: CategorySnapshot
    public let itemIDs: [UUID]

    public init(category: CategorySnapshot, itemIDs: [UUID]) {
        self.category = category
        self.itemIDs = itemIDs
    }
}
```

and in `protocol ItemStore` replace

```swift
    /// Items in the category move to the Inbox.
    func deleteCategory(_ id: UUID) throws
```

with

```swift
    /// Same meaning as SwiftUI's `onMove(perform:)`: `destination` is an index
    /// in the list *before* the move.
    func moveCategories(fromOffsets source: IndexSet, toOffset destination: Int) throws
    /// Items in the category move to the Inbox. Keep the result to undo.
    @discardableResult func deleteCategory(_ id: UUID) throws -> CategoryDeletion
    /// Undo for `deleteCategory`: same id, name, color and position; items
    /// that are still in the Inbox go back into it. No-op if it exists.
    func restoreCategory(_ deletion: CategoryDeletion) throws
```

Keep `moveCategory(_:toIndex:)` — it stays for callers that know the final position.

- [ ] **Step 5: Implement** — in `SwiftDataItemStore.swift`, replace the existing

```swift
    public func deleteCategory(_ id: UUID) throws {
        let context = ModelContext(container)
        context.delete(try categoryModel(id, in: context))
        try save(context)
    }
```

with

```swift
    public func moveCategories(fromOffsets source: IndexSet, toOffset destination: Int) throws {
        let context = ModelContext(container)
        var ordered = fetchCategories(context)
        let moving = source.filter { ordered.indices.contains($0) }.map { ordered[$0] }
        guard !moving.isEmpty else { return }
        let insertAt = destination - source.filter { $0 < destination }.count
        ordered.removeAll { category in moving.contains { $0 === category } }
        ordered.insert(contentsOf: moving, at: min(max(insertAt, 0), ordered.count))
        for (position, category) in ordered.enumerated() where category.sortIndex != Double(position) {
            category.sortIndex = Double(position)
        }
        try save(context)
    }

    @discardableResult
    public func deleteCategory(_ id: UUID) throws -> CategoryDeletion {
        let context = ModelContext(container)
        let category = try categoryModel(id, in: context)
        let items = (category.items ?? []).map(\.snapshot)
        let deletion = CategoryDeletion(
            category: category.snapshot(openCount: items.filter { !$0.isDone }.count),
            itemIDs: items.map(\.id)
        )
        context.delete(category)
        try save(context)
        return deletion
    }

    public func restoreCategory(_ deletion: CategoryDeletion) throws {
        let context = ModelContext(container)
        guard (try? categoryModel(deletion.category.id, in: context)) == nil else { return }
        let snapshot = deletion.category
        let category = Category(
            id: snapshot.id,
            name: snapshot.name,
            emoji: snapshot.emoji,
            colorName: snapshot.colorName,
            sortIndex: snapshot.sortIndex
        )
        context.insert(category)
        for itemID in deletion.itemIDs {
            // Items the user re-filed since the delete stay where they are.
            if let item = try? itemModel(itemID, in: context), item.category == nil {
                item.category = category
            }
        }
        try save(context)
    }
```

(`insertAt` subtracts the moved rows that sat above the drop point — that is what makes a downward drag land where it was dropped.)

- [ ] **Step 6: Run all Core tests**

Run: `cd Core && swift test`
Expected: all pass, 0 failures (the existing `StoreSmokeView` call to `deleteCategory` still compiles thanks to `@discardableResult`).

- [ ] **Step 7: Commit**

```bash
git add Core
git commit -m "Store: undo for category delete, onMove-shaped reordering"
```

---

### Task 2: Day-part times in quick-add

**Files:**
- Modify: `Core/Sources/ScribeCore/Parsing/TimePhrases.swift`
- Modify: `Core/Sources/ScribeCore/Parsing/QuickAddParser.swift` (doc comment only)
- Test: `Core/Tests/ScribeCoreTests/ParserTimeTests.swift` (append a suite)

**Interfaces:**
- Consumes: `TimePhrases.namedTimes: [String: TimeValue]`, `TimeValue(minute:pinsToday:isUnambiguous:)`; test helpers `ParserFixture.parse(_:)`, `ParserFixture.day(_:_:)`.
- Produces: new phrases — "morning", "this morning", "in the morning", "בבוקר" → 09:00; "evening", "this evening", "in the evening", "בערב" → 19:00; "בצהרים" → 12:00. Like "noon", they follow the normal rule (today if still ahead, else tomorrow). "tonight"/"הערב" keep pinning today at 20:00.

- [ ] **Step 1: Write the failing tests** — append to `ParserTimeTests.swift`:

```swift
/// "Now" is Monday 2026-10-05 10:00 in Jerusalem.
struct ParserDayPartTests {
    typealias F = ParserFixture

    static let dayPartCases: [(String, String, LocalDay, Int)] = [
        ("call mom tomorrow morning", "call mom", F.day(10, 6), 9 * 60),
        ("call mom morning", "call mom", F.day(10, 6), 9 * 60),           // 09:00 already passed → tomorrow
        ("gym this evening", "gym", F.day(10, 5), 19 * 60),
        ("gym evening", "gym", F.day(10, 5), 19 * 60),
        ("gym in the evening", "gym", F.day(10, 5), 19 * 60),
        ("run fri in the morning", "run", F.day(10, 9), 9 * 60),
        ("להתקשר לאמא מחר בבוקר", "להתקשר לאמא", F.day(10, 6), 9 * 60),
        ("חדר כושר בערב", "חדר כושר", F.day(10, 5), 19 * 60),
        ("ארוחה בצהרים", "ארוחה", F.day(10, 5), 12 * 60),
    ]

    @Test(arguments: dayPartCases)
    func dayPartsSetATime(text: String, title: String, day: LocalDay, minute: Int) {
        let draft = F.parse(text)
        #expect(draft.title == title)
        #expect(draft.due == DueDate(day: day, minute: minute))
    }

    @Test func eveningAndTonightAreDifferent() {
        #expect(F.parse("x הערב").due == DueDate(day: F.day(10, 5), minute: 20 * 60))
        #expect(F.parse("x בערב").due == DueDate(day: F.day(10, 5), minute: 19 * 60))
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd Core && swift test --filter ParserDayPartTests`
Expected: FAIL — titles keep "morning"/"בערב" and `due` is nil or has no time.

- [ ] **Step 3: Add the phrases** — in `TimePhrases.namedTimes`, directly after the `"בצהריים"` entry, add:

```swift
        "בצהרים": TimeValue(minute: 12 * 60, pinsToday: false, isUnambiguous: true),
        "morning": TimeValue(minute: 9 * 60, pinsToday: false, isUnambiguous: true),
        "this morning": TimeValue(minute: 9 * 60, pinsToday: false, isUnambiguous: true),
        "in the morning": TimeValue(minute: 9 * 60, pinsToday: false, isUnambiguous: true),
        "בבוקר": TimeValue(minute: 9 * 60, pinsToday: false, isUnambiguous: true),
        "evening": TimeValue(minute: 19 * 60, pinsToday: false, isUnambiguous: true),
        "this evening": TimeValue(minute: 19 * 60, pinsToday: false, isUnambiguous: true),
        "in the evening": TimeValue(minute: 19 * 60, pinsToday: false, isUnambiguous: true),
        "בערב": TimeValue(minute: 19 * 60, pinsToday: false, isUnambiguous: true),
```

- [ ] **Step 4: Fix the parser's doc comment** — in `QuickAddParser.swift` replace

```swift
/// therefore keeps "שבת" in the title. Each token kind is used at most once.
```

with

```swift
/// therefore keeps "שבת" in the title. Each token kind is used at most once,
/// except that "tonight" / "הערב" may pair with one explicit time, so a draft
/// can carry two `.time` tokens.
```

- [ ] **Step 5: Run all Core tests**

Run: `cd Core && swift test`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add Core
git commit -m "Parser: morning, evening and בצהרים as quick-add times"
```

---

### Task 3: Display helpers

**Files:**
- Create: `Core/Sources/ScribeCore/Presentation/DeepLink.swift`
- Create: `Core/Sources/ScribeCore/Presentation/TextDirection.swift`
- Create: `Core/Sources/ScribeCore/Presentation/DueLabels.swift`
- Create: `Core/Sources/ScribeCore/Presentation/DatePreset.swift`
- Create: `Core/Sources/ScribeCore/Presentation/StoreErrorMessages.swift`
- Modify: `Core/Sources/ScribeCore/Models/CategoryPalette.swift`
- Test: `Core/Tests/ScribeCoreTests/DeepLinkTests.swift`, `TextDirectionTests.swift`, `DueLabelsTests.swift`, `DatePresetTests.swift`, `StoreErrorMessagesTests.swift`, `CategoryPaletteTests.swift`

**Interfaces:**
- Consumes: `LocalDay` (`init(_:_:_:)`, `init(_ date:calendar:)`, `adding(days:calendar:)`, `date(atMinute:calendar:)`), `DueDate(day:minute:)`, `DatePhrases.nextOccurrence(of:after:calendar:)` (internal, same module), `StoreError`, `CategoryPalette.colorNames`; test helpers `TestCalendar.jerusalem`, `TestCalendar.make(timeZone: String, firstWeekday: Int)`, `makeStore()`.
- Produces:
  - `public enum DeepLink: Hashable, Sendable { case add(categoryID: UUID?), item(UUID), upcoming; static let scheme = "scribe"; init?(url: URL); var url: URL }`
  - `public enum TextDirection { case leftToRight, rightToLeft; static func of(_ text: String) -> TextDirection }`
  - `public struct DueLabels { init(calendar: = .autoupdatingCurrent, locale: = .autoupdatingCurrent); func dayTitle(_ day: LocalDay, today: LocalDay) -> String; func time(_ minute: Int) -> String; func due(_ due: DueDate, today: LocalDay) -> String }`
  - `public enum DatePreset: CaseIterable { case today, tomorrow, nextWeek; var title: String; func day(today:calendar:) -> LocalDay; func applied(to: DueDate?, today:calendar:) -> DueDate }`
  - `extension StoreError: LocalizedError` (sentences the UI shows)
  - `CategoryPalette.suggestedColorName(avoiding used: [String]) -> String`

- [ ] **Step 1: Write the failing tests** — create these six files:

`Core/Tests/ScribeCoreTests/DeepLinkTests.swift`
```swift
import Foundation
import Testing
@testable import ScribeCore

struct DeepLinkTests {
    @Test func roundTrips() {
        let id = UUID()
        for link in [DeepLink.add(categoryID: nil), .add(categoryID: id), .item(id), .upcoming] {
            #expect(DeepLink(url: link.url) == link)
        }
        #expect(DeepLink.item(id).url.absoluteString == "scribe://item/\(id.uuidString)")
        #expect(DeepLink.add(categoryID: id).url.absoluteString == "scribe://add?category=\(id.uuidString)")
    }

    @Test(arguments: ["https://item/x", "scribe://item/not-a-uuid", "scribe://item", "scribe://settings", "scribe:"])
    func rejectsUnknownURLs(text: String) throws {
        #expect(DeepLink(url: try #require(URL(string: text))) == nil)
    }

    @Test func addIgnoresAMalformedCategory() throws {
        #expect(DeepLink(url: try #require(URL(string: "scribe://add?category=zzz"))) == .add(categoryID: nil))
    }
}
```

`Core/Tests/ScribeCoreTests/TextDirectionTests.swift`
```swift
import Foundation
import Testing
@testable import ScribeCore

struct TextDirectionTests {
    @Test(arguments: [
        ("לקנות חלב", TextDirection.rightToLeft),
        ("Buy milk", .leftToRight),
        ("4821 קוד לדלת", .rightToLeft),
        ("🧪 Smoke test", .leftToRight),
        ("📌 לקנות", .rightToLeft),
        ("", .leftToRight),
        ("12:30", .leftToRight),
        ("buy חלב", .leftToRight),
    ] as [(String, TextDirection)])
    func firstStrongLetterDecides(text: String, expected: TextDirection) {
        #expect(TextDirection.of(text) == expected)
    }
}
```

`Core/Tests/ScribeCoreTests/DueLabelsTests.swift`
```swift
import Foundation
import Testing
@testable import ScribeCore

struct DueLabelsTests {
    let labels = DueLabels(calendar: TestCalendar.jerusalem, locale: Locale(identifier: "en_GB"))
    let today = LocalDay(2026, 10, 5)

    @Test func relativeDayTitles() {
        #expect(labels.dayTitle(today, today: today) == "Today")
        #expect(labels.dayTitle(LocalDay(2026, 10, 6), today: today) == "Tomorrow")
        #expect(labels.dayTitle(LocalDay(2026, 10, 4), today: today) == "Yesterday")
        #expect(labels.dayTitle(LocalDay(2026, 10, 9), today: today) == "Fri 9 Oct")
        #expect(labels.dayTitle(LocalDay(2027, 1, 3), today: today) == "Sun, 3 Jan 2027")
    }

    @Test func dueText() {
        #expect(labels.due(DueDate(day: today), today: today) == "Today")
        #expect(labels.due(DueDate(day: LocalDay(2026, 10, 6), minute: 9 * 60 + 5), today: today) == "Tomorrow · 09:05")
    }
}
```

`Core/Tests/ScribeCoreTests/DatePresetTests.swift`
```swift
import Foundation
import Testing
@testable import ScribeCore

/// Today is Monday 2026-10-05.
struct DatePresetTests {
    let today = LocalDay(2026, 10, 5)

    @Test func presetsPickTheirDay() {
        let calendar = TestCalendar.jerusalem
        #expect(DatePreset.today.day(today: today, calendar: calendar) == today)
        #expect(DatePreset.tomorrow.day(today: today, calendar: calendar) == LocalDay(2026, 10, 6))
        #expect(DatePreset.nextWeek.day(today: today, calendar: calendar) == LocalDay(2026, 10, 11)) // Sunday
    }

    @Test func nextWeekFollowsTheDevicesFirstWeekday() {
        let mondayFirst = TestCalendar.make(timeZone: "Europe/London", firstWeekday: 2)
        #expect(DatePreset.nextWeek.day(today: today, calendar: mondayFirst) == LocalDay(2026, 10, 12))
    }

    @Test func applyingKeepsTheTime() {
        let calendar = TestCalendar.jerusalem
        let due = DueDate(day: LocalDay(2026, 10, 1), minute: 18 * 60)
        #expect(DatePreset.tomorrow.applied(to: due, today: today, calendar: calendar) == DueDate(day: LocalDay(2026, 10, 6), minute: 18 * 60))
        #expect(DatePreset.today.applied(to: nil, today: today, calendar: calendar) == DueDate(day: today))
    }
}
```

`Core/Tests/ScribeCoreTests/StoreErrorMessagesTests.swift`
```swift
import Foundation
import Testing
@testable import ScribeCore

@MainActor
struct StoreErrorMessagesTests {
    @Test func duplicateNameReadsAsASentence() throws {
        let store = try makeStore()
        try store.addCategory(CategoryDraft(name: "Work"))
        let error = #expect(throws: StoreError.duplicateCategoryName) {
            try store.addCategory(CategoryDraft(name: "work"))
        }
        #expect(error?.localizedDescription == "There’s already a category with that name.")
    }

    @Test func everyErrorHasAMessage() {
        let errors: [StoreError] = [
            .emptyTitle, .emptyCategoryName, .duplicateCategoryName,
            .invalidColorName("beige"), .itemNotFound(UUID()), .categoryNotFound(UUID()),
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
            #expect(!error.localizedDescription.contains("ScribeCore"))
        }
    }
}
```

`Core/Tests/ScribeCoreTests/CategoryPaletteTests.swift`
```swift
import Testing
@testable import ScribeCore

struct CategoryPaletteTests {
    @Test func suggestsTheFirstUnusedColor() {
        #expect(CategoryPalette.suggestedColorName(avoiding: []) == "red")
        #expect(CategoryPalette.suggestedColorName(avoiding: ["red", "yellow"]) == "orange")
        #expect(CategoryPalette.suggestedColorName(avoiding: ["blue", "blue"]) == "red")
    }

    @Test func cyclesOnceEveryColorIsUsed() {
        let all = CategoryPalette.colorNames
        #expect(CategoryPalette.suggestedColorName(avoiding: all) == all[0])
        #expect(CategoryPalette.suggestedColorName(avoiding: all + ["red"]) == all[1])
    }

    @Test func suggestionsAreValidColors() {
        for used in 0...30 {
            let names = Array(repeating: "red", count: used)
            #expect(CategoryPalette.colorNames.contains(CategoryPalette.suggestedColorName(avoiding: names)))
        }
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd Core && swift test`
Expected: build errors — `DeepLink`, `TextDirection`, `DueLabels`, `DatePreset`, `suggestedColorName` don't exist; `StoreError` has no `localizedDescription` sentence.

- [ ] **Step 3: Implement** — create:

`Core/Sources/ScribeCore/Presentation/DeepLink.swift`
```swift
import Foundation

/// `scribe://` URLs used by widgets, controls and the app itself (spec §8).
public enum DeepLink: Hashable, Sendable {
    /// Open the quick-add composer, optionally preselecting a category.
    case add(categoryID: UUID?)
    /// Show one item.
    case item(UUID)
    /// Show the Upcoming agenda.
    case upcoming

    public static let scheme = "scribe"

    public init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "add":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let category = query.first { $0.name == "category" }?.value.flatMap(UUID.init(uuidString:))
            self = .add(categoryID: category)
        case "item":
            guard path.count == 1, let id = UUID(uuidString: path[0]) else { return nil }
            self = .item(id)
        case "upcoming":
            self = .upcoming
        default:
            return nil
        }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .add(let categoryID):
            components.host = "add"
            if let categoryID {
                components.queryItems = [URLQueryItem(name: "category", value: categoryID.uuidString)]
            }
        case .item(let id):
            components.host = "item"
            components.path = "/" + id.uuidString
        case .upcoming:
            components.host = "upcoming"
        }
        return components.url!
    }
}
```

`Core/Sources/ScribeCore/Presentation/TextDirection.swift`
```swift
/// Direction of a piece of user text, decided by its first strong letter, so
/// a Hebrew title aligns right and an English one left regardless of the
/// system language (spec §9.4).
public enum TextDirection: Sendable, Equatable {
    case leftToRight
    case rightToLeft

    public static func of(_ text: String) -> TextDirection {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF:
                return .rightToLeft // Hebrew, Arabic and their presentation forms
            default:
                if scalar.properties.isAlphabetic { return .leftToRight }
            }
        }
        return .leftToRight
    }
}
```

`Core/Sources/ScribeCore/Presentation/DueLabels.swift`
```swift
import Foundation

/// Short human labels for days and due dates, shared by the app and widgets.
public struct DueLabels: Sendable {
    public var calendar: Calendar
    public var locale: Locale

    public init(calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) {
        self.calendar = calendar
        self.locale = locale
    }

    /// "Today", "Tomorrow", "Yesterday", or e.g. "Fri, 9 Oct".
    public func dayTitle(_ day: LocalDay, today: LocalDay) -> String {
        switch day {
        case today: return "Today"
        case today.adding(days: 1, calendar: calendar): return "Tomorrow"
        case today.adding(days: -1, calendar: calendar): return "Yesterday"
        default:
            var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .weekday(.abbreviated).day().month(.abbreviated)
            if day.year != today.year { style = style.year() }
            return day.date(atMinute: 12 * 60, calendar: calendar).formatted(style)
        }
    }

    /// "09:30" — 24-hour clock.
    public func time(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    /// "Today", "Tomorrow · 09:30", "Fri, 9 Oct · 18:00".
    public func due(_ due: DueDate, today: LocalDay) -> String {
        let day = dayTitle(due.day, today: today)
        guard let minute = due.minute else { return day }
        return "\(day) · \(time(minute))"
    }
}
```

`Core/Sources/ScribeCore/Presentation/DatePreset.swift`
```swift
import Foundation

/// The quick date choices in a row's menu and the editor's date chip.
/// "Next Week" means what typing "next week" means: the first day of next
/// week on this device's calendar.
public enum DatePreset: CaseIterable, Sendable {
    case today, tomorrow, nextWeek

    public var title: String {
        switch self {
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .nextWeek: "Next Week"
        }
    }

    public func day(today: LocalDay, calendar: Calendar) -> LocalDay {
        switch self {
        case .today: today
        case .tomorrow: today.adding(days: 1, calendar: calendar)
        case .nextWeek: DatePhrases.nextOccurrence(of: calendar.firstWeekday, after: today, calendar: calendar)
        }
    }

    /// The new due date; keeps the time the item already had.
    public func applied(to due: DueDate?, today: LocalDay, calendar: Calendar) -> DueDate {
        DueDate(day: day(today: today, calendar: calendar), minute: due?.minute)
    }
}
```

`Core/Sources/ScribeCore/Presentation/StoreErrorMessages.swift`
```swift
import Foundation

/// What the UI says when the store refuses a write (spec §13).
extension StoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyTitle: "Give it a title first."
        case .emptyCategoryName: "Give the category a name."
        case .duplicateCategoryName: "There’s already a category with that name."
        case .invalidColorName(let name): "“\(name)” isn’t one of the category colors."
        case .itemNotFound: "That item no longer exists. It may have been deleted on another device."
        case .categoryNotFound: "That category no longer exists. It may have been deleted on another device."
        }
    }
}
```

and replace `Core/Sources/ScribeCore/Models/CategoryPalette.swift` with:
```swift
public enum CategoryPalette {
    public static let colorNames = [
        "red", "orange", "yellow", "green", "mint", "teal", "cyan",
        "blue", "indigo", "purple", "pink", "brown", "gray",
    ]
    public static let defaultColorName = "blue"

    /// The color for a new category: the first palette color no category
    /// uses yet, so a fresh list isn't all one color. Cycles once all are used.
    public static func suggestedColorName(avoiding used: [String]) -> String {
        colorNames.first { !used.contains($0) } ?? colorNames[used.count % colorNames.count]
    }
}
```

- [ ] **Step 4: Run all Core tests**

Run: `cd Core && swift test`
Expected: all pass. If `dueText` fails only on a comma in "Sun, 3 Jan 2027", the test is right: `en_GB` puts a comma after the weekday when the year is shown.

- [ ] **Step 5: Commit**

```bash
git add Core
git commit -m "Core: deep links, text direction, due labels, date presets, error sentences"
```

---

### Task 4: List grouping and undo

**Files:**
- Create: `Core/Sources/ScribeCore/Presentation/ItemGroups.swift`
- Create: `Core/Sources/ScribeCore/Presentation/UndoCenter.swift`
- Test: `Core/Tests/ScribeCoreTests/ItemGroupsTests.swift`, `Core/Tests/ScribeCoreTests/UndoCenterTests.swift`

**Interfaces:**
- Consumes: `ItemSnapshot` (`kind`, `isDone`, `doneAt`, `categoryID`), `CategorySnapshot` (`id`, `sortIndex`).
- Produces:
  - `public struct CategoryContents: Equatable { var openTasks, memos, done: [ItemSnapshot]; init(items:); var isEmpty: Bool }` — open tasks and memos keep the store's order; done is newest first.
  - `public struct SearchGroup: Identifiable, Equatable { let category: CategorySnapshot?; let items: [ItemSnapshot]; var id: String; static func make(items:categories:) -> [SearchGroup] }` — Inbox (`category == nil`) first, then categories by `sortIndex`; empty groups omitted.
  - `@MainActor @Observable public final class UndoCenter { struct Offer: Identifiable { id; message }; private(set) var current: Offer?; init(duration: Duration = .seconds(5)); func offer(_ message: String, undo: @escaping @MainActor () throws -> Void); func performUndo() throws; func dismiss() }` — a new offer replaces the old one; `performUndo` clears first, then runs, so it can't run twice.

- [ ] **Step 1: Write the failing tests**

`Core/Tests/ScribeCoreTests/ItemGroupsTests.swift`
```swift
import Foundation
import Testing
@testable import ScribeCore

struct ItemGroupsTests {
    @Test func categoryContentsSplitsAndOrders() {
        let open = ItemSnapshot(title: "open")
        let memo = ItemSnapshot(title: "memo", kind: .memo)
        let doneEarly = ItemSnapshot(title: "done early", isDone: true, doneAt: Date(timeIntervalSince1970: 100))
        let doneLate = ItemSnapshot(title: "done late", isDone: true, doneAt: Date(timeIntervalSince1970: 200))
        let contents = CategoryContents(items: [doneEarly, open, memo, doneLate])
        #expect(contents.openTasks.map(\.title) == ["open"])
        #expect(contents.memos.map(\.title) == ["memo"])
        #expect(contents.done.map(\.title) == ["done late", "done early"])
        #expect(!contents.isEmpty)
        #expect(CategoryContents(items: []).isEmpty)
    }

    @Test func searchGroupsInboxFirstThenSortOrder() {
        let work = CategorySnapshot(name: "Work", sortIndex: 1)
        let trip = CategorySnapshot(name: "Trip", sortIndex: 0)
        let empty = CategorySnapshot(name: "Empty", sortIndex: 2)
        let items = [
            ItemSnapshot(title: "w", categoryID: work.id),
            ItemSnapshot(title: "i"),
            ItemSnapshot(title: "t", categoryID: trip.id),
        ]
        let groups = SearchGroup.make(items: items, categories: [work, trip, empty])
        #expect(groups.map { $0.category?.name ?? "Inbox" } == ["Inbox", "Trip", "Work"])
        #expect(groups.map { $0.items.map(\.title) } == [["i"], ["t"], ["w"]])
    }
}
```

`Core/Tests/ScribeCoreTests/UndoCenterTests.swift`
```swift
import Foundation
import Testing
@testable import ScribeCore

@MainActor
struct UndoCenterTests {
    @Test func undoRunsOnceAndClears() throws {
        let center = UndoCenter()
        var undone = 0
        center.offer("Deleted") { undone += 1 }
        #expect(center.current?.message == "Deleted")
        try center.performUndo()
        try center.performUndo()
        #expect(undone == 1)
        #expect(center.current == nil)
    }

    @Test func newOfferReplacesOld() throws {
        let center = UndoCenter()
        var log: [String] = []
        center.offer("first") { log.append("first") }
        center.offer("second") { log.append("second") }
        try center.performUndo()
        #expect(log == ["second"])
    }

    @Test func offersExpire() async throws {
        let center = UndoCenter(duration: .milliseconds(50))
        center.offer("Deleted") {}
        try await Task.sleep(for: .milliseconds(300))
        #expect(center.current == nil)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd Core && swift test --filter "ItemGroupsTests|UndoCenterTests"`
Expected: build errors — the types don't exist.

- [ ] **Step 3: Implement**

`Core/Sources/ScribeCore/Presentation/ItemGroups.swift`
```swift
import Foundation

/// The three sections of a category screen (spec §9.2): open tasks, memos,
/// then done tasks (most recently completed first).
public struct CategoryContents: Equatable, Sendable {
    public var openTasks: [ItemSnapshot]
    public var memos: [ItemSnapshot]
    public var done: [ItemSnapshot]

    /// `items` keeps the store's list order for open tasks and memos.
    public init(items: [ItemSnapshot]) {
        openTasks = items.filter { $0.kind == .task && !$0.isDone }
        memos = items.filter { $0.kind == .memo }
        done = items
            .filter { $0.isDone }
            .sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    public var isEmpty: Bool { openTasks.isEmpty && memos.isEmpty && done.isEmpty }
}

/// Search results grouped by where they live: Inbox first, then categories
/// in their sort order; empty groups are left out.
public struct SearchGroup: Identifiable, Equatable, Sendable {
    /// nil for the Inbox.
    public let category: CategorySnapshot?
    public let items: [ItemSnapshot]

    public var id: String { category?.id.uuidString ?? "inbox" }

    public static func make(items: [ItemSnapshot], categories: [CategorySnapshot]) -> [SearchGroup] {
        var groups: [SearchGroup] = []
        let inbox = items.filter { $0.categoryID == nil }
        if !inbox.isEmpty { groups.append(SearchGroup(category: nil, items: inbox)) }
        for category in categories.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            let matches = items.filter { $0.categoryID == category.id }
            if !matches.isEmpty { groups.append(SearchGroup(category: category, items: matches)) }
        }
        return groups
    }
}
```

`Core/Sources/ScribeCore/Presentation/UndoCenter.swift`
```swift
import Foundation
import Observation

/// Holds the single "Deleted · Undo" offer the UI shows (spec §13). A new
/// offer replaces the old one; offers expire after `duration`.
@MainActor
@Observable
public final class UndoCenter {
    public struct Offer: Identifiable {
        public let id = UUID()
        public let message: String
        fileprivate let undo: @MainActor () throws -> Void
    }

    public private(set) var current: Offer?
    @ObservationIgnored public let duration: Duration
    @ObservationIgnored private var expiry: Task<Void, Never>?

    public init(duration: Duration = .seconds(5)) {
        self.duration = duration
    }

    public func offer(_ message: String, undo: @escaping @MainActor () throws -> Void) {
        let offer = Offer(message: message, undo: undo)
        current = offer
        expiry?.cancel()
        expiry = Task { [weak self, duration] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, self.current?.id == offer.id else { return }
            self.current = nil
        }
    }

    /// Runs the undo and clears the offer (also when the undo throws).
    public func performUndo() throws {
        guard let offer = current else { return }
        dismiss()
        try offer.undo()
    }

    public func dismiss() {
        expiry?.cancel()
        expiry = nil
        current = nil
    }
}
```

- [ ] **Step 4: Run all Core tests**

Run: `cd Core && swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Core
git commit -m "Core: category screen sections, search groups, undo center"
```

---

### Task 5: The quick-add composer

**Files:**
- Create: `Core/Sources/ScribeCore/Presentation/QuickAddComposer.swift`
- Test: `Core/Tests/ScribeCoreTests/QuickAddComposerTests.swift`

**Interfaces:**
- Consumes: `QuickAddParser(calendar:)` and `parse(_:categories:now:disabled:)`, `ParsedDraft` (`title`, `category` = `.none/.matched(UUID)/.unknown(String)`, `tokens: [RecognizedToken]`, `isValid`, `itemDraft`), `TokenKind`, `DueLabels` (Task 3), `CategoryPalette.suggestedColorName(avoiding:)` (Task 3), `ItemStore.addItem`, `addCategory`, `categories`; test helpers `TestClock`, `makeStore(clock:)`, `TestCalendar.jerusalem`.
- Produces: `@MainActor @Observable public final class QuickAddComposer` with
  - `init(store: any ItemStore, calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent, now: @escaping () -> Date = { Date() })`
  - state: `var text: String`, `var isMemo: Bool`, `var defaultCategoryID: UUID?`, `private(set) var disabled: Set<TokenKind>`
  - derived: `var parsed: ParsedDraft`, `var canSave: Bool`, `var unknownCategoryName: String?`, `var chips: [Chip]` where `struct Chip: Identifiable, Equatable { let id: Int /* token index */; let kind: TokenKind; let label: String }` — at most one time chip is shown
  - actions: `func dismiss(_ chip: Chip)`, `func createUnknownCategory() throws` (new category gets the suggested palette color), `@discardableResult func save() throws -> UUID?` (nil when there's no title; an unknown tag stays in the title; the default category applies only when no tag was typed; resets afterwards), `func reset()`

- [ ] **Step 1: Write the failing tests**

`Core/Tests/ScribeCoreTests/QuickAddComposerTests.swift`
```swift
import Foundation
import Testing
@testable import ScribeCore

@MainActor
struct QuickAddComposerTests {
    func make() throws -> (SwiftDataItemStore, QuickAddComposer) {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        let composer = QuickAddComposer(store: store, calendar: TestCalendar.jerusalem, locale: Locale(identifier: "en_GB"), now: { clock.now })
        return (store, composer)
    }

    @Test func chipsDescribeTheParse() throws {
        let (store, composer) = try make()
        try store.addCategory(CategoryDraft(name: "Thailand", emoji: "🇹🇭"))
        composer.text = "book flights fri 18:00 #thai"
        #expect(composer.chips.map(\.label) == ["Fri 9 Oct", "18:00", "🇹🇭 Thailand"])
        #expect(composer.parsed.title == "book flights")
        #expect(composer.canSave)
    }

    @Test func tonightWithATimeShowsOneTimeChip() throws {
        let (_, composer) = try make()
        composer.text = "call Dan tonight at 9"
        #expect(composer.chips.map(\.label) == ["21:00"])
        composer.dismiss(try #require(composer.chips.first))
        #expect(composer.parsed.title == "call Dan tonight at 9")
        #expect(composer.chips.isEmpty)
    }

    @Test func dismissingAChipPutsItsTextBack() throws {
        let (_, composer) = try make()
        composer.text = "pay rent fri"
        composer.dismiss(try #require(composer.chips.first))
        #expect(composer.parsed.title == "pay rent fri")
        #expect(composer.parsed.due == nil)
    }

    @Test func savesWithParsedFieldsAndResets() throws {
        let (store, composer) = try make()
        let trip = try store.addCategory(CategoryDraft(name: "Thailand"))
        composer.text = "book flights fri #thailand"
        let id = try #require(try composer.save())
        let item = try #require(store.item(id))
        #expect(item.title == "book flights")
        #expect(item.categoryID == trip)
        #expect(item.due == DueDate(day: LocalDay(2026, 10, 9)))
        #expect(composer.text.isEmpty)
    }

    @Test func unknownTagCanBecomeACategory() throws {
        let (store, composer) = try make()
        try store.addCategory(CategoryDraft(name: "Work", colorName: "red"))
        composer.text = "visa #bulgaria"
        #expect(composer.unknownCategoryName == "bulgaria")
        try composer.createUnknownCategory()
        #expect(store.categories.map(\.name) == ["Work", "bulgaria"])
        #expect(store.categories.last?.colorName == "orange")
        #expect(composer.unknownCategoryName == nil)
        let id = try #require(try composer.save())
        #expect(store.item(id)?.categoryID == store.categories.last?.id)
    }

    @Test func unknownTagLeftAloneStaysInTheTitle() throws {
        let (store, composer) = try make()
        composer.text = "buy milk #grocries"
        let id = try #require(try composer.save())
        #expect(store.item(id)?.title == "buy milk #grocries")
        #expect(store.item(id)?.categoryID == nil)
    }

    @Test func memoToggleAndDefaultCategory() throws {
        let (store, composer) = try make()
        let work = try store.addCategory(CategoryDraft(name: "Work"))
        let home = try store.addCategory(CategoryDraft(name: "Home"))
        composer.defaultCategoryID = work
        composer.isMemo = true
        composer.text = "door code 4821"
        let memo = try #require(try composer.save())
        #expect(store.item(memo)?.kind == .memo)
        #expect(store.item(memo)?.categoryID == work)
        #expect(composer.isMemo == false)

        composer.text = "fix sink #home" // an explicit tag beats the default
        let fix = try #require(try composer.save())
        #expect(store.item(fix)?.categoryID == home)
    }

    @Test func emptyTextCannotSave() throws {
        let (store, composer) = try make()
        composer.text = "   "
        #expect(!composer.canSave)
        #expect(try composer.save() == nil)
        #expect(store.items(.inbox).isEmpty)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd Core && swift test --filter QuickAddComposerTests`
Expected: build error — `QuickAddComposer` doesn't exist.

- [ ] **Step 3: Implement**

`Core/Sources/ScribeCore/Presentation/QuickAddComposer.swift`
```swift
import Foundation
import Observation

/// State behind every in-app quick-add field (spec §8): the text, the live
/// parse, dismissible chips, the task/memo toggle and saving.
@MainActor
@Observable
public final class QuickAddComposer {
    /// One recognized token shown as a chip. `id` is its position, so two
    /// time chips ("tonight" + "at 9") never collide.
    public struct Chip: Identifiable, Equatable, Sendable {
        public let id: Int
        public let kind: TokenKind
        public let label: String
    }

    public var text: String = ""
    /// The ✓/📝 toggle. `!memo` typed in the text also makes a memo.
    public var isMemo: Bool = false
    /// Category to use when the text has no `#tag` (e.g. composing from a
    /// category screen or a category widget).
    public var defaultCategoryID: UUID?
    public private(set) var disabled: Set<TokenKind> = []

    @ObservationIgnored private let store: any ItemStore
    @ObservationIgnored private let parser: QuickAddParser
    @ObservationIgnored private let labels: DueLabels
    @ObservationIgnored private let now: () -> Date

    public init(
        store: any ItemStore,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.parser = QuickAddParser(calendar: calendar)
        self.labels = DueLabels(calendar: calendar, locale: locale)
        self.now = now
    }

    public var parsed: ParsedDraft {
        parser.parse(text, categories: store.categories, now: now(), disabled: disabled)
    }

    public var canSave: Bool { parsed.isValid }

    /// Name of a typed `#tag` that matches no category, for a
    /// "+ New category" chip.
    public var unknownCategoryName: String? {
        if case .unknown(let name) = parsed.category { return name }
        return nil
    }

    public var chips: [Chip] {
        let draft = parsed
        let today = LocalDay(now(), calendar: parser.calendar)
        var shownTime = false
        return draft.tokens.enumerated().compactMap { index, token in
            // "tonight at 9" is two time tokens but one time: show one chip.
            if token.kind == .time {
                if shownTime { return nil }
                shownTime = true
            }
            guard let label = label(for: token, in: draft, today: today) else { return nil }
            return Chip(id: index, kind: token.kind, label: label)
        }
    }

    /// The user tapped a chip: stop interpreting that kind of token; its
    /// text goes back into the title.
    public func dismiss(_ chip: Chip) {
        disabled.insert(chip.kind)
    }

    public func createUnknownCategory() throws {
        guard let name = unknownCategoryName else { return }
        let color = CategoryPalette.suggestedColorName(avoiding: store.categories.map(\.colorName))
        try store.addCategory(CategoryDraft(name: name, colorName: color))
    }

    /// Adds the item and clears the composer. Returns nil when there is no
    /// title. An unknown `#tag` that wasn't turned into a category stays in
    /// the title instead of being dropped.
    @discardableResult
    public func save() throws -> UUID? {
        var draft = parsed
        if case .unknown = draft.category {
            draft = parser.parse(text, categories: store.categories, now: now(), disabled: disabled.union([.category]))
        }
        guard var item = draft.itemDraft else { return nil }
        if isMemo { item.kind = .memo }
        if item.categoryID == nil, case .none = draft.category { item.categoryID = defaultCategoryID }
        let id = try store.addItem(item)
        reset()
        return id
    }

    public func reset() {
        text = ""
        isMemo = false
        disabled = []
    }

    private func label(for token: RecognizedToken, in draft: ParsedDraft, today: LocalDay) -> String? {
        switch token.kind {
        case .category:
            guard case .matched(let id) = draft.category,
                  let category = store.categories.first(where: { $0.id == id }) else { return nil }
            return category.emoji.isEmpty ? category.name : "\(category.emoji) \(category.name)"
        case .kind:
            return "Memo"
        case .date:
            return draft.due.map { labels.dayTitle($0.day, today: today) }
        case .time:
            return draft.due?.minute.map { labels.time($0) }
        }
    }
}
```

- [ ] **Step 4: Run all Core tests**

Run: `cd Core && swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Core
git commit -m "Core: quick-add composer with chips, unknown tags and defaults"
```

---

### Task 6: App shell — project layout, store loading, tab bar

The app stops being the Phase 0 smoke screen. After this task it launches into the glass tab bar with placeholder tabs (filled in by Tasks 8–10), shows a full-screen error with Retry if the store can't open, refreshes after iCloud imports, opens `scribe://` links, and has a UI test target.

**Files:**
- Modify: `project.yml` (whole file below)
- Regenerate: `App/Info.plist` (adds `CFBundleURLTypes`)
- Modify: `App/ScribeApp.swift`
- Delete: `App/StoreSmokeView.swift`
- Create: `App/Shared/StoreLoader.swift`, `App/Shared/SyncRefresher.swift`, `App/Shared/StoreFailedView.swift`, `App/Shared/Styling.swift`
- Create: `App/macOS/RootView.swift`
- Create: `App/iOS/AppRouter.swift`, `App/iOS/UndoToast.swift`, `App/iOS/RootView.swift`
- Test: `UITests/ScribeUITests.swift`

**Interfaces:**
- Consumes: `StoreFactory.shared(syncsWithCloudKit:)`, `StoreFactory.inMemory()`, `SwiftDataItemStore(container:)`, `store.refresh()`, `DeepLink` (Task 3), `TextDirection` (Task 3), `UndoCenter` (Task 4), `ItemStore.item(_:)`.
- Produces (used by Tasks 7–10):
  - `final class AppRouter` (`@MainActor @Observable`): `enum Tab { upcoming, categories, search }`, `enum Destination: Hashable { inbox, category(UUID) }`, `var tab`, `var categoriesPath: [Destination]`, `var isComposing`, `var composerCategoryID: UUID?`, `var expandedItemID: UUID?`, `var alertMessage: String?`, `var visibleCategoryID: UUID?`, `func compose(in: UUID?)`, `func open(_: DeepLink, store:)`, `func perform(_ action: () throws -> Void)`.
  - Environment values on every tab: `AppRouter`, `UndoCenter`.
  - `extension CategorySnapshot { var color: Color; var displayName: String }`
  - `extension View { func layoutDirection(of text: String) -> some View }`
  - `RootView(store: SwiftDataItemStore)` on both platforms.
  - UI test class `ScribeUITests` with `app` launched as `-uiTesting`.

- [ ] **Step 1: Write the failing UI test** — create `UITests/ScribeUITests.swift`:

```swift
import XCTest

/// Smoke tests for the iPhone app (spec §15). The app launches with
/// `-uiTesting`: an in-memory store, no iCloud.
@MainActor
final class ScribeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    func testLaunchShowsTheTabs() {
        XCTAssertTrue(app.tabBars.buttons["Upcoming"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Categories"].exists)
    }
}
```

- [ ] **Step 2: Replace `project.yml`** with the version below. What changes: the app's sources split into `App/` (both platforms, minus the platform folders), `App/iOS` and `App/macOS` via `destinationFilters`; the `scribe` URL scheme; a `ScribeUITests` target; an explicit `Scribe` scheme whose test action runs it.

```yaml
name: Scribe
options:
  bundleIdPrefix: com.noamchuri
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    IPHONEOS_DEPLOYMENT_TARGET: "26.0"
    MACOSX_DEPLOYMENT_TARGET: "26.0"
    CODE_SIGN_STYLE: Automatic
    DEVELOPMENT_TEAM: X74V85W2JX
    MARKETING_VERSION: "0.1"
    CURRENT_PROJECT_VERSION: "1"
packages:
  ScribeCore:
    path: Core
targets:
  Scribe:
    type: application
    supportedDestinations: [iOS, macOS]
    sources:
      - path: App
        excludes:
          - "iOS/**"
          - "macOS/**"
      - path: App/iOS
        destinationFilters: [iOS]
      - path: App/macOS
        destinationFilters: [macOS]
    dependencies:
      - package: ScribeCore
      - target: ScribeWidgets
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: Scribe
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        UILaunchScreen: {}
        UIBackgroundModes: [remote-notification]
        CFBundleURLTypes:
          - CFBundleURLName: com.noamchuri.scribe
            CFBundleURLSchemes: [scribe]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.noamchuri.scribe
        TARGETED_DEVICE_FAMILY: "1"
        CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]: App/Scribe-iOS.entitlements
        CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]: App/Scribe-iOS.entitlements
        CODE_SIGN_ENTITLEMENTS[sdk=macosx*]: App/Scribe-macOS.entitlements
        ENABLE_HARDENED_RUNTIME[sdk=macosx*]: YES
  ScribeWidgets:
    type: app-extension
    supportedDestinations: [iOS, macOS]
    sources:
      - Widgets
    dependencies:
      - package: ScribeCore
    info:
      path: Widgets/Info.plist
      properties:
        CFBundleDisplayName: Scribe Widgets
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.noamchuri.scribe.widgets
        TARGETED_DEVICE_FAMILY: "1"
        CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]: Widgets/ScribeWidgets-iOS.entitlements
        CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]: Widgets/ScribeWidgets-iOS.entitlements
        CODE_SIGN_ENTITLEMENTS[sdk=macosx*]: Widgets/ScribeWidgets-macOS.entitlements
        ENABLE_HARDENED_RUNTIME[sdk=macosx*]: YES
  ScribeUITests:
    type: bundle.ui-testing
    platform: iOS
    deploymentTarget: "26.0"
    sources:
      - UITests
    dependencies:
      - target: Scribe
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.noamchuri.scribe.uitests
        TARGETED_DEVICE_FAMILY: "1"
        GENERATE_INFOPLIST_FILE: YES
schemes:
  Scribe:
    build:
      targets:
        Scribe: all
    test:
      targets:
        - ScribeUITests
```

- [ ] **Step 3: Generate and watch the test fail** (XcodeGen needs the platform folders to exist; they fill up in Steps 5–6)

```bash
cd /Users/noamchuri/Documents/GitHub/scribe
mkdir -p App/iOS App/macOS
xcodegen generate
xcodebuild -project Scribe.xcodeproj -scheme Scribe -destination id=E4ABB0FF-1B3F-43D4-A4AB-AA656FCEA434 -derivedDataPath build/dd-sim test 2>&1 | grep -E "error:|Test Case|\*\* TEST"
```

Expected: FAIL — the app still shows `StoreSmokeView`, which has no tab bar (`testLaunchShowsTheTabs` fails on the "Upcoming" tab button).

- [ ] **Step 4: Shared app code** — create:

`App/Shared/StoreLoader.swift`
```swift
import Observation
import ScribeCore
import SwiftData

/// Opens the store once at launch (spec §13: a failure shows a screen with
/// Retry; the store file is never deleted or reset).
@MainActor
@Observable
final class StoreLoader {
    enum State {
        case loading
        case ready(SwiftDataItemStore)
        case failed(String)
    }

    private(set) var state: State = .loading
    @ObservationIgnored private var refresher: SyncRefresher?

    /// UI tests launch with `-uiTesting`: a fresh in-memory store, no iCloud.
    static var isUITesting: Bool { CommandLine.arguments.contains("-uiTesting") }

    func load() {
        do {
            let container = Self.isUITesting
                ? try StoreFactory.inMemory()
                : try StoreFactory.shared(syncsWithCloudKit: true)
            let store = SwiftDataItemStore(container: container)
            refresher = SyncRefresher(store: store)
            state = .ready(store)
        } catch {
            state = .failed(String(describing: error))
        }
    }
}
```

`App/Shared/SyncRefresher.swift`
```swift
import CoreData
import ScribeCore

/// Re-reads the store after iCloud imports and after writes from other
/// processes (widget, intents), so open screens update (spec §12).
@MainActor
final class SyncRefresher {
    private var observers: [NSObjectProtocol] = []

    init(store: SwiftDataItemStore) {
        let center = NotificationCenter.default
        let names = [NSPersistentCloudKitContainer.eventChangedNotification, .NSPersistentStoreRemoteChange]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak store] _ in
                MainActor.assumeIsolated { store?.refresh() }
            })
        }
    }
}
```

`App/Shared/StoreFailedView.swift`
```swift
import SwiftUI

struct StoreFailedView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Can't open your notes", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Nothing was deleted. Try again, or restart the app.\n\n\(message)")
        } actions: {
            Button("Try Again", action: retry)
                .buttonStyle(.glassProminent)
        }
    }
}
```

`App/Shared/Styling.swift`
```swift
import ScribeCore
import SwiftUI

extension CategorySnapshot {
    /// The category's palette color (spec §5.1).
    var color: Color {
        switch colorName {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "cyan": .cyan
        case "indigo": .indigo
        case "purple": .purple
        case "pink": .pink
        case "brown": .brown
        case "gray": .gray
        default: .blue
        }
    }

    /// "🇹🇭 Thailand", or just the name without an emoji.
    var displayName: String { emoji.isEmpty ? name : "\(emoji) \(name)" }
}

extension View {
    /// Lays the view out in the direction of `text` itself — right-to-left
    /// for Hebrew, left-to-right otherwise — whatever the system language
    /// (spec §9.4).
    func layoutDirection(of text: String) -> some View {
        environment(\.layoutDirection, TextDirection.of(text) == .rightToLeft ? .rightToLeft : .leftToRight)
    }
}
```

- [ ] **Step 5: App entry and Mac placeholder** — replace `App/ScribeApp.swift` with:

```swift
import ScribeCore
import SwiftUI

@main
struct ScribeApp: App {
    @State private var loader = StoreLoader()

    var body: some Scene {
        WindowGroup {
            Group {
                switch loader.state {
                case .loading:
                    ProgressView()
                case .failed(let message):
                    StoreFailedView(message: message, retry: loader.load)
                case .ready(let store):
                    RootView(store: store)
                }
            }
            .task {
                if case .loading = loader.state { loader.load() }
            }
        }
    }
}
```

Create `App/macOS/RootView.swift`:
```swift
import ScribeCore
import SwiftUI

/// The Mac app arrives in Phase 3.
struct RootView: View {
    let store: SwiftDataItemStore

    var body: some View {
        ContentUnavailableView("Scribe for Mac is coming soon", systemImage: "macwindow")
            .frame(minWidth: 420, minHeight: 280)
    }
}
```

Delete the smoke screen: `git rm App/StoreSmokeView.swift`

- [ ] **Step 6: iPhone shell** — create:

`App/iOS/AppRouter.swift`
```swift
import Foundation
import Observation
import ScribeCore

/// Navigation state for the iPhone app: selected tab, the Categories stack,
/// the quick-add sheet, the one row being edited, and error alerts.
@MainActor
@Observable
final class AppRouter {
    enum Tab: Hashable {
        case upcoming, categories, search
    }

    enum Destination: Hashable {
        case inbox
        case category(UUID)
    }

    var tab: Tab = .upcoming
    var categoriesPath: [Destination] = []
    var isComposing = false
    var composerCategoryID: UUID?
    /// The row showing its inline editor; one at a time.
    var expandedItemID: UUID?
    var alertMessage: String?

    /// The category on screen, so quick-add files into it by default.
    var visibleCategoryID: UUID? {
        guard tab == .categories, case .category(let id)? = categoriesPath.last else { return nil }
        return id
    }

    func compose(in categoryID: UUID?) {
        composerCategoryID = categoryID
        isComposing = true
    }

    func open(_ link: DeepLink, store: any ItemStore) {
        switch link {
        case .upcoming:
            tab = .upcoming
        case .add(let categoryID):
            compose(in: categoryID)
        case .item(let id):
            guard let item = store.item(id) else { return }
            tab = .categories
            categoriesPath = [item.categoryID.map(Destination.category) ?? .inbox]
            expandedItemID = id
        }
    }

    /// Runs a store write; failures become an alert instead of vanishing.
    func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
```

`App/iOS/UndoToast.swift`
```swift
import ScribeCore
import SwiftUI

/// "Deleted “X” · Undo" floating above the tab bar for five seconds.
struct UndoToast: View {
    @Environment(UndoCenter.self) private var undo
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let offer = undo.current {
            HStack(spacing: 12) {
                Text(offer.message)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Undo") {
                    router.perform { try undo.performUndo() }
                }
                .bold()
                .accessibilityIdentifier("undoButton")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(offer.id)
        }
    }
}
```

`App/iOS/RootView.swift` — the tabs show a `ComingNext` placeholder until Tasks 8–10 replace them:
```swift
import ScribeCore
import SwiftUI

/// iPhone app: floating glass tab bar with Upcoming, Categories and Search,
/// and the quick-add capsule above it on every tab (spec §9.2).
struct RootView: View {
    let store: SwiftDataItemStore

    @State private var router = AppRouter()
    @State private var undo = UndoCenter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Upcoming", systemImage: "calendar", value: AppRouter.Tab.upcoming) {
                NavigationStack {
                    ComingNext(title: "Upcoming")
                }
            }
            Tab("Categories", systemImage: "square.stack", value: AppRouter.Tab.categories) {
                NavigationStack(path: $router.categoriesPath) {
                    ComingNext(title: "Categories")
                }
            }
            Tab(value: AppRouter.Tab.search, role: .search) {
                NavigationStack {
                    ComingNext(title: "Search")
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .overlay(alignment: .bottom) {
            UndoToast()
        }
        .alert("Couldn’t Save", isPresented: Binding(
            get: { router.alertMessage != nil },
            set: { if !$0 { router.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(router.alertMessage ?? "")
        }
        .environment(router)
        .environment(undo)
        .onOpenURL { url in
            if let link = DeepLink(url: url) { router.open(link, store: store) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refresh() }
        }
    }
}

/// Stands in for a tab whose screen a later task builds. Task 10 deletes it.
private struct ComingNext: View {
    let title: String

    var body: some View {
        ContentUnavailableView(title, systemImage: "hammer")
            .navigationTitle(title)
    }
}
```

- [ ] **Step 7: Generate, build both platforms, run the UI test**

```bash
xcodegen generate
git diff --stat App/Info.plist   # expect CFBundleURLTypes added
xcodebuild -project Scribe.xcodeproj -scheme Scribe -destination "platform=macOS" -derivedDataPath build/dd build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "warning:|error:|\*\* BUILD"
xcodebuild -project Scribe.xcodeproj -scheme Scribe -destination id=E4ABB0FF-1B3F-43D4-A4AB-AA656FCEA434 -derivedDataPath build/dd-sim test 2>&1 | grep -E "warning:|error:|Test Case|\*\* TEST"
```

Expected: `** BUILD SUCCEEDED **` for macOS with no warnings (ignore the `appintentsmetadataprocessor` line); `testLaunchShowsTheTabs` passed; `** TEST SUCCEEDED **`.

- [ ] **Step 8: Check the URL scheme** — with the simulator still booted:

```bash
xcrun simctl openurl E4ABB0FF-1B3F-43D4-A4AB-AA656FCEA434 "scribe://upcoming"
```

Expected: Scribe comes to the front (no "unsupported URL" error).

- [ ] **Step 9: Commit**

```bash
git add -A project.yml App UITests
git commit -m "iPhone app shell: platform folders, store loading with Retry, tab bar, deep links, UI test target"
```

---

### Task 7: Quick-add capsule and composer

**Files:**
- Create: `App/iOS/QuickAddBar.swift`, `App/iOS/QuickAddSheet.swift`
- Modify: `App/iOS/RootView.swift`
- Test: `UITests/ScribeUITests.swift`

**Interfaces:**
- Consumes: `AppRouter.compose(in:)`, `visibleCategoryID`, `isComposing`, `composerCategoryID`, `perform(_:)` (Task 6); `QuickAddComposer` (Task 5); `View.layoutDirection(of:)` (Task 6); `TokenKind`.
- Produces: `QuickAddBar()` (identifier `quickAddBar`), `QuickAddSheet(store:categoryID:)` with field identifier `quickAddField` and kind toggle `kindToggle`. Return in the field saves; the sheet closes after a save.

- [ ] **Step 1: Write the failing UI test** — add to `ScribeUITests` after `testLaunchShowsTheTabs`:

```swift
    func testComposerAddsOnlyWithATitle() {
        app.buttons["quickAddBar"].tap()
        let field = app.textFields["quickAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Add"].isEnabled)
        field.typeText("Buy milk tomorrow\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "composer should close after adding")
    }
```

- [ ] **Step 2: Run it to see it fail**

```bash
xcodebuild -project Scribe.xcodeproj -scheme Scribe -destination id=E4ABB0FF-1B3F-43D4-A4AB-AA656FCEA434 -derivedDataPath build/dd-sim test -only-testing:ScribeUITests/ScribeUITests/testComposerAddsOnlyWithATitle 2>&1 | grep -E "error:|Test Case"
```

Expected: FAIL — no `quickAddBar` button.

- [ ] **Step 3: Implement** — create:

`App/iOS/QuickAddBar.swift`
```swift
import SwiftUI

/// The glass capsule above the tab bar (spec §8). Tapping it opens the
/// composer, filed into the category on screen if there is one.
struct QuickAddBar: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        Button {
            router.compose(in: router.visibleCategoryID)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                if placement != .inline {
                    Text("Add a task or note")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a task or note")
        .accessibilityIdentifier("quickAddBar")
    }
}
```

`App/iOS/QuickAddSheet.swift`
```swift
import ScribeCore
import SwiftUI

/// The composer: one line of text, live chips for what the parser
/// understood (tap one to undo it), task/memo toggle, Add (spec §8).
struct QuickAddSheet: View {
    @State private var composer: QuickAddComposer
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @FocusState private var focused: Bool

    init(store: any ItemStore, categoryID: UUID?) {
        let composer = QuickAddComposer(store: store)
        composer.defaultCategoryID = categoryID
        _composer = State(initialValue: composer)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button {
                    composer.isMemo.toggle()
                } label: {
                    Image(systemName: composer.isMemo ? "note.text" : "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(composer.isMemo ? "Memo" : "Task")
                .accessibilityIdentifier("kindToggle")

                TextField("Add a task or note", text: $composer.text)
                    .font(.title3)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .layoutDirection(of: composer.text)
                    .accessibilityIdentifier("quickAddField")

                Button("Add", action: save)
                    .buttonStyle(.glassProminent)
                    .disabled(!composer.canSave)
            }
            chips
        }
        .padding(20)
        .presentationDetents([.height(150)])
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
    }

    @ViewBuilder private var chips: some View {
        let chips = composer.chips
        if !chips.isEmpty || composer.unknownCategoryName != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer {
                    HStack(spacing: 8) {
                        ForEach(chips) { chip in
                            Button { composer.dismiss(chip) } label: {
                                Label(chip.label, systemImage: icon(for: chip.kind))
                            }
                            .buttonStyle(.glass)
                            .accessibilityHint("Removes this and keeps the text in the title")
                        }
                        if let name = composer.unknownCategoryName {
                            Button("New category “\(name)”", systemImage: "plus") {
                                router.perform { try composer.createUnknownCategory() }
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
            }
        } else {
            Text("Try “call mom tomorrow 9am #family”")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    private func icon(for kind: TokenKind) -> String {
        switch kind {
        case .category: "folder"
        case .kind: "note.text"
        case .date: "calendar"
        case .time: "clock"
        }
    }

    private func save() {
        router.perform {
            if try composer.save() != nil { dismiss() }
        }
    }
}
```

In `App/iOS/RootView.swift`, replace

```swift
        .tabBarMinimizeBehavior(.onScrollDown)
        .overlay(alignment: .bottom) {
            UndoToast()
        }
```

with

```swift
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            QuickAddBar()
        }
        .overlay(alignment: .bottom) {
            UndoToast()
        }
        .sheet(isPresented: $router.isComposing) {
            QuickAddSheet(store: store, categoryID: router.composerCategoryID)
        }
```

- [ ] **Step 4: Run all UI tests**

```bash
xcodebuild -project Scribe.xcodeproj -scheme Scribe -destination id=E4ABB0FF-1B3F-43D4-A4AB-AA656FCEA434 -derivedDataPath build/dd-sim test 2>&1 | grep -E "warning:|error:|Test Case|\*\* TEST"
```

Expected: 2 tests passed, no warnings.

- [ ] **Step 5: Commit**

```bash
git add App UITests
git commit -m "Quick-add capsule and composer with live chips"
```

---

### Task 8: Upcoming, rows and inline editing

**Files:**
- Create: `App/iOS/UpcomingView.swift`, `App/iOS/ItemRow.swift`, `App/iOS/ItemEditor.swift`
- Modify: `App/iOS/RootView.swift`
- Test: `UITests/ScribeUITests.swift`

**Interfaces:**
- Consumes: `ItemStore.agenda(.all, now:)` (`Agenda.overdue`, `.days[].day/.items`, `.isEmpty`), `setDone`, `updateItem(_:_:)` with `ItemEdit` (`title`, `body`, `kind`, `categoryID`, `due`), `deleteItem`, `restoreItem`, `categories`; `DueLabels`, `DatePreset` (Task 3); `UndoCenter.offer` (Task 4); `AppRouter.expandedItemID`, `perform` (Task 6); `CategorySnapshot.color/displayName`, `layoutDirection(of:)` (Task 6).
- Produces: `ItemRow(store:item:showsDay: = true, showsCategory: = true)` — used by Tasks 9 and 10. Identifiers: `checkbox-<title>`, `titleField`, `dateChip`, `categoryChip`, `kindChip`. `ItemEditor(store:item:close:)`.

Row behavior (spec §9.2): tap the checkbox to complete; tap the row to edit in place — the title becomes a field, then notes, then glass chips for date, category and kind; Return in the title saves and closes, a tap between the fields closes; swipe right completes, swipe left deletes with an Undo toast; long-press offers Move to, Make Memo/Task, Date presets, Delete. The date chip's "Pick a Date…" / "Add Time…" show an inline calendar / time wheel under the chips (no popovers, spec §9.1).

- [ ] **Step 1: Write the failing UI tests** — add the helper right after `setUp()`:

```swift
    private func quickAdd(_ text: String) {
        app.buttons["quickAddBar"].tap()
        let field = app.textFields["quickAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(text + "\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "composer should close after adding")
    }
```

and these tests after `testComposerAddsOnlyWithATitle`:

```swift
    func testQuickAddShowsTheItemInUpcoming() {
        quickAdd("Buy milk tomorrow")
        XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tomorrow"].exists)
    }

    func testCompletingATaskRemovesItFromUpcoming() {
        quickAdd("Call Dan today")
        let checkbox = app.buttons["checkbox-Call Dan"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        checkbox.tap()
        XCTAssertTrue(app.staticTexts["Call Dan"].waitForNonExistence(timeout: 5))
    }
```

- [ ] **Step 2: Run them to see them fail**

```bash
xcodebuild -project Scribe.xcodeproj -scheme Scribe -destination id=E4ABB0FF-1B3F-43D4-A4AB-AA656FCEA434 -derivedDataPath build/dd-sim test 2>&1 | grep -E "error:|Test Case"
```

Expected: the two new tests FAIL — the Upcoming tab is still the placeholder.

- [ ] **Step 3: Implement** — create:

`App/iOS/ItemEditor.swift`
```swift
import ScribeCore
import SwiftUI

/// A tapped row's inline editor (spec §9.2): title, notes, and a row of
/// glass chips for date, category and kind. Text saves on Return (which also
/// closes the editor) and when the editor goes away; chips save immediately.
struct ItemEditor: View {
    let store: any ItemStore
    let item: ItemSnapshot
    let close: () -> Void

    private enum InlinePicker { case date, time }

    @Environment(AppRouter.self) private var router
    @State private var title: String
    @State private var notes: String
    @State private var picker: InlinePicker?

    private let calendar = Calendar.autoupdatingCurrent
    private var today: LocalDay { LocalDay(Date(), calendar: calendar) }

    init(store: any ItemStore, item: ItemSnapshot, close: @escaping () -> Void) {
        self.store = store
        self.item = item
        self.close = close
        _title = State(initialValue: item.title)
        _notes = State(initialValue: item.body)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: $title)
                .font(.body.weight(.medium))
                .layoutDirection(of: title)
                .submitLabel(.done)
                .onSubmit {
                    saveText()
                    close()
                }
                .accessibilityIdentifier("titleField")
            TextField("Notes", text: $notes, axis: .vertical)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1...6)
                .layoutDirection(of: notes)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    dateChip
                    categoryChip
                    kindChip
                }
                .font(.subheadline)
                .controlSize(.small)
            }
            .scrollClipDisabled() // clipping draws a grey band behind the glass chips
            switch picker {
            case .date:
                DatePicker("Date", selection: dayBinding, displayedComponents: .date)
                    .datePickerStyle(.graphical)
            case .time:
                DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            case nil:
                EmptyView()
            }
        }
        .onDisappear(perform: saveText)
    }

    // MARK: Chips

    private var dateChip: some View {
        Menu {
            ForEach(DatePreset.allCases, id: \.self) { preset in
                Button(preset.title) { setDue(preset.applied(to: item.due, today: today, calendar: calendar)) }
            }
            Button("Pick a Date…", systemImage: "calendar") { show(.date) }
            if let due = item.due {
                Button(due.minute == nil ? "Add Time…" : "Change Time…", systemImage: "clock") { show(.time) }
                if due.minute != nil {
                    Button("Remove Time") { setDue(DueDate(day: due.day)) }
                }
                Button("Remove Date", role: .destructive) {
                    picker = nil
                    setDue(nil)
                }
            }
        } label: {
            Label(item.due.map { DueLabels().due($0, today: today) } ?? "No Date", systemImage: "calendar")
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("dateChip")
    }

    private var categoryChip: some View {
        let category = item.categoryID.flatMap { id in store.categories.first { $0.id == id } }
        return Menu {
            Picker("Category", selection: categoryBinding) {
                Label("Inbox", systemImage: "tray").tag(UUID?.none)
                ForEach(store.categories) { category in
                    Text(category.displayName).tag(UUID?.some(category.id))
                }
            }
        } label: {
            Label {
                Text(category?.displayName ?? "Inbox")
            } icon: {
                Image(systemName: category == nil ? "tray" : "circle.fill")
                    .foregroundStyle(category?.color ?? .secondary)
            }
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("categoryChip")
    }

    private var kindChip: some View {
        Button(item.kind == .task ? "Task" : "Memo",
               systemImage: item.kind == .task ? "checkmark.circle" : "note.text") {
            update { $0.kind = item.kind == .task ? .memo : .task }
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("kindChip")
    }

    // MARK: Bindings

    private var categoryBinding: Binding<UUID?> {
        Binding(get: { item.categoryID }, set: { id in update { $0.categoryID = id } })
    }

    /// The inline calendar edits the day and keeps the time.
    private var dayBinding: Binding<Date> {
        Binding(
            get: { (item.due?.day ?? today).date(calendar: calendar) },
            set: { date in setDue(DueDate(day: LocalDay(date, calendar: calendar), minute: item.due?.minute)) }
        )
    }

    /// The inline wheel edits the time and keeps the day.
    private var timeBinding: Binding<Date> {
        Binding(
            get: { (item.due?.day ?? today).date(atMinute: item.due?.minute ?? 9 * 60, calendar: calendar) },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                setDue(DueDate(day: item.due?.day ?? today, minute: (parts.hour ?? 0) * 60 + (parts.minute ?? 0)))
            }
        )
    }

    // MARK: Saving

    private func show(_ inline: InlinePicker) {
        withAnimation(.snappy) { picker = picker == inline ? nil : inline }
    }

    private func saveText() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != item.title || notes != item.body else { return }
        guard !trimmed.isEmpty else {
            title = item.title // an empty title isn't allowed (spec §13); put the old one back
            return
        }
        update {
            $0.title = trimmed
            $0.body = notes
        }
    }

    private func setDue(_ due: DueDate?) {
        guard due != item.due else { return }
        update { $0.due = due }
    }

    private func update(_ edit: (inout ItemEdit) -> Void) {
        router.perform { try store.updateItem(item.id, edit) }
    }
}
```

`App/iOS/ItemRow.swift`
```swift
import ScribeCore
import SwiftUI

/// One item in any list: checkbox (tasks) or note glyph (memos), title in
/// its own text direction, due/category line. Tap to edit in place (the
/// editor takes the title's place; a tap between its fields closes it);
/// swipe right to complete, left to delete with Undo (spec §9.2).
struct ItemRow: View {
    let store: any ItemStore
    let item: ItemSnapshot
    var showsDay = true
    var showsCategory = true

    @Environment(AppRouter.self) private var router
    @Environment(UndoCenter.self) private var undo

    private var category: CategorySnapshot? {
        item.categoryID.flatMap { id in store.categories.first { $0.id == id } }
    }

    private var isExpanded: Bool { router.expandedItemID == item.id }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            marker
            if isExpanded {
                ItemEditor(store: store, item: item) { setExpanded(false) }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .strikethrough(item.isDone)
                        .foregroundStyle(item.isDone ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutDirection(of: item.title)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(.rect)
                .onTapGesture { setExpanded(true) }
            }
        }
        .background {
            if isExpanded {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { setExpanded(false) }
            }
        }
        .swipeActions(edge: .leading) {
            if item.kind == .task {
                Button(item.isDone ? "Not Done" : "Done", systemImage: "checkmark") { toggleDone() }
                    .tint(.green)
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) { delete() }
        }
        .contextMenu { menu }
    }

    @ViewBuilder private var marker: some View {
        switch item.kind {
        case .task:
            Button { toggleDone() } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(category?.color ?? .accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isDone ? "Mark not done" : "Mark done")
            .accessibilityIdentifier("checkbox-\(item.title)")
        case .memo:
            Image(systemName: "note.text")
                .font(.title3)
                .foregroundStyle(.tertiary)
        }
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let due = item.due {
            let labels = DueLabels()
            let today = LocalDay(Date(), calendar: labels.calendar)
            if showsDay {
                parts.append(labels.due(due, today: today))
            } else if let minute = due.minute {
                parts.append(labels.time(minute))
            }
        }
        if showsCategory, let category { parts.append(category.displayName) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder private var menu: some View {
        Menu("Move to", systemImage: "folder") {
            Button("Inbox", systemImage: "tray") { update { $0.categoryID = nil } }
            ForEach(store.categories) { category in
                Button(category.displayName) { update { $0.categoryID = category.id } }
            }
        }
        Button(item.kind == .task ? "Make Memo" : "Make Task",
               systemImage: item.kind == .task ? "note.text" : "checkmark.circle") {
            update { $0.kind = item.kind == .task ? .memo : .task }
        }
        Menu("Date", systemImage: "calendar") {
            let calendar = Calendar.autoupdatingCurrent
            let today = LocalDay(Date(), calendar: calendar)
            ForEach(DatePreset.allCases, id: \.self) { preset in
                Button(preset.title) { update { $0.due = preset.applied(to: $0.due, today: today, calendar: calendar) } }
            }
            Button("No Date") { update { $0.due = nil } }
        }
        Button("Delete", systemImage: "trash", role: .destructive) { delete() }
    }

    private func setExpanded(_ expanded: Bool) {
        withAnimation(.snappy) { router.expandedItemID = expanded ? item.id : nil }
    }

    private func toggleDone() {
        router.perform { try store.setDone(item.id, !item.isDone) }
    }

    private func update(_ edit: (inout ItemEdit) -> Void) {
        router.perform { try store.updateItem(item.id, edit) }
    }

    private func delete() {
        let snapshot = item
        router.perform {
            try store.deleteItem(snapshot.id)
            if router.expandedItemID == snapshot.id { router.expandedItemID = nil }
            undo.offer("Deleted “\(snapshot.title)”") { try store.restoreItem(snapshot) }
        }
    }
}
```

`App/iOS/UpcomingView.swift`
```swift
import ScribeCore
import SwiftUI

/// Overdue tasks, then today and the next six days (spec §6).
struct UpcomingView: View {
    let store: any ItemStore

    var body: some View {
        let now = Date()
        let agenda = store.agenda(.all, now: now)
        let labels = DueLabels()
        let today = LocalDay(now, calendar: labels.calendar)
        List {
            if !agenda.overdue.isEmpty {
                Section {
                    ForEach(agenda.overdue) { ItemRow(store: store, item: $0) }
                } header: {
                    Text("Overdue").foregroundStyle(.red)
                }
            }
            ForEach(agenda.days, id: \.day) { day in
                Section(labels.dayTitle(day.day, today: today)) {
                    ForEach(day.items) { ItemRow(store: store, item: $0, showsDay: false) }
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
    }
}
```

In `App/iOS/RootView.swift`, replace `ComingNext(title: "Upcoming")` with `UpcomingView(store: store)`.

- [ ] **Step 4: Run all UI tests**

Same command as Step 2. Expected: 4 tests passed, no warnings.

- [ ] **Step 5: Commit**

```bash
git add App UITests
git commit -m "Upcoming agenda, item rows, inline editor with glass chips"
```

---

### Task 9: Categories and the category screen

**Files:**
- Create: `App/iOS/CategoriesView.swift`, `App/iOS/CategoryDetailView.swift`
- Modify: `App/iOS/RootView.swift`
- Test: `UITests/ScribeUITests.swift`

**Interfaces:**
- Consumes: `ItemStore.categories`, `items(.inbox / .category(id))`, `addCategory(CategoryDraft(name:colorName:))`, `updateCategory(_:_:)`, `moveCategories(fromOffsets:toOffset:)`, `deleteCategory` → `CategoryDeletion`, `restoreCategory` (Task 1); `CategoryPalette.colorNames`, `suggestedColorName(avoiding:)`, `StoreError.localizedDescription` (Task 3); `CategoryContents` (Task 4); `ItemRow` (Task 8); `AppRouter.Destination`, `perform` (Task 6).
- Produces: `CategoriesView(store:)`, `CategoryDetailView(store:destination:)`. Identifiers: `inboxRow`, `category-<name>`, `newCategoryField`, `inlineError`; toolbar button labelled "Add Category".

Screen behavior (spec §9.2, §13): Inbox row first, then categories with color dot, emoji + name and open count (before the chevron, hidden at zero); "+" adds inline with the next unused palette color; Edit reorders by drag; swipe/long-press to Edit (inline emoji, name, palette) or Delete (Undo toast restores the category and its items). A duplicate name shows "There’s already a category with that name." under the field and keeps it open. The category screen lists open tasks, then "Memos", then a collapsed "Done (n)".

- [ ] **Step 1: Write the failing UI tests** — add after `testCompletingATaskRemovesItFromUpcoming`:

```swift
    func testDeleteThenUndoInTheInbox() {
        quickAdd("Water plants")
        app.tabBars.buttons["Categories"].tap()
        app.buttons["inboxRow"].tap()
        let row = app.staticTexts["Water plants"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        let undo = app.buttons["undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    func testDuplicateCategoryNameIsExplainedInline() {
        app.tabBars.buttons["Categories"].tap()
        for _ in 0..<2 {
            app.buttons["Add Category"].tap()
            let field = app.textFields["newCategoryField"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.typeText("Work\n")
        }
        let message = app.staticTexts["inlineError"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertEqual(message.label, "There’s already a category with that name.")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
```

- [ ] **Step 2: Run them to see them fail**

Same `xcodebuild … test` command as Task 8. Expected: the two new tests FAIL — the Categories tab is still the placeholder.

- [ ] **Step 3: Implement** — create:

`App/iOS/CategoriesView.swift`
```swift
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
```

`App/iOS/CategoryDetailView.swift`
```swift
import ScribeCore
import SwiftUI

/// One category (or the Inbox): open tasks, memos, then a collapsed Done
/// section (spec §9.2).
struct CategoryDetailView: View {
    let store: any ItemStore
    let destination: AppRouter.Destination

    @State private var showsDone = false

    private var filter: ItemFilter {
        switch destination {
        case .inbox: .inbox
        case .category(let id): .category(id)
        }
    }

    private var title: String {
        switch destination {
        case .inbox: "Inbox"
        case .category(let id): store.categories.first { $0.id == id }?.displayName ?? "Category"
        }
    }

    var body: some View {
        let contents = CategoryContents(items: store.items(filter))
        List {
            if !contents.openTasks.isEmpty {
                Section {
                    ForEach(contents.openTasks) { ItemRow(store: store, item: $0, showsCategory: false) }
                }
            }
            if !contents.memos.isEmpty {
                Section("Memos") {
                    ForEach(contents.memos) { ItemRow(store: store, item: $0, showsCategory: false) }
                }
            }
            if !contents.done.isEmpty {
                Section {
                    DisclosureGroup("Done (\(contents.done.count))", isExpanded: $showsDone) {
                        ForEach(contents.done) { ItemRow(store: store, item: $0, showsCategory: false) }
                    }
                }
            }
        }
        .overlay {
            if contents.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "tray", description: Text("Add something with the bar below."))
            }
        }
        .navigationTitle(title)
    }
}
```

In `App/iOS/RootView.swift`, replace

```swift
                NavigationStack(path: $router.categoriesPath) {
                    ComingNext(title: "Categories")
                }
```

with

```swift
                NavigationStack(path: $router.categoriesPath) {
                    CategoriesView(store: store)
                        .navigationDestination(for: AppRouter.Destination.self) { destination in
                            CategoryDetailView(store: store, destination: destination)
                        }
                }
```

- [ ] **Step 4: Run all UI tests**

Expected: 6 tests passed, no warnings. `UITests/ScribeUITests.swift` now reads exactly:

```swift
import XCTest

/// Smoke tests for the iPhone app (spec §15). The app launches with
/// `-uiTesting`: an in-memory store, no iCloud.
@MainActor
final class ScribeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    private func quickAdd(_ text: String) {
        app.buttons["quickAddBar"].tap()
        let field = app.textFields["quickAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(text + "\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "composer should close after adding")
    }

    func testLaunchShowsTheTabs() {
        XCTAssertTrue(app.tabBars.buttons["Upcoming"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Categories"].exists)
    }

    func testComposerAddsOnlyWithATitle() {
        app.buttons["quickAddBar"].tap()
        let field = app.textFields["quickAddField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Add"].isEnabled)
        field.typeText("Buy milk tomorrow\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "composer should close after adding")
    }

    func testQuickAddShowsTheItemInUpcoming() {
        quickAdd("Buy milk tomorrow")
        XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tomorrow"].exists)
    }

    func testCompletingATaskRemovesItFromUpcoming() {
        quickAdd("Call Dan today")
        let checkbox = app.buttons["checkbox-Call Dan"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        checkbox.tap()
        XCTAssertTrue(app.staticTexts["Call Dan"].waitForNonExistence(timeout: 5))
    }

    func testDeleteThenUndoInTheInbox() {
        quickAdd("Water plants")
        app.tabBars.buttons["Categories"].tap()
        app.buttons["inboxRow"].tap()
        let row = app.staticTexts["Water plants"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        let undo = app.buttons["undoButton"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    func testDuplicateCategoryNameIsExplainedInline() {
        app.tabBars.buttons["Categories"].tap()
        for _ in 0..<2 {
            app.buttons["Add Category"].tap()
            let field = app.textFields["newCategoryField"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.typeText("Work\n")
        }
        let message = app.staticTexts["inlineError"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertEqual(message.label, "There’s already a category with that name.")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add App UITests
git commit -m "Categories list with inline add/edit/reorder/delete+undo, category screen"
```

---

### Task 10: Search

**Files:**
- Create: `App/iOS/SearchView.swift`
- Modify: `App/iOS/RootView.swift`

**Interfaces:**
- Consumes: `ItemStore.items(.search(query))` (title + body, done included), `SearchGroup.make` (Task 4), `ItemRow` (Task 8).
- Produces: `SearchView(store:)`; `ComingNext` is gone.

- [ ] **Step 1: Implement** — create `App/iOS/SearchView.swift`:

```swift
import ScribeCore
import SwiftUI

/// Title + body search across everything, including done items, grouped by
/// category (spec §9.2).
struct SearchView: View {
    let store: any ItemStore
    @State private var query = ""

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let groups = SearchGroup.make(items: store.items(.search(trimmed)), categories: store.categories)
        List {
            ForEach(groups) { group in
                Section(group.category?.displayName ?? "Inbox") {
                    ForEach(group.items) { ItemRow(store: store, item: $0, showsCategory: false) }
                }
            }
        }
        .overlay {
            if trimmed.isEmpty {
                ContentUnavailableView("Search", systemImage: "magnifyingglass", description: Text("Titles and notes, including done items."))
            } else if groups.isEmpty {
                ContentUnavailableView.search(text: trimmed)
            }
        }
        .searchable(text: $query)
        .navigationTitle("Search")
    }
}
```

In `App/iOS/RootView.swift`, replace `ComingNext(title: "Search")` with `SearchView(store: store)` and delete the `ComingNext` struct and its doc comment. The file now reads exactly:

```swift
import ScribeCore
import SwiftUI

/// iPhone app: floating glass tab bar with Upcoming, Categories and Search,
/// and the quick-add capsule above it on every tab (spec §9.2).
struct RootView: View {
    let store: SwiftDataItemStore

    @State private var router = AppRouter()
    @State private var undo = UndoCenter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Upcoming", systemImage: "calendar", value: AppRouter.Tab.upcoming) {
                NavigationStack {
                    UpcomingView(store: store)
                }
            }
            Tab("Categories", systemImage: "square.stack", value: AppRouter.Tab.categories) {
                NavigationStack(path: $router.categoriesPath) {
                    CategoriesView(store: store)
                        .navigationDestination(for: AppRouter.Destination.self) { destination in
                            CategoryDetailView(store: store, destination: destination)
                        }
                }
            }
            Tab(value: AppRouter.Tab.search, role: .search) {
                NavigationStack {
                    SearchView(store: store)
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            QuickAddBar()
        }
        .overlay(alignment: .bottom) {
            UndoToast()
        }
        .sheet(isPresented: $router.isComposing) {
            QuickAddSheet(store: store, categoryID: router.composerCategoryID)
        }
        .alert("Couldn’t Save", isPresented: Binding(
            get: { router.alertMessage != nil },
            set: { if !$0 { router.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(router.alertMessage ?? "")
        }
        .environment(router)
        .environment(undo)
        .onOpenURL { url in
            if let link = DeepLink(url: url) { router.open(link, store: store) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refresh() }
        }
    }
}
```

- [ ] **Step 2: Build both platforms and run all tests**

```bash
cd Core && swift test 2>&1 | tail -1 && cd ..
xcodebuild -project Scribe.xcodeproj -scheme Scribe -destination "platform=macOS" -derivedDataPath build/dd build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "warning:|error:|\*\* BUILD"
xcodebuild -project Scribe.xcodeproj -scheme Scribe -destination id=E4ABB0FF-1B3F-43D4-A4AB-AA656FCEA434 -derivedDataPath build/dd-sim test 2>&1 | grep -E "warning:|error:|Test Case|\*\* TEST"
```

Expected: Core all pass; macOS `** BUILD SUCCEEDED **`; 6 UI tests passed; no warnings.

- [ ] **Step 3: Commit**

```bash
git add App
git commit -m "Search tab: titles and notes across everything, grouped by category"
```

---

### Task 11: Visual pass, iPhone install, docs

**Files:**
- Temporary (never committed): `UITests/ScreenshotTour.swift`
- Modify: `README.md`, `docs/backlog.md`

- [ ] **Step 1: Seed the simulator and look at every screen.** Typing through the simulator tools drops characters, so seed with a throwaway UI test. Create `UITests/ScreenshotTour.swift`:

```swift
import XCTest

/// Throwaway: fills the app with realistic data and parks on each screen
/// so screenshots can be taken. Delete before committing.
@MainActor
final class ScreenshotTour: XCTestCase {
    func testTour() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        func add(_ text: String) {
            app.buttons["quickAddBar"].tap()
            let field = app.textFields["quickAddField"]
            _ = field.waitForExistence(timeout: 5)
            field.typeText(text + "\n")
            _ = field.waitForNonExistence(timeout: 5)
        }
        app.tabBars.buttons["Categories"].tap()
        for name in ["Work", "Thailand", "Bulgaria"] {
            app.buttons["Add Category"].tap()
            let field = app.textFields["newCategoryField"]
            _ = field.waitForExistence(timeout: 5)
            field.typeText(name + "\n")
        }
        app.tabBars.buttons["Upcoming"].tap()
        add("Book flights fri 18:00 #thailand")
        add("Q3 report tomorrow 9am #work")
        add("Pay arnona today")
        add("Call mom tonight at 9")
        add("לקנות מתנה לאמא מחר #bulgaria")
        add("Passport + insurance docs fri #bulgaria !memo")
        add("Door code 4821 #work !memo")
        print("TOUR: upcoming"); sleep(15)
        app.staticTexts["Book flights"].tap()
        print("TOUR: editor"); sleep(10)
        app.buttons["dateChip"].tap()
        print("TOUR: date menu"); sleep(10)
        app.buttons["Pick a Date…"].tap()
        print("TOUR: calendar"); sleep(10)
        app.tabBars.buttons["Categories"].tap()
        print("TOUR: categories"); sleep(10)
        app.buttons["category-Bulgaria"].tap()
        print("TOUR: bulgaria"); sleep(10)
        app.buttons["quickAddBar"].tap()
        app.textFields["quickAddField"].typeText("call mom tomorrow 9am #family")
        print("TOUR: composer"); sleep(10)
    }
}
```

Run it in the background (`… test -only-testing:ScribeUITests/ScreenshotTour > build/tour.log`) and take a simulator screenshot at each `TOUR:` line. Check against spec §9: floating glass tab bar with a separate search circle; quick-add capsule above it with a tinted plus; Hebrew titles right-aligned, English left; "Overdue" in red when present; memos show a faint note glyph and no checkbox; category dots red/orange/yellow; counts sit before the chevron; editor shows title, notes and three glass chips with no grey band behind them; composer shows Tomorrow · 09:00 · New category “family” chips. Fix anything off, rerun the six smoke tests, then **delete `UITests/ScreenshotTour.swift`**.

- [ ] **Step 2: Install on the author's iPhone.** Signing must run outside the command sandbox (Apple's auth hosts are blocked inside it).

```bash
UDID=$(cat build/udid.txt)   # 00008150-0002202A22F8401C
xcodebuild -project Scribe.xcodeproj -scheme Scribe -destination "id=$UDID" -derivedDataPath build/dd-signed -allowProvisioningUpdates -allowProvisioningDeviceRegistration build 2>&1 | grep -E "error:|\*\* BUILD"
xcrun devicectl device install app --device "$UDID" build/dd-signed/Build/Products/Debug-iphoneos/Scribe.app
xcrun devicectl device process launch --device "$UDID" com.noamchuri.scribe
```

Expected: `** BUILD SUCCEEDED **`, the app installs and opens on the iPhone with the real iCloud store (existing Phase 0/1 data, if any, appears). Do not drive the author's real data with automation (spec §15); ask the author to try it.

- [ ] **Step 3: Update the docs.** In `README.md` replace the "Status" paragraph with:

```markdown
## Status

iPhone app usable (Phase 2): Upcoming, categories, inline editing, quick-add with English + Hebrew parsing, search, iCloud sync. Mac app, widgets, notifications and settings come next.
```

and add under "Development":

~~~markdown
### Tests

```bash
cd Core && swift test                      # Core unit tests
xcodebuild -project Scribe.xcodeproj -scheme Scribe \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" test   # UI smoke tests
```
~~~

In `docs/backlog.md`, delete the whole "## Phase 2 (iPhone app)" section (every item is done), and under "## Phase 3 (Mac app)" add:

```markdown
- **Mac UI** replaces the placeholder `App/macOS/RootView.swift`; reuse `ItemRow`-style rows via shared views where the platforms agree.
```

- [ ] **Step 4: Final run and commit**

```bash
cd Core && swift test 2>&1 | tail -1 && cd ..
xcodebuild -project Scribe.xcodeproj -scheme Scribe -destination id=E4ABB0FF-1B3F-43D4-A4AB-AA656FCEA434 -derivedDataPath build/dd-sim test 2>&1 | grep -E "Test Case|\*\* TEST"
git status --short   # ScreenshotTour.swift must not be listed
git add README.md docs/backlog.md
git commit -m "Docs: Phase 2 status, test commands, backlog"
```

Expected: Core all pass; 6 UI tests passed; clean tree after the commit.
