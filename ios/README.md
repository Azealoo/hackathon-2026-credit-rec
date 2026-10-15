# Paywise iOS

Xcode 27, iOS 27.0+, iPhone only. Targets: **Paywise** (app), **PaywiseWidgets** (Live Activity extension), **PaywiseTests**.
`Shared/` is compiled into both the app and the extension. `data/cards.json` is bundled as a file reference (no copy).

`project.yml` is the source of truth. After editing it, run `xcodegen` in this folder and commit the regenerated `Paywise.xcodeproj`.

## Signing

Automatic signing, team `645L37J78Q`. The Apple Development certificate, the registered iPhone and the
App Group profiles (`group.com.azealoo.paywise`) already exist. The keychain is set to **Always Allow** for codesign,
so the commands below run without prompts.

## Commands (non-interactive)

Run from `ios/`. `$DD` is any DerivedData folder, for example `/tmp/paywise-dd`.

```bash
# Unit tests (simulator)
xcodebuild -project Paywise.xcodeproj -scheme Paywise -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath "$DD" test

# Device build (signs, refreshes profiles, registers the phone if needed)
xcodebuild -project Paywise.xcodeproj -scheme Paywise -configuration Debug -destination 'id=00008140-001858591EE0801C' -derivedDataPath "$DD" -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

# Install and launch (the phone must be unlocked to launch)
xcrun devicectl device install app --device 00008140-001858591EE0801C "$DD/Build/Products/Debug-iphoneos/Paywise.app"
xcrun devicectl device process launch --device 00008140-001858591EE0801C --terminate-existing com.azealoo.paywise
```

## Checking the island

Debug builds have a **Debug** section with *Start sample Live Activity* / *End Live Activity* (SPEC §6.3 *Checking* state).
To start it without tapping, pass `-autostartSampleActivity` and read the state changes on the console:

```bash
xcrun devicectl device process launch --device 00008140-001858591EE0801C --terminate-existing --console -- com.azealoo.paywise -autostartSampleActivity
```

Then go to the Home Screen: the island only shows while Paywise isn't in the foreground. On the simulator, use the
iOS Simulator tool's screenshot (`xcrun simctl io … screenshot` omits the island); long-press the island to expand it.
