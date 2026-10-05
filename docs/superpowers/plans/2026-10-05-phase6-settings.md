# Scribe Phase 6 — Settings Implementation Plan

**Goal:** One Settings screen on iPhone and Mac (spec §16 Phase 6): iCloud sync status with "Last synced …" and the last error, the per-device notification switch with the morning summary and its time, JSON export, version — plus, on the Mac, the quick-add hotkey recorder. Two Phase 4 review follow-ups ride along.

**Spec:** §2 (export), §9.2 / §9.3 (placement), §11 (per-device notification settings), §13 (iCloud not signed in, offline, permission denied), §16, §18 ("Last synced" from `NSPersistentCloudKitContainer.eventChangedNotification`), §19 (hotkey default ⌃⇧Space). Backlog: "Phase 6 (Settings)".

**Architecture:** Everything that decides *what Settings says* is pure and lives in `ScribeCore/Settings/` with Swift Testing tests: the iCloud account state and the per-device sync log (which events count, which error stands), the sentences for both, the notification section's rules, the summary-time ↔ minute conversion, the export file name, the version line and the hotkey note. The app adds one observable `SyncMonitor` (CloudKit account status + event log, started with the app's services), one shared `SettingsView` (grouped `Form`), an iPhone `SettingsButton` that presents it in a sheet, and a Mac `Settings` scene that adds the `KeyboardShortcuts.Recorder`. Notifications bind straight to Phase 5's `NotificationCoordinator.shared`.

**Not in this phase:** wiring `SettingsButton` into the iPhone's new Lists tab (the controller does it at merge — the Lists home is being built in parallel), import from JSON, localization.

## Global Constraints

Phase 2's constraints apply (Swift 6, iOS/macOS 26, ScribeCore imports only Foundation/Observation/SwiftData, no model changes, no `try!`/`fatalError` in app code, zero warnings, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`). Additionally:

