# Scribe

A native notes app, written in Swift.

## Status

Early setup. Design in progress.

## Development

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and is not checked in.

```bash
brew install xcodegen
xcodegen generate
open Scribe.xcodeproj
```

### Signing and devices

- Register the App Group `group.com.noamchuri.scribe` in the Apple Developer portal and enable App Groups (with that group) on the App IDs `com.noamchuri.scribe` and `com.noamchuri.scribe.widgets`. Command-line automatic signing does not register App Groups.
- The first signed build for a new Mac or iPhone needs `-allowProvisioningUpdates -allowProvisioningDeviceRegistration`.
- Keep signed builds in their own derived-data folder (for example `-derivedDataPath build/dd-signed`); sharing one with unsigned builds breaks code signing of the widget extension.
