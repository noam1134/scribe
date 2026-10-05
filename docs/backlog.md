# Backlog — carried out of Phases 0–2

Items deferred during review. Each later phase plan must pick up the ones for its phase.

## Phase 2 follow-ups

Deferred in the Phase 2 (iPhone app) reviews.

### Quick-add

- A time-only phrase that rolls to tomorrow shows only "09:00" on its chip — label it "Tomorrow · 09:00" when no date token was typed; "this morning"/"this evening" roll to tomorrow once passed (ask the author).
- A dismissed chip disables that kind for the rest of the composition (re-enable it when the dismissed text is gone? Product call).
- The composer's compact height (252 pt since the Notes field) clips at accessibility text sizes.
- The kind toggle ignores a typed `!memo`, and its accessibility label lacks a value.
- An add link doesn't retarget an already-open composer.
- A half-typed draft is lost if iOS terminates the app.

### Lists, rows and editor

- Upcoming doesn't roll to the new day if the app stays open past midnight (refresh on a significant time change).
- "Add Time…" shows 09:00 but sets nothing until the wheel is scrolled.
- `expandedItemID` lingers after the item leaves the list.
- Accessibility: no button trait on tap-to-edit, ~22 pt checkbox, no focus on expand.

### Categories

- A restored category may tie on `sortIndex` and skips the duplicate-name check.
- Reorder is index-based across a possible sync gap (move by ids).
- Colour swatches lack button/selected traits, have 26 pt targets, and draw a white check on yellow/mint/cyan.
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
- `AppRouter.open` / Retry (consider moving link resolution into Core).
- `offersExpire` uses a wall-clock sleep (watch for flakes).

### Code

- The unknown-tag re-parse duplicates `QuickAddParser.nonInteractiveDraft` (give it a `disabled:` parameter).
- The "Inbox" literal is repeated in six places.

## Lists home tab follow-ups

From the Lists change (spec §20, plan `2026-10-05-lists-home.md`).

