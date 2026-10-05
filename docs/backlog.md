# Backlog — carried out of Phases 0–1

Items deferred during review. Each later phase plan must pick up the ones for its phase.

## Phase 3 (Mac app)

- **Mac UI** replaces the placeholder `App/macOS/RootView.swift`; reuse `ItemRow`-style rows via shared views where the platforms agree.
- **Deep links on the Mac.** `ScribeApp` buffers every `scribe://` link in `StoreLoader.pendingLink`; only the iPhone `RootView` drains it. The Mac root must drain it too, or a stale link fires when the real Mac UI appears.
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

## Later (after v1)

Ideas from the author, 2026-10-05.

- **Talk to add, with the category worked out.** Saying or typing "remind me to fix the dates for our hotels in Thailand" adds "Fix the dates for our hotels" to Thailand. When no category clearly fits, ask which one, or offer to create one. Builds on Phase 4's Siri intent (`AddItemIntent`); Apple's on-device Foundation Models framework could pick the category privately, with the `#tag` parser as the fallback.
- **Let Claude add tasks — from any device, iPhone included.** A remote MCP server on a Cloudflare Worker (Claude custom connectors work on iPhone, web and Mac). The data stays in iCloud; the Worker is a mailbox: the app publishes its category list, Claude reads it and drops new items in (asking in the chat when the category is unclear, or proposing a new one), and Scribe collects them on launch, background refresh or a silent push, then syncs them through iCloud as usual. If the data later moves to Cloudflare (spec §17), the same MCP talks to it directly. (A Mac-only local tool was rejected: it wouldn't work from the iPhone.)

## Before the first production CloudKit schema deploy

- In the CloudKit Console (Development), confirm every `CD_Item` / `CD_Category` field exists — fields appear only after a saved record has a value (e.g. `dueDay`, `dueMinute`, `doneAt`).
- `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD` is `YES` (Vision Pro availability) — decide at distribution time.
