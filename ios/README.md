# Paywise iOS

Xcode 27, iOS 27.0+, iPhone only. Targets: **Paywise** (app), **PaywiseWidgets** (Live Activity extension), **PaywiseTests**
(offline unit tests), **PaywiseUITests** (UI tests against the live backend, and the screenshot tour).
`Shared/` is compiled into both the app and the extension. `data/cards.json` is bundled as a file reference (no copy).

`project.yml` is the source of truth. After editing it, run `xcodegen` in this folder and commit the regenerated `Paywise.xcodeproj`.

## Signing

Automatic signing, team `645L37J78Q`. The Apple Development certificate, the registered iPhone and the
App Group profiles (`group.com.azealoo.paywise`) already exist. The keychain is set to **Always Allow** for codesign,
so the commands below run without prompts.

## Commands (non-interactive)

Run from `ios/`. `$DD` is any DerivedData folder, for example `/tmp/paywise-dd`. `$DEVICE_ID` is your iPhone's
UDID: run `xcrun devicectl list devices` and copy the phone's Identifier (the one marked UDID).

```bash
# Unit tests (simulator, offline). The Paywise scheme also holds the live UI tests, so name the suite.
xcodebuild -project Paywise.xcodeproj -scheme Paywise -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath "$DD" -only-testing:PaywiseTests test

# Device build (signs, refreshes profiles, registers the phone if needed)
xcodebuild -project Paywise.xcodeproj -scheme Paywise -configuration Debug -destination "id=$DEVICE_ID" -derivedDataPath "$DD" -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

# Install and launch (the phone must be unlocked to launch)
xcrun devicectl device install app --device "$DEVICE_ID" "$DD/Build/Products/Debug-iphoneos/Paywise.app"
xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing com.azealoo.paywise
```

## Checking the island

Debug builds have a **Debug** section with *Start sample Live Activity* / *End Live Activity* (SPEC §6.3 *Checking* state).
To start it without tapping, pass `-autostartSampleActivity` and read the state changes on the console:

```bash
xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing --console -- com.azealoo.paywise -autostartSampleActivity
```

Then go to the Home Screen: the island only shows while Paywise isn't in the foreground. On the simulator, use the
iOS Simulator tool's screenshot (`xcrun simctl io … screenshot` omits the island); long-press the island to expand it.

### Screenshot hooks (Debug builds only)

| Launch argument | Shows |
|---|---|
| `-demoActivity <state>` | Starts that Live Activity with the §6.3 copy for the demo wallet and leaves it running (never stale): `checking`, `keep`, `keepMethod`, `noCheckout`, `couldntCheck`, `switchFallback`, `stale` (staleDate in the past). Result states alert, so the island expands. |
| `-demoActivity end` | Ends every Paywise activity. |
| `-gallery <state>` | Opens on the result snippet in that state, full screen: `result`, `resultCashBest`, `resultCash`, `keepProtected`, `saved`, `savedEarbuds` (the longer "Wireless Earbuds" Saved line 1), `savedLongName` (a name too long for one line: cut, price kept), `sent`, `notSetUp`. |
| `-checkState <state>` | Opens the Check tab on an answer the island shows after a press, as "Check a screenshot" shows it: `keepDefault`, `keepMethod`, `keepItemsUnreadable`, `noCheckoutOnDevice`, `noCheckoutFromBackend`, `alreadyPaid`, `couldntCheck`, `tookTooLong` (use with `-skipOnboarding -tab check`). |

```bash
xcrun simctl launch <device> com.azealoo.paywise -demoActivity keep
xcrun simctl launch --terminate-running-process <device> com.azealoo.paywise -demoActivity end
xcrun simctl spawn <device> log show --last 2m --predicate 'subsystem == "com.azealoo.paywise" AND category == "demo"'
```

### Test hooks (Debug builds only)

