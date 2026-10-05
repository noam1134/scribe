# Scribe

A native notes app, written in Swift.

## Status

iPhone app usable (Phase 2): Upcoming, categories, inline editing, quick-add with English + Hebrew parsing, search, iCloud sync. Mac app, widgets, notifications and settings come next.

## Development

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and is not checked in.

```bash
brew install xcodegen
xcodegen generate
open Scribe.xcodeproj
```

### Tests

```bash
cd Core && swift test                      # Core unit tests
xcodebuild -project Scribe.xcodeproj -scheme Scribe \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" test   # UI smoke tests
```

### Signing and devices

- Register the App Group `group.com.noamchuri.scribe` in the Apple Developer portal and enable App Groups (with that group) on the App IDs `com.noamchuri.scribe` and `com.noamchuri.scribe.widgets`. Command-line automatic signing does not register App Groups.
- The first signed build for a new Mac or iPhone needs `-allowProvisioningUpdates -allowProvisioningDeviceRegistration`.
- Keep signed builds in their own derived-data folder (for example `-derivedDataPath build/dd-signed`); sharing one with unsigned builds breaks code signing of the widget extension.
