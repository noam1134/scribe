# Phase 0 Findings — Sync Spike

Date: 2026-10-05
Devices: iPhone "Noam" (iPhone18,1, iOS 27.0), Mac (macOS 27.0)
Build: branch phase0-sync-spike, commit 5bbeae0

## Setup findings (before measurements)

- **App Group must be registered by hand.** `xcodebuild -allowProvisioningUpdates` registered the App IDs and the iCloud container but not the App Group. Without it the Mac app died at launch with CoreData "Sandbox access to file-read-data denied" on `~/Library/Group Containers/group.com.noamchuri.scribe`. After registering `group.com.noamchuri.scribe` in the developer portal (App Groups capability on `com.noamchuri.scribe` and `com.noamchuri.scribe.widgets`) and deleting Xcode's stale cached profiles, both Mac and iOS profiles include the group and the app opens its store.
- **Signing from the agent shell needs the Bash sandbox off** (Apple auth hosts are unreachable from inside it), and the Mac must be registered as a device (`-allowProvisioningDeviceRegistration`).
- **First sync after install is slow:** 4 notes added on the iPhone right after first launch arrived on the Mac in one import 34–112 s later (one-time zone/schema setup).

## Measurements

Arrival times on the Mac come from the store's persistent history (`ATRANSACTION` rows authored by `NSCloudKitMirroringDelegate.import`), compared with each note's creation time.

| ID | Scenario | Result (seconds) | Notes |
|----|----------|------------------|-------|
| M1 | Both apps open, add on iPhone ×3 within 5 s → visible on Mac | **Never by push.** Batch: 23.9–36.5 s but pulled by Mac-side clicks. Clean single add 13:23:57: arrived 13:33:17, 2.8 s after Mac activation. Repeat after adding `registerForRemoteNotifications` (registration succeeded, Mac awake, app frontmost): iPhone note 13:56:50 uploaded at once (`NEEDSUPLOAD = 0`), no push ever reached the Mac in 3.5 min, imported 14:00:24 (214 s), ~2 s after re-activation | **The Mac app only imports when it becomes active.** Registering for remote notifications did not change that. |
| M1r | Both apps open, add on Mac ×3 within 5 s → visible on iPhone | 3.1–3.5 (iPhone store history) | iPhone in foreground receives pushes; Mac exports immediately on save. |
| M2 | iPhone app backgrounded, add on Mac → iPhone widget updates? | **No update for 6+ min.** Mac note 13:41:57 was imported on the iPhone at 13:48:44 (407 s) — the moment the app was reopened | iOS did not wake the suspended app for the CloudKit silent push (build has `UIBackgroundModes: remote-notification` and `aps-environment: development`, verified). Silent pushes are low-priority and throttled by iOS. |
| M2b | Same as M2 with Low Power Mode ON | Skipped | M2 already fails without Low Power Mode. |
| M3 | iPhone app force-quit, tap widget "+" → note written? reaches Mac? | **Nothing written** (iPhone store pulled afterwards: no new note) | Same root-cause candidate as M4: the device had not registered Scribe's App Intents. Unverified; Phase 4 re-tests on device. |
| M4 | iPhone app force-quit, run "Add probe note in Scribe" from Shortcuts | **Scribe not listed in Shortcuts on the iPhone** (also not via "Add Action" search) | In the iOS 26.3 simulator the same build lists "Add Probe Note" under Scribe; running it launched the app in the background and wrote `shortcut via app` (intent runs in the **app** process). Metadata.appintents is present in app and widget bundles. Likely App Intents indexing lag after a `devicectl` install. |
| M5 | iPhone Control "Add Probe" | **Nothing written** | See M3. |
| M6 | Sync events visible (setup/import/export)? Remote-change notifications fire? | **Yes** | `NSPersistentCloudKitContainer.eventChangedNotification` delivers setup/import/export start + success under SwiftData; `NSPersistentStoreRemoteChange` fires on every import and local save. Store history (`ATRANSACTION`) also exposes import times. |
| M7 | Mac widget shows Mac store contents? | Deferred to Phase 4 | Mac widget profile now carries the App Group (the mechanism the Mac app uses successfully). |
| M8 | iPhone in Airplane Mode, add, reconnect → reaches Mac? | Inconclusive | The offline add used the widget "+", which wrote nothing (M3). Core Data's export queue is standard behaviour; re-test with the app in Phase 2. |
| M9 | Mac: "Add Probe Note" among Control Center / menu bar controls? | Deferred to Phase 4 | `ControlWidget` compiles with a macOS 26 target. |

## Answers to spec §14

1. Cross-device sync works (target ≤ ~60 s with both apps open): **Partly.** Mac → iPhone ≈ 3 s while the iPhone app is in front. iPhone → Mac: the iPhone uploads at once, but the Mac app receives **no CloudKit pushes** (not even after `registerForRemoteNotifications` succeeded, Mac awake, app frontmost) and only imports **~2 s after the app becomes active**. A suspended iPhone app is **not woken** by the silent push either (M2: 407 s, imported on reopen).
2. Out-of-app writes (widget / Siri / Control) reach the other device: **Unanswered on device** — none of the three ran on the iPhone (Shortcuts didn't list Scribe). In the simulator the shortcut ran in the app process and wrote to the shared store.
3. Sync events observable under SwiftData (→ "Last synced" in Settings): **Yes** (M6).
4. macOS App Group identifier that works: `group.com.noamchuri.scribe` — works once registered in the developer portal and present in the provisioning profile (no Team-ID-prefixed fallback needed).
5. Control widget on macOS 26+: compiles; runtime availability deferred to Phase 4.

## Decision

**GO WITH CHANGES** — decided by the author on 2026-10-05. (The plan's NO-GO rule ("M1 never syncs with both apps open") is technically met for iPhone → Mac, because the Mac only syncs on activation; the author chose to keep iCloud with the changes below.)

Changes required in later phases:
- §12 / Phase 3 (Mac): keep `registerForRemoteNotifications`; investigate why CloudKit pushes don't reach the Mac app (dev-signed build, APNs environment, CloudKit subscription); until fixed, the Mac shows the latest data within ~2 s of becoming active, and the menu bar panel must trigger activation when opened.
- §10 / §11 / Phase 4–5 (iPhone): iOS won't reliably wake the app for silent pushes, so widgets and notifications can be stale until the app runs. Add a `BGAppRefreshTask` that lets the app import and reload widgets opportunistically; document that widget data can lag.
- §8 / Phase 4: first thing on device, confirm Scribe's App Intents are registered (Shortcuts lists them) and that widget "+" / checkbox and Control actions write; record which process runs them.
- §13 / Phase 6: "Last synced" is feasible — use `NSPersistentCloudKitContainer.eventChangedNotification`.
- §16 build notes: register App Groups manually in the developer portal; signed builds need `-allowProvisioningDeviceRegistration` and their own derived-data folder; the agent shell needs its sandbox off for signing.
