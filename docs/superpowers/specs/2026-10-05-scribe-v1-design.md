# Scribe v1 — Design Spec

Date: 2026-10-05
Status: Draft for review

## 1. Intent

Scribe is a personal notes-and-tasks app for one person (the author), running natively on iPhone and Mac with the same data on both, always up to date.

What makes it different from Apple Notes / Reminders / Obsidian:

- **Categories hold items.** Categories are life areas or projects (Work, Thailand, Bulgaria…). Items live inside them.
- **Items are either tasks or memos.** A task is something to do (has a checkbox). A memo is something to remember (no checkbox). Both can have a date.
- **"Upcoming" everywhere.** Widgets on the home screen, lock screen and Mac desktop show what is coming up in the next days.
- **Quick-add from everywhere.** One parser, many entry points: in-app capsule, widget, Control Center, Siri/Shortcuts, Mac menu bar, Mac global hotkey.
- **Native iOS 26+ look.** Liquid Glass via standard SwiftUI components.

Success for v1: the author uses Scribe daily on iPhone and Mac instead of other tools, items added on one device appear on the other without thinking about it, and the widget answers "what do I have coming up?" at a glance.

## 2. Decisions Made During Brainstorming

| Topic | Decision |
|---|---|
| Users | Single user. No sharing in v1. |
| Platforms | iPhone + Mac, iOS 26+ / macOS 26+. iPad not targeted in v1. |
| Code sharing | One multiplatform SwiftUI app target + shared `ScribeCore` Swift package. |
| Persistence | SwiftData, stored in an App Group container. |
| Sync | iCloud (CloudKit private database) via SwiftData — **behind an `ItemStore` interface** so a Cloudflare backend can replace it later without UI changes. |
| Item model | One `Item` type with a `kind` flag (task / memo). |
| Languages | English and Hebrew input; per-item RTL/LTR rendering. |
| Design language | iOS 26 / macOS 26 Liquid Glass, native components first. |
| Export | Settings → Export as JSON (backup + future migration path). |

## 3. Non-Goals (v1)

Cloudflare backend, sharing categories with others, Claude/MCP access, web app, recurring items, sub-checklists, attachments/photos, priorities, manual reordering of items, time-zone-pinned items, Hebrew Siri phrases, iPad layout, Apple Watch.

## 4. Architecture

### 4.1 Project layout

```
scribe/
  project.yml              XcodeGen; .xcodeproj is generated, not committed
  Core/                    Swift package "ScribeCore" — no UI imports
    Sources/ScribeCore/
      Models/              Item, Category (@Model), ItemKind, DueDate
      Store/               ItemStore protocol, SwiftDataItemStore, snapshots, export
      Parsing/             QuickAddParser (EN + HE)
      Agenda/              Agenda builder (overdue / today / next 6 days)
      Notifications/       NotificationPlanner (pure: items → planned notifications)
      Widgets/             WidgetEntryBuilder (pure: items → timeline entries)
    Tests/ScribeCoreTests/
  Intents/                 App Intents shared by app + widget extension
  App/                     Multiplatform app target (iOS + macOS)
    Shared/                Views used on both platforms
    iOS/                   iOS-only views (#if os(iOS))
    macOS/                 Menu bar, hotkey panel (#if os(macOS))
  Widgets/                 Widget extension: agenda widget, lock screen widgets, Control
  UITests/
  docs/
```

### 4.2 Targets and identifiers

| Target | Type | Platforms | Bundle ID |
|---|---|---|---|
| Scribe | application | iOS, macOS | `com.noamchuri.scribe` |
| ScribeWidgets | app-extension | iOS, macOS | `com.noamchuri.scribe.widgets` |
| ScribeUITests | ui-testing bundle | iOS | — |
| ScribeCoreTests | SwiftPM test target | macOS host | — |

- App Group: `group.com.noamchuri.scribe` (macOS naming must be verified in Phase 0; see §14).
- iCloud container: `iCloud.com.noamchuri.scribe`.
- Capabilities: iCloud (CloudKit), Push Notifications (CloudKit silent pushes), Background Modes → Remote notifications (iOS), App Groups, App Sandbox + outgoing network (macOS).
- Language mode: Swift 6.
- Third-party dependencies: `KeyboardShortcuts` (macOS only). Nothing else.

### 4.3 Process model

Four kinds of processes touch the same SwiftData store file in the App Group container: the iOS app, the macOS app, the widget extension, and App Intents (Siri / Shortcuts / widget buttons).

