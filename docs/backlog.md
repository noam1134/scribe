# Backlog — carried out of Phases 0–2

Items deferred during review. Each later phase plan must pick up the ones for its phase.

## Phase 2 follow-ups

Deferred in the Phase 2 (iPhone app) reviews.

### Quick-add

- A time-only phrase that rolls to tomorrow shows only "09:00" on its chip — label it "Tomorrow · 09:00" when no date token was typed; "this morning"/"this evening" roll to tomorrow once passed (ask the author).
- A dismissed chip disables that kind for the rest of the composition (re-enable it when the dismissed text is gone? Product call).
- The 150 pt sheet clips at accessibility text sizes.
- The kind toggle ignores a typed `!memo`, and its accessibility label lacks a value.
- An add link doesn't retarget an already-open composer.
- A half-typed draft is lost if iOS terminates the app.

### Lists, rows and editor

- Upcoming doesn't roll to the new day if the app stays open past midnight (refresh on a significant time change).
- "Add Time…" shows 09:00 but sets nothing until the wheel is scrolled.
- `expandedItemID` lingers after the item leaves the list.
- An item link to a done item opens inside the collapsed Done group (expand it).
- Accessibility: no button trait on tap-to-edit, ~22 pt checkbox, no focus on expand.

### Categories

- A restored category may tie on `sortIndex` and skips the duplicate-name check.
- Reorder is index-based across a possible sync gap (move by ids).
- Colour swatches lack button/selected traits, have 26 pt targets, and draw a white check on yellow/mint/cyan.
- A whitespace-only add leaves the text in the field.
- The add field can only be dismissed with Return.
- The emoji placeholder symbol should be `.accessibilityHidden(true)`.

### Undo toast

- `.transition` never animates (add `.animation(.snappy, value: undo.current?.id)`).
- 120 pt magic bottom padding.
- The store-failure title uses an ASCII apostrophe ("Can't").

### Labels

- "Today/Tomorrow/Memo/Next Week" are English while weekday/month names follow the locale (decide at localization).

### Tests to add

- UI tests: chip taps, the sheet alert, the editor, the category edit row, category delete + undo, reorder, Search.
- Core tests: empty/out-of-range `IndexSet`, restore after an item was deleted, day-part edge phrases.
- Core tests: `UndoCenter` (throwing undo, dismiss, replaced-offer timer).
- Core tests: `QuickAddComposer` `reset()`, `createUnknownCategory` no-op, save keeping the text when `addItem` throws.
- `AppRouter.open` / `visibleCategoryID` / Retry (consider moving link resolution into Core).
- `offersExpire` uses a wall-clock sleep (watch for flakes).

### Code

- The unknown-tag re-parse duplicates `QuickAddParser.nonInteractiveDraft` (give it a `disabled:` parameter).
- The "Inbox" literal is repeated in six places.

## Phase 3 (Mac app)

The Mac UI, deep-link drain, activation refresh, `KeyboardShortcuts` (macOS-only), the macOS runpath and the push registration landed in Phase 3. Still open:

- **Mac CloudKit.** After the 2026-10-05 Development reset, the Mac app's CloudKit setup fails with `CKErrorDomain 6` (service unavailable) while the iPhone works; clearing the app's CloudKit cache and restarting `cloudd` did not help. Try a Mac restart / iCloud sign-out-in first. Then re-run the cross-device check in both directions.
- **Mac push.** `registerForRemoteNotifications()` is back; registration, every push and every CloudKit setup/import/export is logged (`log stream --level info --predicate 'subsystem == "com.noamchuri.scribe"'`, categories `push`, `sync`, `hotkey`). A signed run must show whether pushes reach the app and whether an import follows (spec §18).
- **⌃⌥Space vs. Input Sources.** macOS's "Select next source in Input menu" also defaults to ⌃⌥Space; with Hebrew + English input sources the system may take it first (the app logs a warning when the shortcut is a system one). Check on the author's Mac; Phase 6's recorder can change it.
- **Activation side effect.** Opening the menu bar extra or the hotkey panel activates the app (spec §9.3, §18), which brings the main window forward behind the panel; closing hands activation back to the app that was in front. Judge the feel on the author's Mac.
- Upcoming and the menu bar agenda don't roll over at midnight while open (as on the iPhone).
- The category editor in the sidebar closes only with Return or Esc, not by clicking away.
- No macOS UI tests: driving the Mac UI takes over the live keyboard and mouse. Candidates: keyboard flow, sidebar add/edit/delete + ⌘Z, the quick-add field.

## Phase 4 (widgets, Control, Siri)

- **Every add needs a category (spec §19).** `AddItemIntent` / Siri / the Control must ask for a category (Siri disambiguation over `CategoryEntity`) or infer one — never file to the Inbox silently.
- Verify App Intents registration on device (Shortcuts listed nothing on the iPhone in Phase 0) and the widget/Control write path in the simulator and on device; record which process runs each intent (spec §18).
- `StoreFactory.shared` must be called once per process; an intent running inside the app needs the app's container.
- Verify a `BGAppRefreshTask` actually triggers an import; fallback is showing data age (spec §18).
- Mac desktop widget (M7) and Control on macOS (Q5).
- Widget needs an error state if the store can't open.
- Verify widget/intent writes post `NSPersistentStoreRemoteChange`, so the open app refreshes (scene activation is the backstop).
- Verify a cold-launch `scribe://item/<id>` pushes the category screen (only `scribe://add` was tried).

## Phase 5–6

- `ItemFilter` has no `.all`; `NotificationPlanner` needs timed items beyond the 7-day agenda.
- "Last synced" should use the CloudKit event's `endDate`.

## Later (after v1)

Ideas from the author, 2026-10-05.

- **Talk to add, with the category worked out.** Saying or typing "remind me to fix the dates for our hotels in Thailand" adds "Fix the dates for our hotels" to Thailand. When no category clearly fits, ask which one, or offer to create one. Builds on Phase 4's Siri intent (`AddItemIntent`); Apple's on-device Foundation Models framework could pick the category privately, with the `#tag` parser as the fallback.
- **Let Claude add tasks — from any device, iPhone included.** A remote MCP server on a Cloudflare Worker (Claude custom connectors work on iPhone, web and Mac). The data stays in iCloud; the Worker is a mailbox: the app publishes its category list, Claude reads it and drops new items in (asking in the chat when the category is unclear, or proposing a new one), and Scribe collects them on launch, background refresh or a silent push, then syncs them through iCloud as usual. If the data later moves to Cloudflare (spec §17), the same MCP talks to it directly. (A Mac-only local tool was rejected: it wouldn't work from the iPhone.)

## Before the first production CloudKit schema deploy

- In the CloudKit Console (Development), confirm every `CD_Item` / `CD_Category` field exists — fields appear only after a saved record has a value (e.g. `dueDay`, `dueMinute`, `doneAt`).
- `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD` is `YES` (Vision Pro availability) — decide at distribution time.
