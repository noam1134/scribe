# Scribe Phase 4 — Widgets, Control, Siri/Shortcuts

**Goal:** Quick-add and "what's coming up" from outside the app: the agenda widget (iPhone home + lock screen, Mac desktop), the "Add to Scribe" Control, and Siri/Shortcuts intents — every add ending in a real category (spec §19).

**Spec:** §4.3 process model, §8 entry points + App Intents, §10 widgets, §12, §13, §15 (`WidgetEntryBuilder` tests), §18 ("iPhone background freshness", "App Intents on device"), §19. Backlog: "Phase 4".

**Architecture:**
- **Core (pure, tested):** `WidgetEntryBuilder` turns items + categories + scope + "data fresh at" into timeline entries (rows, sections, counts, "+N more" fitting, age label). `IntentAdd` resolves spoken/typed text + an optional category into an `ItemDraft` (or "ask for a category"), searches categories by name for Siri, and words the spoken reply. `ItemFilter.all` lets the widget read every item.
- **`Intents/` (compiled into the app AND the widget extension):** `SharedStore` (one `SwiftDataItemStore` per process — the app's syncs with CloudKit, the extension's doesn't; intents running in the app use the app's), `CategoryEntity` + query, `CompleteTaskIntent`, `OpenQuickAddIntent`, `IntentLinkInbox` (hands a link from an intent to the app UI), `FreshnessStamp` (App Group defaults: when the app last knew its data was current).
- **`Widgets/` (extension):** agenda widget (`AppIntentConfiguration` over an optional `CategoryEntity`), its views per family, the configurable "Add to Scribe" Control.
- **`App/` (app only):** `AddItemIntent` + `ScribeShortcuts` (Siri/Shortcuts run in the app process), `WidgetRefresher` (reload timelines after store changes and imports, stamp freshness), `BackgroundRefresh` (iOS `BGAppRefreshTask`).

**Process model (spec §4.3, §18):**

| Path | Runs in | Store |
|---|---|---|
| Widget timeline, widget config query, widget checkbox (`CompleteTaskIntent`) | widget extension | extension container, no CloudKit |
| Control / widget-small "+" (`OpenQuickAddIntent`, `supportedModes = .foreground`) | app (foregrounded) | — (hands `scribe://add` to the UI) |
| Siri / Shortcuts (`AddItemIntent`, app-only) | app (background launch) | the app's CloudKit container via `SharedStore` |
| Widget "+" (medium/large), row tap | deep link into the app | — |

Extension writes land in the shared SQLite file with persistent history; the app's `NSPersistentCloudKitContainer` exports them at its next launch/activation (spec §12) and refreshes on `NSPersistentStoreRemoteChange`.

## Global Constraints

Same as Phase 2 (`docs/superpowers/plans/2026-10-05-phase2-iphone-app.md`), plus:
- Branch `phase4-widgets`; simulator `FBFE7176-C36B-470A-9ED0-D2E10AE74C27` ("Scribe P4") only.
- No SwiftData model changes. `ScribeCore` stays free of WidgetKit/AppIntents/SwiftUI.
- Shared-file edits (`project.yml`, `App/ScribeApp.swift`, `App/Shared/StoreLoader.swift`, `App/Info.plist`, `docs/backlog.md`) are small, localized hooks; everything else is new files.
- `ItemFilter.all` uses the exact text agreed with Phase 5 (last case, `/// Every item, done ones included.`; `case .all: return all.sorted(by: ItemOrdering.list)`).

## File Map

| File | Responsibility | Task |
|---|---|---|
| `Core/…/Store/ItemStore.swift`, `SwiftDataItemStore.swift` | `ItemFilter.all` | 1 |
| `Core/Tests/…/SharedFileTests.swift` | A second container on the same file sees writes; non-CloudKit writes are in persistent history (the export precondition) | 1 |
| `Core/…/Widgets/WidgetEntryBuilder.swift` | Entries, rows, sections, counts, fitting, age label | 2 |
| `Core/…/Intents/IntentAdd.swift` | Text + category → draft / ask; category search; reply wording | 3 |
| `Intents/*.swift` | `SharedStore`, `CategoryEntity`, `CompleteTaskIntent`, `OpenQuickAddIntent`, `IntentLinkInbox`, `FreshnessStamp`, `IntentError` | 4 |
| `App/Shared/StoreLoader.swift`, `App/ScribeApp.swift` | Store from `SharedStore`; `WidgetRefresher`; intent links → `pendingLink`; BG task | 4, 6 |
| `Widgets/*.swift` | Agenda widget, views, Control, bundle | 5 |
| `App/Shared/AddItemIntent.swift`, `ScribeShortcuts.swift`, `WidgetRefresher.swift`; `App/iOS/BackgroundRefresh.swift` | Siri/Shortcuts, widget reloads, freshness, background refresh | 6 |
| `project.yml`, `App/Info.plist` | `Intents/` in both targets, `Styling.swift` in the widget, `fetch` mode, BG identifier | 4, 6 |
| `UITests/ScribeUITests.swift` | Add link opens the composer | 7 |