- **Only the main app runs CloudKit sync.**
- Widget extension and intents read and write the shared store directly.
- After any write from any process, `WidgetCenter.shared.reloadAllTimelines()` is called.
- The main app picks up writes made by other processes on activation and on background wake, then syncs them.

### 4.4 The `ItemStore` boundary

The UI, widgets and intents never touch SwiftData `@Model` objects. They talk to `ItemStore` and receive value-type snapshots. This is what keeps a future Cloudflare backend a drop-in replacement.

```swift
@MainActor
protocol ItemStore: AnyObject, Observable {
    var categories: [CategorySnapshot] { get }
    func items(_ filter: ItemFilter) -> [ItemSnapshot]
    func agenda(_ scope: CategoryScope, now: Date) -> Agenda

    @discardableResult func addItem(_ draft: ItemDraft) throws -> UUID
    func updateItem(_ id: UUID, _ change: ItemChange) throws
    func setDone(_ id: UUID, _ done: Bool) throws
    func deleteItem(_ id: UUID) throws
    func restoreItem(_ snapshot: ItemSnapshot) throws   // undo after delete

    @discardableResult func addCategory(_ draft: CategoryDraft) throws -> UUID
    func updateCategory(_ id: UUID, _ change: CategoryChange) throws
    func moveCategory(_ id: UUID, toIndex: Int) throws
    func deleteCategory(_ id: UUID) throws               // items move to Inbox

    func exportJSON() throws -> Data
}
```

Signatures are illustrative; exact types (`ItemFilter`, `ItemChange`, snapshots) are fixed in the implementation plan. `SwiftDataItemStore` is the only v1 implementation. Tests use it with an in-memory `ModelContainer`.

## 5. Data Model

All rules below exist to satisfy CloudKit-backed SwiftData: every stored property has a default or is optional, no `@Attribute(.unique)`, all relationships optional.

### 5.1 `Category`

| Field | Type | Default | Notes |
|---|---|---|---|
| `id` | `UUID` | `UUID()` | Stable identity across devices and export. |
| `name` | `String` | `""` | Unique case-insensitively — enforced by the store, not the database. |
| `emoji` | `String` | `""` | Optional visual. |
| `colorName` | `String` | `"blue"` | One of the system palette names (red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray). |
| `sortIndex` | `Double` | `0` | Manual order; fractional to allow inserting between. |
| `items` | `[Item]?` | `[]` | Inverse of `Item.category`, delete rule `.nullify`. |

Deleting a category moves its items to the Inbox (no data loss), with an Undo toast.

### 5.2 `Item`

| Field | Type | Default | Notes |
|---|---|---|---|
| `id` | `UUID` | `UUID()` | |
| `title` | `String` | `""` | Required non-empty by the store. |
| `body` | `String` | `""` | Multi-line plain text. |
| `kindRaw` | `String` | `"task"` | `ItemKind`: `task` / `memo`. Stored as string for CloudKit. |
| `category` | `Category?` | `nil` | `nil` = Inbox. |
| `dueDay` | `String?` | `nil` | Floating calendar day, `yyyy-MM-dd`. |
| `dueMinute` | `Int?` | `nil` | Minutes after local midnight (0–1439). Only valid with `dueDay`. |
| `isDone` | `Bool` | `false` | Tasks only; always `false` for memos. |
| `doneAt` | `Date?` | `nil` | |
| `createdAt` | `Date` | `.now` | |
| `updatedAt` | `Date` | `.now` | Set by the store on every change. |

**Due dates are floating wall-clock values.** "Oct 12, 09:00" means 09:00 on Oct 12 wherever the user is — important because the author travels (Thailand, Bulgaria). The store exposes this as a `DueDate` value type with `day: DateComponents` and optional `time`.

Switching an item from task to memo clears `isDone` / `doneAt`.

### 5.3 Schema evolution rule

Once the CloudKit schema is deployed to production: **only add new optional or defaulted fields. Never rename, retype, or remove a field or model.** Breaking changes require a new field plus a migration in app code.

## 6. Agenda Rules

Used by the Upcoming tab, Mac sidebar "Upcoming", the menu bar panel, and widgets.

