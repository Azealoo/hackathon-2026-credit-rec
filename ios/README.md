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

### Screenshot hooks (Debug builds only)

| Launch argument | Shows |
|---|---|
| `-demoActivity <state>` | Starts that Live Activity with the §6.3 copy for the demo wallet and leaves it running (never stale): `checking`, `keep`, `keepMethod`, `noCheckout`, `couldntCheck`, `switchFallback`, `stale` (staleDate in the past). Result states alert, so the island expands. |
| `-demoActivity end` | Ends every Paywise activity. |
| `-gallery <state>` | Opens on the result snippet in that state, full screen: `result`, `resultCashBest`, `resultCash`, `keepProtected`, `saved`, `sent`, `notSetUp`. |

```bash
xcrun simctl launch <device> com.azealoo.paywise -demoActivity keep
xcrun simctl launch --terminate-running-process <device> com.azealoo.paywise -demoActivity end
xcrun simctl spawn <device> log show --last 2m --predicate 'subsystem == "com.azealoo.paywise" AND category == "demo"'
```

The Debug section also has *Start demo state*. The states are built by the same code a press uses
(`Paywise/Debug/DemoChecks.swift` → `CopyFill` → `CheckFlow.islandState`); `LiveActivityStateTests` pins their copy to §6.3.

## Live Activity and assets

`PaywiseWidgets/PaywiseLiveActivity.swift` places the parts in `Shared/LiveActivityViews.swift`: leading = card art
(Keep, switch fallback) or the glyph; trailing = progress ring / ✓ / ⚠ / ••last4; long lines in the bottom region,
8 pt in. The Lock Screen says only "Paywise is checking" / "Paywise checked this screen". `ContentState.cardId` names
the card whose bundled art the island draws (§9.1).

`tools/make_assets.sh` rebuilds every visual asset from docs/design.md §5–§7 and `data/cards.json` (deterministic;
commit the output):

| Asset | Where | Size |
|---|---|---|
| `card-<id>` (expanded, snippet) | `Shared/Assets.xcassets` (app + widget) | 156 × 98 px @3x, 104 × 65 @2x |
| `card-<id>-compact` | `Shared/Assets.xcassets` | 157 × 110 px @3x (letterboxed), 104 × 73 @2x |
| `glyph` | `Shared/Assets.xcassets` | template SVG, 24 × 24 grid |
| `accent` | `Shared/Assets.xcassets` | #3f5bf6, dark #5b74ff |
| `AppIcon` | `Paywise/Assets.xcassets` | 1024 × 1024 standard, dark, tinted; opaque |
| `silent.caf` | `Shared/Sounds` (app + widget bundles) | 10 ms of silence, 16-bit PCM mono 44.1 kHz |

`AssetTests` checks the sizes (never above the slot), both bundles, the glyph, `accent`, the sound and the icon.

## Check chain (SPEC §15.5)

`CheckCheckoutIntent` (Shortcut action "Check Checkout") → on-device reading (`ScreenReader`; a placeholder that
throws until `VisionScreenReader` lands) → `POST /v1/check` (6.0 s; base URL from Info.plist `PaywiseAPIURL`) →
`CheckRecord` in `<AppGroup>/checks/` → result snippet (`CheckResultSnippetIntent`, buttons `SavePurchaseIntent` /
`ShowSentIntent`) or an island alert. Dependencies live in `Paywise/Check/Dependencies.swift`.

`Paywise/Check/PrivacyGuard.swift` is the backstop before sending, whatever the reader returned: it turns card
numbers (12+ digit runs, card-shaped or Luhn-valid separated numbers), "ending in dddd", masked last 4 ("••5678") and
the wallet's own last 4 beside a card word into `[CARD]`, rounds `ocrConfidence` to 2 places, and checks the whole
encoded body against the backend's privacy rule. A body that fails is never sent; the press ends on §6.3 *No checkout,
on device*, as a reading failure does.

The app's **Check** section switches, without a rebuild (App Group `UserDefaults`):

| Key | Values | Default |
|---|---|---|
| `snippetMode` | `snippet` (Pattern A) · `confirm` (Pattern B) · `island` (§6.6 G2 fallback, 8 s `.default` alert) | `snippet` |
| `silentAlerts` | `true` → `.named("silent.caf")` · `false` → `.default` | `true` |
| `replayEnabled` | replay `fixtures/replay/<merchantId>_<totalCents>.json` when the request fails | `true` |
