# Scribe Phase 5 — Notifications Implementation Plan

**Goal:** Notifications per spec §11: one alert at each timed item's due time, a morning summary on days with items, Done / +1 hour / Tomorrow actions that change the item (so they sync), a 60-request budget, per-device settings, and rescheduling after every local write, sync import, app activation and day change.

**Architecture:** Everything that decides *what* to schedule is pure and lives in `ScribeCore/Notifications/` with Swift Testing tests: the planner (snapshots + now + calendar + settings → the exact requests), the diff against what is already pending, the action logic (applied through `ItemStore`), and the settings value with its `UserDefaults` encoding. The app keeps one thin, cross-platform object, `App/Shared/NotificationCoordinator.swift`: it is the `UNUserNotificationCenterDelegate`, watches the store with Observation, maps plans to `UNNotificationRequest`s, asks for permission at the right moment, and exposes the settings and the permission state to Phase 6.

**Spec:** §5.2 (floating due dates), §6 (agenda rules the summary reuses), §11, §12, §13 ("Notification permission denied"), §15, §18. Backlog: "Phase 5–6" (`ItemFilter` has no `.all`).

**Not in this phase:** the Settings screen (Phase 6), widgets/intents/background refresh (Phase 4), the Mac UI (Phase 3).

## Global Constraints

Phase 2's constraints apply (Swift 6, iOS/macOS 26, ScribeCore imports only Foundation/Observation/SwiftData, no model changes, zero warnings, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`). Additionally:

- Simulator: "Scribe P5", id `B85C8B39-D495-4992-B2A5-812B8671F428` (derived data `build/dd-sim`).
- Branch `phase5-notifications` in `.worktrees/phase5-notifications`. Phases 3 and 4 run in parallel: shared files (`App/ScribeApp.swift`, `Core/.../ItemStore.swift`, `SwiftDataItemStore.swift`) get small, localized edits only.
- No new entitlements, capabilities, background modes or Info.plist keys are needed for local notifications.

## File Map

| File | Responsibility | Task |
|---|---|---|
| `Core/Sources/ScribeCore/Store/ItemStore.swift`, `SwiftDataItemStore.swift` | `ItemFilter.all` (same definition as Phase 4) | 1 |
| `Core/Sources/ScribeCore/Notifications/NotificationSettings.swift` | Per-device settings value, platform defaults, `UserDefaults` encoding | 2 |
| `Core/Sources/ScribeCore/Notifications/PlannedNotification.swift` | One planned request: id, kind, fire date, floating trigger, content, link, fingerprint | 3 |
| `Core/Sources/ScribeCore/Notifications/NotificationPlanner.swift` | Items → due alerts + morning summaries, nearest-first, capped at 60 | 3 |
| `Core/Sources/ScribeCore/Notifications/NotificationDiff.swift` | Pending vs planned → ids to remove, requests to add | 4 |
| `Core/Sources/ScribeCore/Notifications/NotificationAction.swift` | Done / +1 hour / Tomorrow: identifiers and how each changes the item | 5 |
| `Core/Sources/ScribeCore/Notifications/NotificationScheduler.swift` | (review fix) Passes, permission, settings, actions, store opening — behind `NotificationCenterClient`, unit-tested with a fake center | 6 |
| `App/Shared/NotificationCoordinator.swift` | Delegate, loader hand-off, activation/day/time-zone hooks, log; Phase 6's API | 6 |
| `App/Shared/SystemNotificationCenter.swift` | `UNUserNotificationCenter` as a `NotificationCenterClient`; `PlannedNotification` → `UNNotificationRequest`; the three categories | 6 |
| `App/ScribeApp.swift` | `init()` installs the coordinator before launch finishes | 6 |
| `UITests/NotificationUITests.swift` | Due-time alert appears and tapping it opens the item (opt-in flag) | 7 |
| `README.md`, `docs/backlog.md` | Status, device checklist pointer, backlog | 8 |

## Tasks

### Task 1: `ItemFilter.all`

- `ItemFilter.all` — "Every item, done ones included." — last enum case; `SwiftDataItemStore.items(.all)` returns them in `ItemOrdering.list` order. Identical to Phase 4's addition so the merge is clean.
- Test (`NotificationStoreTests`): `.all` returns done and open items, dated and undated, from every category and the Inbox.

### Task 2: Settings