- "Today" = the device's current local calendar day.
- **Overdue:** tasks, not done, with `dueDay` before today. Shown first, styled red. Memos never become overdue; past-dated memos drop out of the agenda (they stay in their category).
- **Days:** today through today + 6 (seven day groups). Contains tasks (not done) and memos with that `dueDay`.
- Within a day: untimed items first (by `createdAt`), then timed items by `dueMinute`.
- Tasks completed are removed from the agenda immediately.
- Empty days are omitted from lists; the widget shows an empty state when nothing is due.
- Scope: all categories, or a single category (used by configured widgets).

## 7. Quick-Add Parser

`QuickAddParser.parse(text:, categories:, now:, calendar:) -> ParsedDraft`

`ParsedDraft` carries: `title`, `kind`, `categoryMatch` (`.matched(id)`, `.unknown(name)`, or `.none`), `due` (`DueDate?`), and the ranges of recognized tokens (for UI chips).

### 7.1 Trailing-token rule

Recognized tokens are only consumed from the **end** of the input. The parser walks tokens backwards and stops at the first unrecognized token; everything before that is the title. Recognized token types (each at most once): category tag, kind marker, date phrase, time phrase.

This keeps titles like "ארוחת שבת עם המשפחה" or "fri night plans with Dan" intact, while "book flights fri #thailand" parses as title "book flights", due Friday, category Thailand.

If the title is empty after parsing, the draft is invalid (UI disables Save; Siri asks again).

### 7.2 Category tag

- `#` followed by non-whitespace characters.
- Matching normalizes case, spaces and diacritics. Exact match wins; otherwise a prefix match; if several categories match the prefix, the first in the user's sort order wins (visible in the chip, changeable).
- No match → `.unknown(name)`. In-app UI shows a "+ New category ‘name’" chip that must be tapped to create it. Non-UI paths (Siri) file the item in the Inbox and keep `#name` in the title.

### 7.3 Kind marker

`!memo`, `!note`, `!פתק` → memo. Default kind is task. The composer also has a task/memo toggle.

### 7.4 Dates

The parser uses the device's current calendar and its `firstWeekday` (Sunday in Israel). Tests inject Asia/Jerusalem with Sunday-first.

| English | Hebrew | Meaning |
|---|---|---|
| `today` | `היום` | today |
| `tomorrow`, `tmr`, `tmrw` | `מחר` | today + 1 |
| — | `מחרתיים` | today + 2 |
| `sun`…`sat`, full names, optional `next ` prefix (`next fri` = `fri`) | `ראשון`…`שבת`, optional `יום `/`ב`/`ביום ` prefix | next occurrence **strictly after** today |
| `next week` | `שבוע הבא`, `בשבוע הבא` | first day of next week (Sunday in Israel) |
| `in N days`, `in N weeks` | `בעוד N ימים`, `בעוד יומיים`, `בעוד שבוע`, `בעוד N שבועות` | relative |
| `12/10`, `12.10`, `12/10/26`, `12/10/2026` | same | **day/month**[/year] |
| `oct 12`, `12 oct`, `october 12` | — | month name |

Without a year, a date that has already passed this year means next year.

### 7.5 Times

| Input | Meaning |
|---|---|
| `9am`, `9:30pm`, `14:30`, `at 9`, `at 14:30` | that time (bare hour = 24-hour clock) |
| `noon` / `בצהריים` | 12:00 |
| `tonight` / `הערב` | 20:00 today |
| `ב-9`, `ב9:30`, `בשעה 14:00` | that time |

A time without a date means today if still in the future, otherwise tomorrow.

## 8. Quick-Add Entry Points

All paths call `QuickAddParser` then `ItemStore.addItem`.

| Entry point | Platform | Behavior |
|---|---|---|
| Quick-add capsule | iOS | Glass capsule in `tabViewBottomAccessory`; tap expands to composer with keyboard, live parse chips, task/memo toggle. |
| Widget "+" | iOS, macOS | Deep link `scribe://add?category=<id>` — opens the composer, preselecting the widget's category if it is filtered. |
| Control ("Add to Scribe") | iOS (macOS if supported — verify) | `ControlWidgetButton` running `OpenQuickAddIntent`; usable in Control Center, Lock Screen, Action Button. |
| Siri / Shortcuts | iOS, macOS | `AddItemIntent(text:)`; prompts "What should I add?" if missing; saves without opening the app; replies e.g. "Added ‘Book flights’ to Thailand, Friday." |
| Menu bar panel | macOS | `MenuBarExtra` (window style): today's agenda + quick-add field. |
| Global hotkey `⌃⌥Space` | macOS | Floating glass panel, Spotlight-style; Enter saves, Esc closes; configurable in Settings via KeyboardShortcuts recorder. |