## Tasks

### Task 1 — `ItemFilter.all` and the shared-file write path
- `ItemFilter.all` + store case. Test: returns done and open items across categories and the Inbox.
- `SharedFileTests`: two `ModelContainer`s (no CloudKit) on one temp file — a write through B is read by a fresh context of A; B's insert appears in `fetchHistory` (persistent history is on without CloudKit, which the app's mirroring needs to export extension writes).

### Task 2 — `WidgetEntryBuilder` (Core, TDD)
- `timeline(items:categories:categoryID:now:freshAt:) -> WidgetTimeline` (`entries`, `refreshAt`). Entries at now, each open timed item's due time later today, the moment the data turns stale (if today), and the next local midnight; `refreshAt` = next midnight. Each entry = the §6 agenda at its date.
- `WidgetEntry { date, category (scope; nil = all), content: .agenda | .categoryMissing | .storeUnavailable, staleLabel }`; `unavailable(now:)` retries in 15 min.
- `WidgetAgenda { sections, todayCount, dueTaskCount, itemCount, isEmpty, fitting(lines:), firstRows(_:) }`; `WidgetSection { title, isOverdue, rows }`; `WidgetRow { id, title, kind, category, detail, isLate }` — detail is the time ("09:30") or, for overdue rows, the day ("Yesterday").
- Tests: empty; overdue section first + late; memos (never late, past memo drops out); category filter; deleted category; done tasks excluded; entry dates; midnight entry turns today's open task overdue; a timed task turns late at its time; counts; many items → fitting reserves a "+N more" line; first rows; stale label (fresh, same day, yesterday); unavailable.

### Task 3 — `IntentAdd` (Core, TDD)
- `resolve(_:categoryID:categories:now:calendar:) -> .ready(ItemDraft) | .needsCategory(ItemDraft) | .noCategories | .emptyTitle`. Order: explicit category (if it exists) → matched `#tag` → the only category → ask. Unknown `#tag` stays in the title (as `nonInteractiveDraft`). Never Inbox.
- `categories(matching:in:)` — exact, then prefix, then contains, normalized like tags.
- `reply(title:categoryName:due:now:calendar:locale:)` — "Added ‘Book flights’ to Thailand, Friday." / "…, tomorrow at 09:00." / "…, 20 October." / no date → "Added ‘X’ to Y."

### Task 4 — Shared intents glue + store wiring
- `SharedStore.open()` (MainActor, cached on success; `-uiTesting` → in-memory). `StoreLoader.load()` uses it.
- `CategoryEntity` (`id: UUID`, name, emoji) + `CategoryQuery: EntityStringQuery`.
- `CompleteTaskIntent(itemID:)` — not discoverable; `setDone(true)`, missing item is a no-op; reload timelines.
- `OpenQuickAddIntent(category?)` — `supportedModes = .foreground(.immediate)`; sets `IntentLinkInbox.shared.link = .add(categoryID:)`; `ScribeApp` forwards it into `loader.pendingLink`.
- `project.yml`: `Intents` in both targets; `App/Shared/Styling.swift` also in the widget (category colors, text direction).

### Task 5 — Widget extension
- `AgendaWidget`: `AppIntentConfiguration(intent: AgendaWidgetIntent)` (`category: CategoryEntity?`, nil = all), families iOS small/medium/large/accessoryRectangular/accessoryCircular, macOS small/medium/large. Provider reads `SharedStore` + `FreshnessStamp`, maps the plan to `Timeline(.after(refreshAt))`; store failure → error entry.
- Views: header (scope + "+"), sections with interactive checkboxes (`Button(intent: CompleteTaskIntent)`), memo glyph, row `Link` to `scribe://item/<id>`, "+N more", empty state "Nothing in the next 7 days", error/missing states, age label. Small: today's count + next 3; rectangular: scope + next 2; circular: due-today + overdue task count. Accented mode: category colors yield to the tint (`widgetAccentable`).
- `AddToScribeControl`: `AppIntentControlConfiguration` (optional category) → `ControlWidgetButton(action: OpenQuickAddIntent(category:))`, iOS + macOS.

### Task 6 — App side: Siri/Shortcuts, reloads, background refresh
- `AddItemIntent(text:category:)` — prompt "What should I add?"; `IntentAdd.resolve`; `.needsCategory` → `$category.requestDisambiguation`; `.noCategories` → error "Add a category in Scribe first."; replies with `IntentAdd.reply`; reloads timelines.
- `ScribeShortcuts` (English phrases) for `AddItemIntent` and `OpenQuickAddIntent`.
- `WidgetRefresher`: debounced `reloadAllTimelines()` on `NSPersistentStoreRemoteChange`; on a successful CloudKit import, stamp freshness + reload; iOS entering background → stamp, reload, schedule BG refresh.
- `BackgroundRefresh` (iOS): `BGAppRefreshTask` `com.noamchuri.scribe.refresh`, ≥30 min; opens the store (which can trigger the CloudKit import), waits ≤20 s for an import to finish, stamps freshness if one did, refreshes, reloads widgets. `UIBackgroundModes += fetch`, `BGTaskSchedulerPermittedIdentifiers`.