- Simulator "Scribe P6", id `4493027E-E776-44C1-913F-455D6A81F2E3` (derived data `build/dd-sim`). Branch `phase6-settings` in `.worktrees/phase6-settings`, from `main` b29c8fa.
- Don't edit the iPhone list/category screens, `RootView`'s tab structure or the quick-add composer (another agent is replacing the Categories tab).
- Shared files (`App/ScribeApp.swift`, `project.yml`, `docs/backlog.md`, `README.md`) get small, localized edits only.
- No macOS UI tests (they would drive the author's live screen).

## File Map

| File | Responsibility | Task |
|---|---|---|
| `Core/Sources/ScribeCore/Settings/SyncStatus.swift` | `CloudAccountState`, `SyncEventKind`, `SyncFailureReason` (from an `NSError`), `SyncLog` (per-device, `Codable`) | 1 |
| `Core/Sources/ScribeCore/Settings/SettingsText.swift` | `DeviceKind`; `SyncStatusText` (headline, how to fix, "Last synced …", problem); `NotificationSectionText`; `AboutText`; `QuickAddHotkeyNote` | 2 |
| `Core/Sources/ScribeCore/Notifications/NotificationSettings.swift` | `summaryTime(calendar:)` / `setSummaryTime(_:calendar:)` on a fixed reference day | 2 |
| `Core/Sources/ScribeCore/Store/ExportDocument.swift` | `suggestedFilename(now:calendar:)` → `Scribe-2026-10-05.json` | 2 |
| `App/Shared/SyncMonitor.swift` | Account status (`CKContainer.accountStatus`, `CKAccountChanged`), CloudKit events → `SyncLog`, persisted per device | 3 |
| `App/Shared/AppProcess.swift` | Starts `SyncMonitor` with the app's services | 3 |
| `App/Shared/SettingsView.swift` | The shared grouped form: iCloud, Notifications, (Mac) Quick Add, Export, About | 4 |
| `App/Shared/SettingsExport.swift` | Export to a temp file; iPhone share sheet; Mac save panel item | 4 |
| `App/Shared/SettingsDemo.swift` | DEBUG `-uiTesting` states for tests and screenshots (`-demoSync`, `-demoPermission`) | 4 |
| `App/Shared/NotificationCoordinator.swift` | `requestPermission()` is a no-op when notifications are inactive in a UI-test run | 4 |
| `App/iOS/SettingsButton.swift` | Gear button → sheet with `SettingsView`, closed with the toolbar's X; DEBUG test entry (`-settingsButton`, `-showSettings`) | 5 |
| `App/ScribeApp.swift` | `MacSettingsScene` (macOS); the iOS DEBUG test entry modifier | 5, 6 |
| `App/macOS/MacSettings.swift` | `Settings` scene; quick-add hotkey section (recorder, system-conflict warning, restore default); DEBUG `-showSettings` | 6 |
| `App/macOS/QuickAddHotkey.swift`, `MenuBarPanel.swift` | Observable hotkey status (menu bar note follows the recorder); Phase 4 follow-up: forward `IntentLinkInbox` links from the menu bar label | 6, 7 |
| `App/Scribe-macOS.entitlements` | `com.apple.security.files.user-selected.read-write` (save panel) | 6 |
| `UITests/SettingsUITests.swift` | Open Settings from the button, sync/notification/export/about rows, share sheet, denied permission | 5 |
| `docs/…`, `README.md` | Spec §21, backlog, Phase 4 plan fix, status | 8 |

## Tasks

### Task 1: Sync state and log (Core, TDD)

```swift
public enum CloudAccountState: Equatable, Sendable { case checking, available, noAccount, restricted, temporarilyUnavailable, unknown }
public enum SyncEventKind: String, Codable, Sendable { case setup, `import`, export }
public enum SyncFailureReason: Codable, Equatable, Sendable {
    case offline, iCloudBusy, notSignedIn, storageFull, accountNeedsAttention, other(String)
    public init(error: NSError)   // CKErrorDomain codes; unwraps partial failures and NSUnderlyingErrorKey; Core Data 134400 = no account
}
public struct SyncLog: Codable, Equatable, Sendable {
    public private(set) var lastSuccess: Date?        // latest successful import/export end
    public private(set) var failures: [SyncFailure]   // ≤ 1 per kind
    public var latestFailure: SyncFailure? { get }
    @discardableResult public mutating func record(_ kind: SyncEventKind, endedAt: Date, failure: SyncFailureReason?) -> Bool
    public init(from defaults: UserDefaults, key: String) / func save(to:key:)
}
```
Tests (`SyncStatusTests`): success moves `lastSuccess` forward only (never back); setup success doesn't count as a sync; a failure stands until that kind succeeds; an import/export success clears a setup failure; an export failure survives an import success; the latest failure is the newest; error mapping (network 3/4 → offline, 6/7/23/34 → busy, 9 + Core Data 134400 → not signed in, 25 → storage full, 36 → needs attention, partial failure → first inner error, underlying error, unknown → `other("CKErrorDomain 15")`); round trip through defaults; corrupt data → empty log.

### Task 2: Settings sentences and small conversions (Core, TDD)

- `DeviceKind { iPhone, mac }` with `.current`, `name` ("iPhone"/"Mac") and `settingsAppName` ("Settings"/"System Settings").
- `SyncStatusText(account:log:now:device:labels:)` → `headline`, `detail` (how to fix), `lastSynced`, `problem`, `isWarning`. Headline for no account is exactly "Sync off — sign in to iCloud" (§13). "Last synced just now / at 09:14 / yesterday at 22:10 / Fri, 9 Oct at 09:14" (24-hour, `DueLabels`); "Not synced yet on this iPhone" while signed in with no success. The problem line shows only while the account row doesn't already explain it.
- `NotificationSectionText(settings:permission:device:)` → `showsPermissionProblem` (denied while the switch is on), problem sentence + button title, `summaryToggleEnabled`, `showsSummaryTime`, `footer` (per-device sentence).
- `NotificationSettings.summaryTime(calendar:)` / `setSummaryTime(_:calendar:)`: hour and minute on a fixed reference day (no DST), clamped.
- `ExportDocument.suggestedFilename(now:calendar:)` → "Scribe-2026-10-05.json" (device's local day).
- `AboutText.version(short:build:)` → "0.1 (1)".
- `QuickAddHotkeyNote(shortcut:isTakenBySystem:)` → menu bar and Settings sentences; nil shortcut = "No shortcut".
- Scheduler check: changing the summary time moves the pending summaries; turning the summary off removes them (`NotificationSchedulerTests`).

### Task 3: `SyncMonitor` (app)

`@MainActor @Observable final class SyncMonitor { static let shared; account; log; start(); refreshAccount() async }`. `start()` (idempotent) observes `eventChangedNotification` (finished events only) and `.CKAccountChanged`, and checks the account. The log is saved in the standard defaults (`sync.log`) — per device, never synced. `AppProcess.start` calls `start()`, so events are recorded from launch whether or not Settings is open; Settings calls it too and re-checks the account on appear. UI-test runs never touch CloudKit (DEBUG demo states instead); a Mac build without the iCloud entitlement (unsigned) skips `CKContainer` and reports `.unknown`.

### Task 4: `SettingsView` (shared)

Grouped `Form`, sections in order:
1. **iCloud** — status icon + headline, how-to-fix detail, "Last synced …" (refreshed every 30 s by a `TimelineView`), problem line.
2. **Notifications** — "Notifications on This iPhone/Mac" switch (turning it on calls `requestPermission()`); denied → sentence + "Open Settings"/"Open System Settings" (`NotificationCoordinator.systemSettingsURL`); "Morning Summary" switch (disabled while off); "Summary Time" `DatePicker(.hourAndMinute)` while the summary is on; footer says it's for this device. Bound to `NotificationCoordinator.shared.settings`, whose setter saves and re-plans.
3. **Quick Add** (macOS only, Task 6).
4. **Export** — "Export All as JSON": `exportJSON()` → temp file `Scribe-yyyy-MM-dd.json` → iPhone share sheet / Mac save panel. A failure shows "Couldn’t Export" with the error's sentence.
5. **About** — Version.

`NotificationCoordinator.requestPermission()` returns at once in UI-test runs where notifications are inactive, so the switch never raises the system prompt during the smoke tests.

### Task 5: iPhone entry + UI tests

`SettingsButton` — `Button("Settings", systemImage: "gear")` (identifier `settingsButton`) that presents `NavigationStack { SettingsView }` in a sheet closed with the toolbar's X (`Button(role: .close)`; changes apply as they're made). Self-contained: reads the `StoreLoader` from the environment. The controller places it in the Lists tab's toolbar at merge.

Test entry (DEBUG, `-uiTesting` only): `-settingsButton` overlays a `SettingsButton` on the app root so the test taps the real button; `-showSettings` presents the sheet at launch (simulator screenshots). Applied as one modifier in `ScribeApp`.

`SettingsUITests`: (1) the button opens Settings: "Sync off — sign in to iCloud", the notification switches, the summary time hides when the summary is off and returns, Export and Version rows, X closes it; (2) signed-in demo shows "Last synced"; (3) Export opens the share sheet, which names `Scribe-<date>` (JSON); (4) the offline demo shows the problem line, and denied permission shows the explanation and Open Settings until the switch is turned off. Launch arguments pin the `notifications.*` values so toggles don't leak into later runs.

### Task 6: Mac Settings scene + hotkey

`MacSettingsScene(loader:)` — `Settings { SettingsView }` (⌘,), one pane, a fixed 480 × 640 pt window whose form scrolls (a resizable one grew to the main window's width). Quick Add section: `KeyboardShortcuts.Recorder("Quick Add", name: .quickAdd)` (its own dialogs: a macOS shortcut asks "Use Anyway", a menu shortcut is refused), the saved shortcut's system-conflict warning, "No shortcut" note when cleared, and "Restore ⌃⇧Space" when it differs from the default. `QuickAddHotkey`'s status becomes observable so the menu bar note follows changes. Entitlement for the save panel.

### Task 7: Phase 4 follow-up — Mac intent link with no window

`MenuBarLabel` (always present) also moves `IntentLinkInbox.shared.link` into `loader.pendingLink`; its existing `pendingLink` handler then opens a main window through `MacWindows.showMain`.

### Task 8: Docs and verification

Spec §21; backlog (Phase 6 section → follow-ups; stale Phase 4/5 lines; the Mac desktop-widget tick device check); Phase 4 plan's `LiveActivityIntent` line; README status. Core suite, iOS UI tests on "Scribe P6", iOS + macOS builds, simulator screenshots in the scratchpad's `settings-shots/`.

## Decisions

1. **Sections and order:** iCloud, Notifications, Quick Add (Mac), Export, About. One pane on the Mac (no tabs for five short sections).
2. **iCloud account** comes from `CKContainer.accountStatus()`, re-checked when Settings appears and on `CKAccountChanged`. "Not signed in" also covers iCloud turned off for Scribe; the how-to-fix line says both.
3. **"Last synced"** is the end of the latest *successful import or export* (setup excluded), recorded by the app from launch and saved per device. It never moves backwards. No success yet while signed in: "Not synced yet on this iPhone".
4. **The error line** shows while the latest event of some kind (setup, import or export) failed and none of that kind has succeeded since; an import/export success clears a setup failure. It is hidden while the account row already explains the problem. CloudKit codes become short sentences (offline, iCloud busy, storage full, …); anything else shows its domain and code.
5. **Notifications:** the switch is per device (§11). Turning it on asks for permission — the only place the Mac asks. The summary switch is disabled while notifications are off (its value is kept); the time picker shows only while the summary is on. The denied explanation shows only while the switch is on.
6. **Summary time** is edited on a fixed reference day, so a DST day can never shift the stored minute. The picker follows the device's 12/24-hour setting (system control).
7. **Export:** iPhone — the share sheet (AirDrop, Files, Mail…), with the file written when the button is tapped; Mac — the save panel. Preparing the file first (instead of `ShareLink` exporting lazily inside the sheet) is what lets a failure show "Couldn’t Export" with its sentence. The name uses the device's local date: `Scribe-2026-10-05.json`.
8. **iPhone entry** is a gear `SettingsButton` presenting a sheet closed with the iOS 26 X (`.close` role — nothing to confirm, and no second prominent button); placement is the controller's (spec §9.2 says the Categories toolbar; that tab is becoming Lists).
9. **UI test entry:** DEBUG-only `-settingsButton` overlays the real button on the app root (and `-showSettings` opens it at launch for screenshots) — no edit to the iPhone screens. After the merge the test can tap the toolbar button instead.
10. **Mac hotkey:** KeyboardShortcuts' recorder with its default conflict policy; the persistent orange warning reuses the menu bar's sentence. "Restore ⌃⇧Space" resets to the default. A cleared shortcut leaves quick add in the menu bar.
11. **No Settings link in the menu bar panel:** the panel hands activation back to the previous app when it closes, which would push a just-opened Settings window behind it. ⌘, and the app menu are the way in.
12. **Version line:** "0.1 (1)" from the bundle (`CFBundleShortVersionString`, `CFBundleVersion`).

## Implementation notes

- Screenshots: iPhone with `xcrun simctl launch … -uiTesting -showSettings -demoSync … -demoPermission …`; Mac from a background-launched Debug build (`open -g -n … --args -uiTesting -demoData -showSettings …`, `screencapture -l <window>`), never driven.
- `SyncMonitor` keeps the CloudKit container it makes, so `CKAccountChanged` keeps arriving; a Mac process without the iCloud entitlement never makes one.
- `QuickAddHotkey.status` is now backed by an `@Observable` state, refreshed at install, when Settings appears and after the recorder or Restore changes the shortcut.