- Ticking a task with Show Completed off hides it at once, as on Upcoming. Consider a short linger or an Undo toast.
- A header's long press opens a confirmation dialog (Rename / Delete), not a context menu: SwiftUI gives only list rows context menus. A UIKit `UIContextMenuInteraction` on the header could replace it.
- A tap outside a text field closes the keyboard even when it lands on a button or chip (e.g. the composer's category chips) — the button still works. Judge the feel on the device.
- Collapse state keeps the ids of deleted categories (so Undo restores the state); they are never pruned.
- Lists reads every item, done ones included, on each render. Fine at personal scale; revisit if the store grows into the thousands.
- The demo data's emoji draw as missing-glyph boxes in the iOS 27 simulator (Upcoming too); check on the device.

## Phase 3 (Mac app)

The Mac UI, deep-link drain, activation refresh, `KeyboardShortcuts` (macOS-only), the macOS runpath and the push registration landed in Phase 3. Still open:

- **Mac CloudKit.** After the 2026-10-05 Development reset, the Mac app's CloudKit setup fails with `CKErrorDomain 6` (service unavailable) while the iPhone works; clearing the app's CloudKit cache and restarting `cloudd` did not help. Try a Mac restart / iCloud sign-out-in first. Then re-run the cross-device check in both directions.
- **Mac push.** `registerForRemoteNotifications()` is back; registration, every push and every CloudKit setup/import/export is logged (`log stream --level info --predicate 'subsystem == "com.noamchuri.scribe"'`, categories `push`, `sync`, `hotkey`). A signed run must show whether pushes reach the app and whether an import follows (spec §18).
- **Hotkey is ⌃⇧Space** (spec §8, §19: ⌃⌥Space is macOS's "Select next source in Input menu" on the author's Mac). The menu bar panel warns if the shortcut is also a macOS one. Phase 6's recorder can change it.
- **Activation.** Opening the menu bar extra activates the app (spec §18), which brings the main window forward behind it; closing hands activation back unless the user went on in Scribe. The hotkey panel never activates the app. Judge the feel on the author's Mac.
- A menu path back to a closed main window (New Item could open the main window when none is open).
- `handlesExternalEvents` is only on the ready root; add it to the loading and failed roots too.
- Check how the expanded editor looks over the key window's selection highlight.
- Open on key-down (`onKeyDown`) for a snappier hotkey panel.
- Make window quick-adds undoable (⌘Z after an add).
- Upcoming and the menu bar agenda don't roll over at midnight while open (as on the iPhone).
- The category editor in the sidebar closes only with Return or Esc, not by clicking away.
- No macOS UI tests: driving the Mac UI takes over the live keyboard and mouse. Candidates: keyboard flow, sidebar add/edit/delete + ⌘Z, the quick-add field.

## Phase 4 (widgets, Control, Siri)

Built and checked in the simulator (see the Phase 4 plan). Still open:

- **Device checks** (simulator can't prove them): Shortcuts lists Scribe on the iPhone; the widget checkbox's extension write reaches the Mac via iCloud after the iPhone app next opens; `BGAppRefreshTask` runs and actually triggers an iCloud import (the simulator refuses BG tasks); Mac desktop widget (M7) reads the Mac store; "Add to Scribe" Control appears in the Mac's Control Center / menu bar (Q5); an open Mac app refreshes when the desktop widget's checkbox writes (cross-process `NSPersistentStoreRemoteChange`; activation is the backstop); Siri voice flow with category disambiguation.
- Siri can't create a category from an unknown `#tag` (the tag stays in the title and Siri asks for an existing category).
- Per-category Siri phrases ("Add to Thailand in Scribe") would need `updateAppShortcutParameters()` whenever categories change.

## Phase 4 follow-ups

From the Phase 4 review.

- Widget links and the composer: an item/Upcoming link closes an open composer and loses its draft; an `add?category=` link while the composer is open keeps the old category.
- The medium/large widgets fit 5/14 lines whatever the Dynamic Type size; scale the budgets.
- A category widget's background tap opens Upcoming; it should open that category (needs a `scribe://category/<id>` link).
- Siri: ask for the category by spoken name (`requestValue`) before listing every category.
- Siri replies are English with the user's region formats (dates); revisit at localization.
- No undo for a widget tick.
- Check the widgets in tinted and clear home-screen modes.

## Phase 5 follow-ups

- **Device check** of notifications (permission prompt, a due-time alert, the morning summary, Done / +1 hour / Tomorrow from the lock screen with the app suspended and force-quit). Steps in the Phase 5 report.
- **Stale alerts on iPhone.** Notifications are planned from the data the iPhone has; an item changed on the Mac re-plans only when the iPhone app imports it (spec §18). On activation that is automatic; a background refresh task or an intent running in the app process must `await NotificationCoordinator.shared.rescheduleNow()` (it opens the store if needed) before finishing.
- **Widget Complete intent** should withdraw the item's alert: remove `PlannedNotification.identifier(forItem:)` from pending and delivered requests.
- Notification text is English ("Today: 3", "Overdue: 2", "+1 Hour") — decide at localization.
- An item moved by "+1 hour" inside the hour repeated by the autumn DST change lands on the first, already-passed copy of that time and gets no new alert.

## Phase 6 (Settings)

- Bind to `NotificationCoordinator.shared`: `settings` (`isEnabled`, `morningSummaryEnabled`, `morningSummaryMinute`), `permission` (`.denied` → explain and link `NotificationCoordinator.systemSettingsURL`), `requestPermission()`. Turning notifications on (the Mac's default is off) should call `requestPermission()`, so the prompt comes from the switch even before anything is scheduled.
- "Last synced" should use the CloudKit event's `endDate`.

## Later (after v1)

Ideas from the author, 2026-10-05.

- **Talk to add, with the category worked out.** Saying or typing "remind me to fix the dates for our hotels in Thailand" adds "Fix the dates for our hotels" to Thailand. When no category clearly fits, ask which one, or offer to create one. Builds on Phase 4's Siri intent (`AddItemIntent`); Apple's on-device Foundation Models framework could pick the category privately, with the `#tag` parser as the fallback.
- **Let Claude add tasks — from any device, iPhone included.** A remote MCP server on a Cloudflare Worker (Claude custom connectors work on iPhone, web and Mac). The data stays in iCloud; the Worker is a mailbox: the app publishes its category list, Claude reads it and drops new items in (asking in the chat when the category is unclear, or proposing a new one), and Scribe collects them on launch, background refresh or a silent push, then syncs them through iCloud as usual. If the data later moves to Cloudflare (spec §17), the same MCP talks to it directly. (A Mac-only local tool was rejected: it wouldn't work from the iPhone.)

## Before the first production CloudKit schema deploy

- In the CloudKit Console (Development), confirm every `CD_Item` / `CD_Category` field exists — fields appear only after a saved record has a value (e.g. `dueDay`, `dueMinute`, `doneAt`).
- `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD` is `YES` (Vision Pro availability) — decide at distribution time.