### Task 7 — Verification and docs
- UI test: `scribe://add` opens the composer (the widget "+" path). Existing 7 stay green.
- Simulator checks (manual, recorded in the report): Shortcuts lists the actions; Siri-style add with disambiguation; widget renders; widget checkbox completes in the extension and the app shows it; Control opens the composer; cold-launch `scribe://item/<id>`.
- iOS + macOS builds with zero warnings; backlog updated.

## Decisions

1. **Siri category rule (§19):** explicit Category parameter → `#tag` → if exactly one category exists, use it (the reply names it) → otherwise Siri asks with a list (disambiguation). No categories at all → the intent fails with "Add a category in Scribe first." An unknown `#tag` stays in the title, as in the composer.
2. **Process for each intent:** `AddItemIntent` is compiled only into the app, so Siri/Shortcuts always run it in the app process with the CloudKit container. `CompleteTaskIntent` runs in the widget extension. `OpenQuickAddIntent` foregrounds the app (`supportedModes`, iOS 26's replacement for `openAppWhenRun`) and hands the link over in-process.
3. **Small-widget "+":** small widgets can't hold a `Link`, so their "+" is a `Button(intent: OpenQuickAddIntent)`; medium/large use the `scribe://add?category=` link. Lock-screen widgets aren't interactive: tapping opens Upcoming.
4. **Timed entries:** a task whose time has passed today shows its time in red ("late"); that is what the per-due-time entries change. Overdue rows show their day instead of a time.
5. **Data age (§18 fallback):** the app stamps "fresh at" after each successful CloudKit import and, on iPhone, when it leaves the foreground (while in front it receives pushes). Widgets show "Updated 09:14" / "Updated yesterday" once the data is 2 hours old. Mac: import stamps only (no pushes, §18).
6. **Deleted widget category:** the widget says the category was deleted and to edit the widget (no silent fallback to All).
7. **Widget configuration:** an empty Category means all categories (spec: nil = All).
8. **Control is configurable:** optional category, so e.g. the Action Button can open quick-add in Thailand.
9. **`CompleteTaskIntent` is hidden from Shortcuts** (`isDiscoverable = false`) — it takes a raw item id.

## Simulator verification (2026-10-05, iPhone 17 Pro, iOS 26.3)

Driven with throwaway XCUITest scripts against SpringBoard and Shortcuts; process names from the `com.noamchuri.scribe` log subsystem and the store's persistent history.

| Check | Result |
|---|---|
| Widget gallery lists Scribe → Upcoming (small, medium, large; lock screen rectangular, circular) | Yes, all render (light, dark, lock screen) |
| Widget shows the real store; configured with a category (picker lists categories via `CategoryQuery` in the extension) | Yes |
| Widget checkbox | Runs `CompleteTaskIntent` in **ScribeWidgets**; item marked done in the shared file (history transaction by `com.noamchuri.scribe.widgets`); both widgets reload; the app shows it done |
| Small-widget "+" and the Control | Run `OpenQuickAddIntent` in **Scribe** (app brought forward); composer opens |
| Medium/large "+", row tap | `scribe://add` opens the composer; `scribe://item/<id>` opens the item's category with the row expanded (also from a cold launch) |
| Shortcuts | Library shows Scribe with "Add to Scribe" and "Quick Add". Running Add to Scribe: "What should I add?" → "Buy milk tomorrow 9am" → "Which category should ‘Buy milk’ go in?" (thailand / work) → "Added ‘Buy milk’ to work, tomorrow at 09:00." — ran in **Scribe** |
| Control gallery | "Add to Scribe" listed under Scribe; adds to Control Center; tapping opens the composer |
| Background refresh | `BGTaskScheduler.submit` fails with `Unavailable` in the simulator (expected); device only |
| Freshness stamp | Written to the App Group defaults when the app enters the background |

Found and fixed while checking: an item or Upcoming link (widget row, widget background) opened underneath a composer left open earlier; those links now close it.

## Review fixes (2026-10-05)

- `WidgetRefresher` became `StoreChangeRelay`, started with `SyncRefresher` by `AppProcess` whenever the app process first opens its store (`SharedStore.open()` → `processDidOpen`, defined per target). `StoreChanged.notify()` (Intents/) is the one per-process "store changed" signal: widget + Control reloads, then registered observers (notification rescheduling joins at the Phase 5 merge).
- A widget configured for a deleted category gets a `CategoryEntity.deleted` placeholder and shows "Category deleted" (confirmed broken first: it silently switched to all categories).
- Widget checkboxes: 26×22 pt tap area, "Complete <title>".
- Background refresh: cold launch vs warm wake (20 s / 5 s import wait), cancellation-aware.
- Widget timelines read `datedOpenItems()` (open items with a date) instead of every item.
- `CompleteTaskIntent` runs in the app process if it also conforms to `LiveActivityIntent` (checked in the simulator); not adopted yet.
