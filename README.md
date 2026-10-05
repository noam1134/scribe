# Scribe

A native notes app, written in Swift.

## Status

Built so far:

- **iPhone app:** Upcoming, categories, inline editing, quick-add with English + Hebrew parsing, search, iCloud sync.
- **Mac app:** sidebar + list with inline editing, keyboard shortcuts, search, a menu bar extra and the ⌃⇧Space quick-add panel.
- **Widgets:** an Upcoming widget (iPhone home and lock screen, Mac desktop, optionally one category) with checkboxes, plus an "Add to Scribe" Control.
- **Siri and Shortcuts:** "Add to Scribe", which asks for a category when the text has no `#tag`.
- **Notifications:** an alert at each timed item's due time, with Done / +1 hour / Tomorrow, and a morning summary of the day. On by default on iPhone, off on Mac.

Settings come next.

## Development

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and is not checked in.

```bash
brew install xcodegen
xcodegen generate
open Scribe.xcodeproj
```

### Tests

```bash
(cd Core && swift test)                    # Core unit tests
xcodebuild -project Scribe.xcodeproj -scheme Scribe \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" test   # UI smoke tests
```

`NotificationUITests` waits for real notifications (about five minutes; fails in the minutes before midnight), so it is skipped unless you prefix the command with `TEST_RUNNER_SCRIBE_RUN_NOTIFICATION_UI_TESTS=1`.

### Signing and devices

- Register the App Group `group.com.noamchuri.scribe` in the Apple Developer portal and enable App Groups (with that group) on the App IDs `com.noamchuri.scribe` and `com.noamchuri.scribe.widgets`. Command-line automatic signing does not register App Groups.
- The first signed build for a new Mac or iPhone needs `-allowProvisioningUpdates -allowProvisioningDeviceRegistration`.
- Keep signed builds in their own derived-data folder (for example `-derivedDataPath build/dd-signed`); sharing one with unsigned builds breaks code signing of the widget extension.