App Intents: `AddItemIntent`, `CompleteTaskIntent(itemID)`, `OpenQuickAddIntent(category?)`, plus `CategoryEntity` for widget configuration. App Shortcut phrases are English in v1; spoken/typed content may be Hebrew.

Deep links: `scribe://add[?category=<uuid>]`, `scribe://item/<uuid>`, `scribe://upcoming`.

## 9. UI

### 9.1 Design language

- Liquid Glass through standard components first: `TabView`, `NavigationSplitView`, toolbars, `.buttonStyle(.glass)` / `.glassProminent`.
- Custom `.glassEffect` only where there is no standard component: the expanded quick-add composer, parse chips, the Mac hotkey panel.
- Glass is for controls floating above content; content (lists, rows) is never glass; never glass on glass.
- Category color appears as an accent (dot, checkbox tint, widget accent), never as a row background.
- Taste constraints carried from the author's previous app: borderless minimal inputs, inline editing (no popovers for editing), compact layouts, at most one prominent button per screen.
- Before Phase 2, check iOS 27 / macOS 27 documentation for Liquid Glass additions since iOS 26.

### 9.2 iPhone

- **Floating glass tab bar:** Upcoming · Categories, and Search as a separate glass circle (`Tab(role: .search)`). `.tabBarMinimizeBehavior(.onScrollDown)`.
- **Quick-add capsule** in `.tabViewBottomAccessory`, reachable from every tab.
- **Upcoming:** agenda (§6) with day headers.
- **Categories:** Inbox row first, then categories (emoji, name, open-item count, color dot). Inline add / rename / reorder / emoji+color picker.
- **Category screen:** open tasks, then memos (faint note glyph, no checkbox), then a collapsed "Done" section.
- **Row interactions:** tap checkbox completes; tap row expands it for inline editing (title, body, and a row of glass chips for date, category, kind); swipe right = complete, swipe left = delete with Undo toast; long-press menu = move to category, convert task↔memo, set date.
- **Search:** title + body across all items including done, results grouped by category.
- **Settings:** toolbar button on the Categories tab.

### 9.3 Mac

- `NavigationSplitView`, two columns: glass sidebar (Upcoming, Inbox, categories) and the item list. Rows expand inline for editing (Things-style); no third column.
- Keyboard (list focused, not while editing text): `⌘N` new item, `Space` toggle done, `⌘⌫` delete, `⌘Z` undo, `⌘1`–`⌘9` jump to category, `⌘F` search.
- Menu bar extra and global hotkey panel (§8).
- Hotkey panel constraints (learned on MeetingNotes): show on the display under the mouse pointer (multi-display setups); borderless panel needs `acceptsFirstMouse` + app activation so the first click works; handle Esc via `keyDown` keyCode 53 because `.onExitCommand` does not fire in borderless `NSHostingView`.
- Regular Dock app (not `LSUIElement`). Settings in a standard Settings scene (`⌘,`).

### 9.4 Bidirectional text

Each item's text views align by the first strong directional character of their own content (Hebrew → right-aligned, English → left-aligned), independent of the system language, so mixed lists read correctly. Same for widget rows.

## 10. Widgets

### 10.1 Agenda widget

- Families: iOS `systemSmall`, `systemMedium`, `systemLarge`, `accessoryRectangular`, `accessoryCircular`; macOS `systemSmall`, `systemMedium`, `systemLarge`.
- Configuration: `AppIntentConfiguration` with optional `CategoryEntity` (nil = All).
- Content: the agenda (§6) for the configured scope, as many rows as fit, then "+N more".
  - Small: today's count + next 2–3 items.
  - Rectangular (lock screen): next 2–3 items.
  - Circular (lock screen): count of open tasks due today + overdue.
- Task rows have an interactive checkbox: `Button(intent: CompleteTaskIntent(itemID:))`.
- "+" corner button: deep link to the composer (§8).
- Tapping an item: `scribe://item/<uuid>`.
- Empty state: "Nothing in the next 7 days" with the "+" button.
- Rendering modes: correct in full color, dark, clear/glass, and tinted (`widgetAccentable` on accents; category colors yield to the system tint in accented mode).

### 10.2 Timeline

`WidgetEntryBuilder` (pure, in Core) produces entries at: now, the next local midnight, and each timed item's due time inside the window. Reload policy `.atEnd`. The app also reloads timelines after every change and after every sync import.