| Launch argument | Does |
|---|---|
| `-resetState` | Clears the wallet, purchases, check records, onboarding and the date override before any screen loads. |
| `-skipOnboarding` | Seeds the demo wallet (`demo-3card`) and opens the tabs. |
| `-dateOverride YYYY-MM-DD` | Turns on Settings › "Pretend today is…" with that day (the check's `clientDate` and the claim's `asOf`). |
| `-tab check\|purchases\|settings` | Opens on that tab. |
| `-doubleSave` | The in-app [Paying with …] starts two saves at once and reports what each returned (`debug.saveOutcomes`), so a UI test can show two racing saves make one purchase. A synthesized double tap reaches a SwiftUI button as one action. |
| `-showBackTapPrompt` | The Check tab opens with the Back Tap prompt up (use with `-skipOnboarding -tab check`). |
| `-forceReduceMotion` | Reduce Motion reads as on everywhere (the prompt's two still frames, a still breadcrumb). |
| `-simulateBackTap` | "Try it now" gets a press 1.5 s after it opens: the real check (`CheckFlow`, live backend) on a render of its own screen, as the Shortcut would run it, so it turns to "Back Tap works ✓". |

### Back Tap prompt and setup

iOS has no Back Tap API: an app can't turn it on, read whether it's on, or open Accessibility › Touch › Back Tap
(`openSettingsURLString` opens Paywise's own page). So the app asks in its own sheet
(`Paywise/Onboarding/BackTapPrompt.swift`: a looping KeyframeAnimator demo with a CoreHaptics two-tap, still frames
under Reduce Motion), shows the path (`TriggerSetupView`: Back Tap first, the Action Button as "Prefer a button?"),
and confirms it on "Try it now": the Shortcut runs Check Checkout in the app's process, so a `CheckRecord` that wasn't
in the App Group when the step opened means the press arrived. The prompt is onboarding's trigger step and shows once
more in the Check tab, back at the tab's start after the 2nd in-app check, if setup was skipped; [Not Now]
(`backTapPromptDeclined`) and a confirmed setup (`triggerSetupConfirmed`) end it. `BackTapSetupTests` covers the rules,
the haptic timing and a render of "Try it now" read by `VisionScreenReader` and the gate.

### UI tests against the live backend, and the screenshot tour

`PaywiseUITests` runs against https://paywise-api-n0f9.onrender.com. It is in the `Paywise` scheme's test action, so a
plain `test` runs it too (about 6 minutes, network needed): pick a suite with `-only-testing:PaywiseTests` or
`-only-testing:PaywiseUITests`.

| Test | Checks |
|---|---|
| `AppShellUITests/testCheckAScreenshotLive` | "Check a screenshot" → newest photo → the exact §6.3 *Switch* lines and instruction within 6 s of the pick (time printed as `PAYWISE_UI`). |
| `AppShellUITests/testSaveIsIdempotent` | [Paying with Freedom] with `-doubleSave` → two saves race on one check, one returns "saved" and one "alreadySaved" → *Saved* → Purchases has one row, the §15.7 step 12a line word for word (also after a relaunch). A double tap on the system snippet stays the on-device check in §15.7 step 12a. |
| `AppShellUITests/testClaimCases1and2` | The purchase checked and saved on Oct 17, 2026, then claims on Dec 18, 2027: case 1 → "May be eligible" + "Extended warranty"; case 2 → "Not covered" (read from the web view). |
| `BackTapPromptUITests` | The Back Tap prompt is onboarding's trigger step with [Set Up Back Tap] and [Not Now]; [Not Now] holds after a relaunch and after the 2nd in-app check; with setup skipped, the prompt shows once after the 2nd check; Saved's [What we sent] and [Done] sit side by side (same row, equal widths, 10 pt apart); Settings › Set Up Back Tap (a sheet) › Try it now with `-simulateBackTap` → "Back Tap works ✓" → [Done] closes the setup, back to Settings. |
| `ScreenshotTourUITests/testScreenshotTour` | Every screen and state (including the `-checkState` answers, [No, another card], [Don't know] → "Assumed", the delete confirmation, the Back Tap prompt in onboarding, again after the 2nd check and under Reduce Motion, Set Up Back Tap, Try it now and "Back Tap works ✓"), plus the `-gallery` snippet states, as `docs/overnight-shots/<appearance>-<size>/NN-<screen>.png`. |

They pick the newest photo in the PhotosPicker, so add the demo laptop checkout to the simulator's Photos first:

```bash
xcrun simctl addmedia <device> ../fixtures/screenshots/laptop-checkout.png
xcodebuild -project Paywise.xcodeproj -scheme Paywise -destination 'platform=iOS Simulator,id=<device>' -derivedDataPath "$DD" -only-testing:PaywiseUITests/AppShellUITests test
```

`tools/run_ui_tour.sh` does all of it on the simulator "Paywise Dev 18" (created if missing; `PAYWISE_SIM` picks
another): warms Render, adds a copy of the photo dated now (addmedia dates a PNG by its file's modification time, and
the picker sorts by date), sets the status bar to 9:41, builds once, runs the live tests, then the tour
four times (light, dark, light at Dynamic Type extra-large and extra-extra-large → `light-default`, `dark-default`,
`light-xl`, `light-xxl`), and
puts the appearance, text size and status bar back. `tools/run_ui_tour.sh live` or `… tour` runs one part. The tour's
folder comes from `TEST_RUNNER_PAYWISE_SHOTS=<name>` on the xcodebuild command line. xcodebuild 27 can hang after the
last test; the script stops it after 60 s and reads the result from the log.

Settings › Debug also has *Start demo state*. The states are built by the same code a press uses
(`Paywise/Debug/DemoChecks.swift` → `CopyFill` → `CheckFlow.islandState`); `LiveActivityStateTests` pins their copy to §6.3.

## Live Activity and assets

`PaywiseWidgets/PaywiseLiveActivity.swift` places the parts in `Shared/LiveActivityViews.swift`: leading = card art
(Keep, switch fallback) or the glyph; trailing = progress ring / ✓ / ⚠ / ••last4; long lines in the bottom region,
8 pt in. The Lock Screen says only "Paywise is checking" / "Paywise checked this screen". `ContentState.cardId` names
the card whose bundled art the island draws (§9.1).

`tools/make_assets.sh` rebuilds every visual asset from docs/design.md §5–§7, `data/cards.json` and the logo in
`brand/08-monoline` (option 08 "Monoline"; deterministic; commit the output). The standard app icon is the opaque
1024 PNG already in `AppIcon.appiconset`; `tools/make_assets.sh <png>` replaces it first. Dark and tinted are drawn
from `brand/08-monoline/app-icon.svg`.

| Asset | Where | Size |
|---|---|---|
| `card-<id>` (expanded, snippet) | `Shared/Assets.xcassets` (app + widget) | 156 × 98 px @3x, 104 × 65 @2x |
| `card-<id>-compact` | `Shared/Assets.xcassets` | 157 × 110 px @3x (letterboxed), 104 × 73 @2x |
| `glyph` | `Shared/Assets.xcassets` | the island mark, vector: `brand/08-monoline/mark-island.svg` (Any), `mark-island-dark.svg` (Dark); the Live Activity's glyph (island, minimal, stale, Lock Screen) |
| `accent` | `Shared/Assets.xcassets` | #3f5bf6, dark #5b74ff |
| `AppIcon` | `Paywise/Assets.xcassets` | 1024 × 1024: standard opaque; dark (paper + #5b74ff lines) and tinted (grayscale) on transparent |
| `mark` | `Paywise/Assets.xcassets` (app only) | the logo, vector: `mark.svg` (Any), `mark-dark.svg` (Dark); onboarding, result header, Checking card |
| `silent.caf` | `Shared/Sounds` (app + widget bundles) | 10 ms of silence, 16-bit PCM mono 44.1 kHz |

`AssetTests` checks the sizes (never above the slot), both bundles, the glyph, `accent`, the sound, the icon's three
appearances (and their alpha) and the mark's Any/Dark. `tools/run_ui_tour.sh icon` saves the home-screen icon in light,
dark and tinted to `docs/overnight-shots/brand/`.

## Check chain (SPEC §15.5)

`CheckCheckoutIntent` (Shortcut action "Check Checkout") → on-device reading (`ScreenReader`: `VisionScreenReader` crops, runs Vision OCR,
the checkout gate and redaction) → `POST /v1/check` (6.0 s; base URL from Info.plist `PaywiseAPIURL`) →
`CheckRecord` in `<AppGroup>/checks/` → result snippet (`CheckResultSnippetIntent`, buttons `SavePurchaseIntent` /
`ShowSentIntent`) or an island alert. Dependencies live in `Paywise/Check/Dependencies.swift`.

`Paywise/Check/PrivacyGuard.swift` is the backstop before sending, whatever the reader returned: it turns card
numbers (12+ digit runs, card-shaped or Luhn-valid separated numbers), "ending in dddd", masked last 4 ("••5678") and
the wallet's own last 4 beside a card word into `[CARD]`, rounds `ocrConfidence` to 2 places, and checks the whole
encoded body against the backend's privacy rule. A body that fails is never sent; the press ends on §6.3 *No checkout,
on device*, as a reading failure does.

**Settings › Results** switches, without a rebuild (App Group `UserDefaults`; the picker reads "Snippet with a
Paying with button" / "System confirm prompt" / "Island alert, held 8 s"):

| Key | Values | Default |
|---|---|---|
| `snippetMode` | `snippet` (Pattern A) · `confirm` (Pattern B) · `island` (§6.6 G2 fallback, 8 s `.default` alert) | `snippet` |
| `silentAlerts` | `true` → `.named("silent.caf")` · `false` → `.default` | `true` |
| `replayEnabled` | replay `fixtures/replay/<merchantId>_<totalCents>.json` when the request fails or times out (not on a 4xx) | `true` |
| `dateOverrideEnabled` + `dateOverride` | Settings › Demo › "Pretend today is…": the check's `clientDate` and the claim's `asOf` / incident date | off, `2027-12-18` |