```swift
public struct NotificationSettings: Equatable, Sendable {
    public var isEnabled: Bool               // master switch: item alerts AND the summary
    public var morningSummaryEnabled: Bool
    public var morningSummaryMinute: Int     // minutes after local midnight, 0..<1440
    public static let iOSDefault, macOSDefault, platformDefault
    public init(from defaults: UserDefaults, fallback: NotificationSettings = .platformDefault)
    public func save(to defaults: UserDefaults)
}
```
Defaults (spec §11): on for iOS, off for macOS; summary on at 09:00. Keys `notifications.enabled`, `notifications.morningSummary`, `notifications.morningSummaryMinute`; a missing or out-of-range value falls back.
Tests: defaults per platform, round trip, missing keys, out-of-range minute.

### Task 3: Planner

```swift
public struct NotificationPlanner: Sendable {
    public static let requestLimit = 60     // iOS keeps at most 64 pending
    public static let summaryDays = 7
    public init(calendar: Calendar, locale: Locale)
    public func plan(items: [ItemSnapshot], categories: [CategorySnapshot],
                     settings: NotificationSettings, now: Date,
                     limit: Int = requestLimit) -> [PlannedNotification]
}
```
- Due alerts: every not-done item (tasks and memos) with a time whose fire date is after `now`. Id `item.<uuid>`. Content: title = item title; body = "14:00 · Category" plus the notes' first line. Category `scribe.item.task` (Done, +1 hour, Tomorrow) or `scribe.item.memo` (+1 hour, Tomorrow). Link `scribe://item/<id>`.
- Morning summaries: the next 7 summary times strictly after `now` (today's only if not yet passed). One per day whose agenda day (§6 rules, via `AgendaBuilder`) has at least one item. Title "Today: 3"; body "A, B, C, …" plus "Overdue: 2" when open tasks are due before that day. Id `summary.<yyyy-MM-dd>`, category `scribe.summary`, link `scribe://upcoming`.
- Budget: summaries first (≤ 7), then due alerts nearest-first; total ≤ `limit`. Output sorted by fire date, ties by id.
- Floating trigger: `DateComponents` year…minute of the fire date in the device calendar, no time zone — the alert fires at that wall-clock time wherever the device is (spec §5.2).
- Fingerprint: a stable FNV-1a hash of everything that is shown or scheduled, stored in `userInfo` so unchanged requests aren't re-added.
Tests: past/done/untimed items, memos, ordering, ties, cap (61+ timed items, summaries kept), summary content (count, three titles, ellipsis, overdue, memos never overdue, days without items skipped, today's passed summary skipped, summary disabled, master switch off), category name and Inbox body, Hebrew titles, time zones (traveling), DST (spring-forward gap, fall-back), non-Gregorian device calendar.

### Task 4: Diff

`NotificationDiff(pending: [(id, fingerprint?)], planned:)` → `remove` (ours, no longer planned; sorted) and `add` (new or changed). Ids that don't belong to the planner are never touched. Tests: idempotent replan → empty diff; changed content re-added; vanished removed; foreign ids kept.

### Task 5: Actions

```swift
public enum NotificationAction: String, CaseIterable, Sendable { case done, inAnHour, tomorrow }
// identifiers "scribe.action.done" / ".inAnHour" / ".tomorrow"
public func perform(itemID: UUID, store: any ItemStore, now: Date, calendar: Calendar) throws
public static func dueInAnHour(from:calendar:) -> DueDate                // now + 60 min, seconds dropped, rounded up to 5 min
public static func dueTomorrow(after:today:calendar:) -> DueDate         // day after max(due day, today), time kept
```
A missing item is ignored (deleted on another device). Done on a memo is a no-op (store rule). Tests with the in-memory store: each action, midnight crossing, exact 5-minute boundary, seconds dropped before rounding (14:00:20 → 15:00), stale notification, missing item.

### Task 6: App scheduler (`NotificationCoordinator`)

- `ScribeApp.init()` creates the `StoreLoader`, then `NotificationCoordinator.shared.install(loader:)`: sets the delegate and the categories before launch finishes, and watches `loader.state` (Observation) to start once the store is ready — no `StoreLoader` edit.
- Rescheduling: `withObservationTracking` around the store reads (`items(.all)`, `categories`), so every write and every `refresh()` (CloudKit import, remote change, activation) triggers a reschedule; plus app activation, `NSCalendarDayChanged`, `NSSystemTimeZoneDidChange`, and settings changes. Coalesced (0.3 s) and serialized.
- Permission: asked only when the plan is non-empty, the master switch is on and the app is active — so never on a launch with nothing to notify. `permission: NotificationPermission` (`.notDetermined / .denied / .allowed`) refreshed on activation; scheduling is skipped unless allowed.
- Delegate: `willPresent` → banner + list + sound; `didReceive` → default tap sets `loader.pendingLink`; an action loads the store if the app was launched in the background, runs `NotificationAction.perform`, and reschedules before returning.
- Delivered alerts of items that are now done or deleted are removed.
- `-uiTesting` disables the coordinator unless `-enableNotifications` is also passed (keeps the permission alert out of the smoke tests).
- A `notice` log line after each reschedule (counts, and ids in Debug) — the simulator check reads it with `log show`.
- Phase 6 API: `settings` (bindable), `permission`, `requestPermission()`, `systemSettingsURL`. `rescheduleNow()` for a background task that must finish before suspension.

### Task 7: Simulator verification

- `NotificationUITests.testAlertsAndMorningSummary` (`-uiTesting -enableNotifications`, answers the permission alert): two items due 2 and 3 minutes ahead and a morning summary moved to 5 minutes after launch (launch-argument override of `notifications.morningSummaryMinute`). With the app in the background, Done on the first banner completes the task; tapping the second banner opens the item; the summary reads "Today: 1" without the done task and opens Upcoming. About 4.5 minutes.
- The `notice` log (`log stream --predicate 'subsystem == "com.noamchuri.scribe"'`) shows each pass: planned count, added/removed, permission, pending ids (Debug).

### Task 8: Docs and final run

README status line, backlog (remove the Phase 5 item, add follow-ups), report.

## Decisions

1. **Summary days:** only days whose own agenda (items due that day) is non-empty get a summary; overdue tasks alone don't trigger one. The overdue count is projected ("open tasks due before that day") and refreshed on every change.
2. **Summary slots:** the next 7 summary times after now. If today's time has passed, the 7 days start tomorrow.
3. **Timed memos alert too** (with +1 hour / Tomorrow; Done is task-only).
4. **Floating triggers:** calendar triggers without a time zone, so a 09:00 item alerts at 09:00 local time in Thailand or Bulgaria too (spec §5.2). Components come from the device calendar, so non-Gregorian device calendars still fire on the right day. A time skipped by a DST jump fires at the shifted time Foundation resolves (02:30 → 03:30).
5. **Tomorrow:** the day after the later of the item's due day and today (spec: "dueDay +1"; the "today" floor keeps the label honest when an old alert is acted on late). The time is kept.
6. **+1 hour:** now + 60 minutes, seconds dropped, rounded up to the next multiple of 5 minutes (14:00:20 → 15:00, 14:03 → 15:05); may cross midnight into the next day.
7. **Identifiers:** `item.<uuid>` (one alert per item, so a moved time replaces the old request) and `summary.<yyyy-MM-dd>`, public as `PlannedNotification.identifier(forItem:)` / `identifier(forSummaryOn:)` for other processes.
8. **Permission moment:** the first time there is something to notify while the app is in front — in practice right after adding the first dated or timed item. On macOS (off by default) the prompt comes when Phase 6 turns the switch on.
9. **Actions run in the background** (no `.foreground`, no unlock required — like Reminders). Tapping the summary opens Upcoming; tapping an alert opens the item.
10. **Alerts show while the app is open** (banner + sound).
11. **Delivered alerts** of items that became done or were deleted are removed from Notification Center on the next reschedule.
12. **Settings storage:** the App Group's defaults (`NotificationSettings.appGroupDefaults`), so the widget and intents can read the master switch. Still per device: App Group defaults aren't synced.
13. **Store query:** `ItemFilter.all` (shared with Phase 4) rather than a planner-specific query; the planner filters. Reads already load every item for the other filters, so this costs the same.
14. **Copy:** English, like `DueLabels` (localization later). Due alert body "14:00 · Thailand" + first line of notes; summary "Today: 3" / "Book flights, Pay arnona, Call Dan, …" / "Overdue: 2".

## Review fixes (2026-10-05)

The scheduling logic moved from the app into Core (`NotificationScheduler` behind `NotificationCenterClient`), so it is unit-tested with a fake center: `rescheduleNow()` opens the store itself in a background launch; the permission prompt runs in its own task and never blocks a pass; a dropped action is reported. Also: public alert identifiers, App Group settings, a clamped summary minute, "+1 hour" drops seconds, the Mac settings URL opens Scribe's entry, and `NotificationUITests` is opt-in (`TEST_RUNNER_SCRIBE_RUN_NOTIFICATION_UI_TESTS=1`).

Round 2: passes prompt for permission at most once per process, and the scheduler re-plans after a prompt only once permission is decided — a prompt that fails while leaving it undetermined (an unsigned Mac build) no longer loops. `requestPermission()` (the Settings button) still tries once per call.