## 11. Notifications

- **Per-device toggle**, stored locally (not synced). Default **on** for iOS, **off** for macOS, to avoid double alerts.
- **Timed items** (`dueMinute` set): one notification at the due time, if not done and in the future.
- **Date-only items:** no per-item notification. Instead, one **morning summary** per day at the summary time (default 09:00, per-device setting), only on days whose agenda has at least one item. It lists the count of today's items (timed and untimed) and the first three titles — "Today: 3 — Book flights, Pay arnona, …" — plus the overdue-task count if any. Timed items still get their own alert.
- The per-device toggle controls both item alerts and the summary.
- **Actions** on item notifications: **Done** (tasks), **+1 hour** (sets due to now + 1 hour, rounded to the next 5 minutes), **Tomorrow** (moves `dueDay` +1, keeps time). Actions change the item itself, so they sync. The summary notification has no actions; tapping opens Upcoming.
- **Budget:** iOS allows 64 pending notifications. `NotificationPlanner` (pure) produces the nearest plan capped at 60: up to 7 summaries, timed items nearest-first for the rest. The scheduler refills on every store change, sync import, app activation and background wake.

## 12. Sync and Data Flow

**Local write:** UI / widget / intent / notification action → `ItemStore` → SwiftData save to the App Group store → widget reload + notification reschedule → (main app) CloudKit export.

**Remote change:** CloudKit silent push → app wakes in background → import → `ItemStore` publishes changes → views update, widget reload, notification reschedule.

**Writes from other processes:** made while the main app is not running; picked up on next activation/background wake, then exported. Expected delay is measured in Phase 0.

## 13. Error Handling

| Situation | Behavior |
|---|---|
| Not signed in to iCloud / iCloud disabled | App works fully on that device; Settings shows "Sync off — sign in to iCloud". No data loss; uploads when sign-in happens. |
| Offline / CloudKit transient error | Local edits kept; system retries automatically. Settings shows "Last synced …" if sync events are observable (Phase 0). |
| Notification permission denied | App works; Settings shows how to enable. |
| Parser recognized something unwanted | Chips show every recognized token; tapping a chip removes it (its text returns to the title). Never silent. |
| Empty title | Save disabled; Siri re-prompts. |
| Duplicate category name | Store rejects; UI shows inline message. |
| Delete item / category | Undo toast (5 s) on iOS; `⌘Z` on Mac. Category delete moves items to Inbox. |
| Store failed to open | Full-screen error with Retry. The store file is never deleted or reset automatically. |

## 14. Risks and Phase 0 Questions

Phase 0 must answer these before Phase 1 starts:

1. **Cross-device sync works** for the iOS app ↔ macOS app with SwiftData + CloudKit in a shared App Group store. Target: change visible on the other device within ~1 minute while both apps are open.
2. **Out-of-app writes** (widget checkbox, Siri add) — how long until they reach the other device when the main app is not running? Acceptable: synced at next app activation/background wake. If they never sync without opening the app, evaluate running intents in the app process.
3. **Sync status observability** — can the app observe CloudKit import/export events under SwiftData? Decides whether Settings shows "Last synced".
4. **macOS App Group identifier** — confirm `group.com.noamchuri.scribe` works for the sandboxed Mac app + widget, or fall back to the Team-ID-prefixed form.
5. **Control widget on macOS 26** — confirm availability.

After Phase 0, reset the CloudKit development schema so spike record types do not leak into the real schema.

## 15. Testing Strategy

- **Core unit tests** (Swift Testing, `swift test`, no simulator):
  - Parser: table-driven EN + HE cases with injected `now` and calendar (Asia/Jerusalem, Sunday-first): trailing-token rule, weekday on the same weekday, `12/10` as 12 Oct, past times rolling to tomorrow, year rollover, unknown/ambiguous tags, empty titles.
  - Agenda: grouping, ordering, overdue rules, memos never overdue, midnight boundary, DST change.
  - Store: in-memory container; CRUD, Inbox on category delete, duplicate names, task→memo clears done, export JSON shape.
  - `NotificationPlanner` and `WidgetEntryBuilder`: pure input → output tests, including the 60-notification cap.
- **UI smoke tests** (iOS simulator): add via capsule, complete a task, delete + undo.
- **Manual sync checklist** on the author's iPhone + Mac (written in Phase 0, rerun after Phases 4–6).
- Verification by Claude uses the simulator and screenshots; the author's real apps and data are not driven by automation unless the author asks.

