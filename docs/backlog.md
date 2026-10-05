# Backlog — carried out of Phases 0–1

Items deferred during review. Each later phase plan must pick up the ones for its phase.

## Phase 2 (iPhone app)

- **Category delete undo (spec §13).** Add `restoreCategory(_:)` that re-inserts a deleted category with the same `id` and `sortIndex` and re-attaches its items; `deleteCategory` returns what's needed to undo.
- **Who calls `ItemStore.refresh()`.** Wire it to CloudKit import events (`NSPersistentCloudKitContainer.eventChangedNotification` / `NSPersistentStoreRemoteChange`) and to the app becoming active (spec §12).
- **Reordering.** Add an `onMove`-shaped `moveCategories(fromOffsets:toOffset:)`; `moveCategory(_:toIndex:)` takes the final position, which is off by one for SwiftUI drags downward.
- **Unknown `#tag` in the composer.** `ParsedDraft.itemDraft` drops an unknown tag's text; the composer must re-parse with `disabled: [.category]` before saving if the user didn't create the category.
- **Two `.time` chips.** "tonight" + an explicit time produce two chips of the same kind; key chips by position, not kind. Update the `QuickAddParser` doc comment ("each kind at most once" no longer holds for time).
- **Store-open failure screen (spec §13)** replaces the temporary `fatalError` in `App/ScribeApp.swift`; delete `App/StoreSmokeView.swift`.
- **Product questions for the author:** what "morning"/"evening"/"בבוקר"/"בערב" mean as quick-add times; whether a bare hour 1–7 ("ב-5") should mean afternoon; Hebrew spelling "בצהרים".
- **Check iOS 27 Liquid Glass docs** before writing UI (spec §9.1).

## Phase 3 (Mac app)

- **Mac CloudKit.** After the 2026-10-05 Development reset, the Mac app's CloudKit setup fails with `CKErrorDomain 6` (service unavailable) while the iPhone works; clearing the app's CloudKit cache and restarting `cloudd` did not help. Try a Mac restart / iCloud sign-out-in first. Then re-run the cross-device check in both directions.
- **Mac push.** The Mac app received no CloudKit pushes in Phase 0 even with `registerForRemoteNotifications()` (spec §18). Re-add the registration and investigate.
- **KeyboardShortcuts** dependency must be macOS-only on the multiplatform target (`destinationFilters`).
- **Runpath.** Add `@executable_path/../Frameworks` for macOS before embedding any dynamic framework.

## Phase 4 (widgets, Control, Siri)

- Verify App Intents registration on device (Shortcuts listed nothing on the iPhone in Phase 0) and the widget/Control write path in the simulator and on device; record which process runs each intent (spec §18).
- `StoreFactory.shared` must be called once per process; an intent running inside the app needs the app's container.
- Verify a `BGAppRefreshTask` actually triggers an import; fallback is showing data age (spec §18).
- Mac desktop widget (M7) and Control on macOS (Q5).
- Widget needs an error state if the store can't open.

## Phase 5–6

- `ItemFilter` has no `.all`; `NotificationPlanner` needs timed items beyond the 7-day agenda.
- "Last synced" should use the CloudKit event's `endDate`.

## Before the first production CloudKit schema deploy

- In the CloudKit Console (Development), confirm every `CD_Item` / `CD_Category` field exists — fields appear only after a saved record has a value (e.g. `dueDay`, `dueMinute`, `doneAt`).
- `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD` is `YES` (Vision Pro availability) — decide at distribution time.