## 16. Build Phases

Each phase gets its own implementation plan, written when the previous phase is done.

| Phase | Scope | Exit criteria |
|---|---|---|
| 0. Sync spike | `project.yml`, app + widget targets, entitlements, App Group store, CloudKit, minimal model | §14 questions answered and recorded in `docs/`; go/no-go decision |
| 1. Core | Models, `ItemStore` + `SwiftDataItemStore`, Agenda, QuickAddParser (EN + HE), export | All Core tests green |
| 2. iPhone app | Glass tab bar, Upcoming, Categories, category screen, inline editing, quick-add capsule, search, deep links | Author can use it daily on iPhone |
| 3. Mac app | Split view, inline editing, keyboard shortcuts, menu bar extra, hotkey panel | Feature parity on Mac |
| 4. Widgets + intents | Agenda widget (all families + configuration), interactive checkbox, Control, Siri/Shortcuts intents | Quick-add from every entry point in §8 |
| 5. Notifications | Planner + scheduler, due-time alerts, morning summary, actions | Notifications per §11 on a real device |
| 6. Settings | Sync status, per-device notification toggle, summary time, hotkey recorder, JSON export | v1 complete |

## 17. Future (explicitly later)

- `CloudflareItemStore` (Worker + D1/Durable Object) behind the same `ItemStore` protocol, seeded from JSON export — enables sharing, web app, and Claude access (MCP on the same Worker).
- Sharing a category with another person.
- Recurring items, sub-checklists, attachments.
- Hebrew App Shortcut phrases.

## 18. Phase 0 Amendments (2026-10-05)

Measured on a real iPhone + Mac; details in `docs/phase0-findings.md`. Decision: keep iCloud sync (§2), with these changes:

- **Mac sync timing (§12).** The Mac app did not receive CloudKit pushes, even after `NSApplication.registerForRemoteNotifications()` succeeded; it imports within ~2 s of becoming active. The registration was removed with the probe: Phase 3 re-adds it, investigates the missing pushes, and makes opening the menu bar panel activate the app so it syncs. The Mac desktop widget has the same limit — it shows data as of the Mac app's last activation.
- **iPhone background freshness (§10, §11).** iOS did not wake the suspended app for the CloudKit silent push. `NSPersistentCloudKitContainer` has no public "import now" API, so Phase 4 first verifies on a device whether a `BGAppRefreshTask` (requires the `fetch` background mode and `BGTaskSchedulerPermittedIdentifiers`) actually triggers an import and a widget reload. Fallback: the widget shows how old its data is, and the lag is accepted.
- **App Intents on device (§8).** On the iPhone, Shortcuts did not list Scribe and the widget/Control intents wrote nothing; in the simulator the shortcut ran in the app process and wrote correctly. The extension-process write → app export path (§4.3) is untested everywhere — the only successful out-of-app write ran in the app process — so Phase 4 starts by verifying intent registration on the device and testing the widget/Control write path in the simulator and on the device.
- **"Last synced" (§13).** Feasible: `NSPersistentCloudKitContainer.eventChangedNotification` reports setup/import/export under SwiftData.
- **App Group (§4.2).** `group.com.noamchuri.scribe` works on macOS and iOS once registered in the developer portal; command-line automatic signing does not register App Groups.
- **Deferred to Phase 4.** The Mac desktop widget reading the store (M7) and Control availability on macOS (§8, Q5).
- **Open item.** Reset the CloudKit Development environment (removes the probe's `CD_ProbeNote` record type) before the first production schema deploy and before Phase 1 Task 10's record-type check.

## 19. Post-Phase 2 Amendments (2026-10-05)

Decided by the author after using the iPhone app:

- **Every new item gets a real category (§8, §9.2).** The quick-add composer shows a row of category chips under the field; Add stays disabled until a category is chosen. A typed `#tag` picks it, a tapped chip overrides the tag, and the category on screen is preselected. A typed unknown `#name` offers "+ New category" (creating it picks it). The composer never offers or defaults to the Inbox; a preselected category that no longer exists leaves nothing picked.
- **Inbox becomes a holding place, not a destination.** It holds items whose category was deleted (and, until Phase 4 decides otherwise, entries made without a category). Its row on the Categories screen shows only while something is in it. "Move to" and the inline editor's category picker don't list it.
- **Siri / Shortcuts / Control adds (Phase 4)** follow the same rule: ask for a category (or infer one) instead of filing to the Inbox.
