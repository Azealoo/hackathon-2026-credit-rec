# Spikes and gates

SPEC §14.2 (gates), §15.7 steps 6–7. State on **Oct 15, 2026, 18:35 PDT**, commit `86dd685` (corrected 18:55).

- **Simulator:** iPhone 18 Pro, iOS 27.0, Xcode 27.0. Evidence: the 18:02 full run (`xcodebuild test`: 159 unit tests in 29 suites + 4 UI tests, `TEST SUCCEEDED`; all 4 UI tests ran against live Render) and the screenshots in `docs/overnight-shots/`.
  - The run's log is in a temporary session folder (`/private/tmp/claude-501/…/scratchpad/fulltest-1802.log`) that will be deleted. Its summary lines are copied in [metrics.md](metrics.md#simulator-run-1802).
  - `docs/overnight-shots/` is local only: not in git yet (339 files, 169 MB). Screenshot paths below work only on the build Mac until it is committed. `ios/tools/run_ui_tour.sh tour` remakes the `light-*` and `dark-*` folders, per its header (u: not re-run; where `live-activity/`, `verdict-web/` and `brand/` come from wasn't checked).
- **iPhone:** Paywise is installed (not yet opened). Nothing below has run on the phone yet.
- **(u)** = not checked this run; where I looked is named next to it.

## Gates

| Gate | Pass rule (§14.2) | Seen on the simulator | Still open (iPhone) | State |
|---|---|---|---|---|
| **G1** chain | ≥9/10 Action Button presses capture the right screen and show the island (store in Safari + 2 real apps) | `CheckCheckoutIntent.perform()` with real Vision OCR on the laptop screenshot → Switch (`RealReaderIntentTests`). In-app check against Render: Switch copy 4.17 s after the pick. *Checking* island: `live-activity/01–02`. | The whole press chain: Action Button → Shortcut → Take Screenshot → intent. Which screen gets captured. Back Tap. | Open |
| **G2** surface | Snippet appears ≥9/10 (Safari + ≥1 third-party app); [Paying with …] saves and reloads ≥9/10; island empty 5 min after Done; silent alert expands with no sound | Snippet states render in the app (`*/50–57-gallery-*`). Two racing saves make one purchase (`testSaveIsIdempotent`). Island fallback (`islandModeShowsSwitchFallback`, `live-activity/07–08`). `silent.caf` is silent PCM in both bundles (`AssetTests`). | All four checks. The system snippet only exists after a real press. | Open |
| **G3** capture | Wired QuickTime or AirPlay shows the island and the snippet | Nothing (the simulator can't show this) | Everything | Open |
| **G4** Visa | Sandbox returns an approved transaction ID | Code and tests done (`test_store_pay.py`). Mock mode works live (18:35: `/v1/store/pay` → approved, `processor: mock`). The sandbox accepts our signed request: `scripts/visa_smoke.py` at 18:36 → auth probe HTTP 400 `MISSING_FIELD` card number, so the keys and signature work (a wrong secret gave 401 earlier tonight (u: build log)). Only an approval with a card proves G4. | Nothing on the phone | **Blocked:** the owner must set `DEMO_TEST_CARD_MAP` on Render |
| **G5** data | Demo-card protections checked against the Guides to Benefits | `docs/benefits-verification.md` (Oct 14): all four G5 answers verified; the S1 copy holds | A human review by B or D | Data done; review pending |

## Spikes

| Spike | What (§14.2) | Seen on the simulator | Still open (iPhone) |
|---|---|---|---|
| **S0** | Project, signing, widget extension, App Group | Builds and tests green. The Live Activity renders, which needs the signed extension. | Nothing. A device build and install worked at 18:20 (u: from the build log). |
| **S1** | Press → Shortcut → intent → island → result; os_signpost per link | Intent, OCR and live backend (see G1) | The press chain, and its timings. os_signpost per link is built (`CheckTrace`, see [Timing a press](#timing-a-press-os_signpost)) but not yet read on the phone. The part before the app runs (press → Shortcut → Take Screenshot → intent start) still needs the video. |
| **S2** | Snippet Patterns A and B, button + reload, silent sound, `.transient` probe, island 5 min after Done, Shortcuts indicator during the 4 s Keep hold | Patterns A and B and the island fallback are built. Settings › Results switches them without a rebuild (`light-default/41-settings.png`). Pattern B without a card name falls back to a static snippet (`confirmWithoutCardNameShowsStaticSnippet`). | Every Y/N item. **The `.transient` probe isn't built** (grep of `ios/`). |
| **S3** | Capture rig | Nothing | Same as G3 |
| **S6** | Setup in ≤2:00 + Share Sheet branch | Steps in `ios/Shortcut/README.md`. Signed `ios/Shortcut/Paywise.shortcut` (u: signing from the build log). Setup screens `*/07–09`, `*/45`. | Stopwatch. Share Sheet branch. Whether the signed file imports. |

## Other device-only items

| Item | Target | Simulator | iPhone |
|---|---|---|---|
| OCR + redaction time | p50 ≤400 ms (§15.7 step 8) | p50 443 ms, p90 527 ms, n = 21 (Mac CPU; `readTimeP50`, 18:02 run) | Open |
| `silent.caf` | No sound; the island still expands | Silent PCM in both bundles | Open (G2) |
| Stale island | The bare glyph, nothing else (§6.4) | `StaleRenderTests` renders every island part and the Lock Screen with `isStale = true` for 4 states: the glyph only, no text, art or last 4 (`live-activity/stale-rendered.png`). `-demoActivity stale` (23:19): ActivityKit reports `stale` 1 s after the past-staleDate update. The redrawn island itself wasn't seen (simctl screenshots omit the island) | Open |
| Replay robustness | Still hits after ≥2 min, at another battery %, and with another Live Activity running (§15.7 step 10) | `replayHitAfterFailure` (replay after a failure) and `replayOffMeansCouldntCheck` (replay off → *Couldn't check*) in `CheckCheckoutIntentTests`; both passed in the 18:02 run | Open |

## Timing a press (os_signpost)

SPEC §15.7 step 6 asks for os_signpost per link. Built in `ios/Paywise/Check/CheckTrace.swift` (Oct 15, 23:20): subsystem `com.azealoo.paywise`, category `check`, one interval per link per check, each with its own signpost ID. When an interval ends, one `.info` line logs `<name> <ms> ms (<source>)`. Only names and durations are logged: no OCR text, amounts, cards or stores. The source is `intent` for a press, `in-app` for "Check a screenshot".

| Interval | From → to |
|---|---|
| `intent-to-checking` | `CheckCheckoutIntent.perform()` starts → *Checking* requested from ActivityKit |
| `read` | Crop + OCR + checkout gate + redaction, then the request body's on-device privacy check |
| `post` | `POST /v1/check` (6.0 s timeout), including the replay lookup after a failure |
| `record` | `CheckRecord` built and written to the App Group |
| `result` | The flow's answer → the snippet or confirmation handed to the system, or the island alert sent |
| `press-to-result` | `perform()` starts → the end of `result`. Doesn't include the 4 s / 8 s island hold after it |

"Press" here means the intent's start. The Action Button press, the Shortcut and Take Screenshot run before the app does anything (§9 budget: 0.5–1.0 s), so only the video shows them. Press → *Checking* on the video minus `intent-to-checking` ≈ the time before the intent starts. A link that doesn't run has no interval: no checkout means no `post` and no `record`. With no screenshot (*Not set up*), `intent-to-checking` ends as "abandoned" and logs no duration.

**On the simulator** (checked 23:17 on Paywise Dev 18 during the unit suite: 20 intent runs that got as far as the POST logged all six links, and no line had OCR text, a store, a card or an amount):

```bash
xcrun simctl spawn <udid> log stream --info --signpost --style compact \
  --predicate 'subsystem == "com.azealoo.paywise" AND category == "check"'
```

```
… Sp Paywise[…] [com.azealoo.paywise:check] [spid 0x3f2, process, begin] press-to-result: intent
… Sp Paywise[…] [com.azealoo.paywise:check] [spid 0x3f2, process,   end] intent-to-checking
… I  Paywise[…] [com.azealoo.paywise:check] intent-to-checking 0 ms (intent)
… I  Paywise[…] [com.azealoo.paywise:check] read 1 ms (intent)
… I  Paywise[…] [com.azealoo.paywise:check] post 6 ms (intent)
… I  Paywise[…] [com.azealoo.paywise:check] press-to-result 9 ms (intent)
```

(Unit-test numbers with a stub server and a fixture reader, so they're only an example of the format.) Without `--info` the duration lines are hidden; without `--signpost` the intervals are.

**On the iPhone** (u: neither route has been run on the phone yet). `log stream` on the Mac reads only the Mac's own log, so use one of these:
- **Instruments:** open Xcode › Open Developer Tool › Instruments, pick the iPhone and **All Processes** (the intent runs in Paywise launched in the background), and use the **os_signpost** instrument (in the Logging template, or add it to a Blank one). Record, do the presses, stop, then filter to subsystem `com.azealoo.paywise`. Each interval shows its duration (u: template and menu names not checked on Instruments 27).
- **Console.app:** pick the iPhone in the sidebar, turn on Action › Include Info Messages, search `subsystem:com.azealoo.paywise category:check`, and press. The `.info` lines carry the durations (u: menu names not checked on macOS 27).

## Morning test on the iPhone (about 30 min)

**Before you start:** unlock the phone, open Paywise once and tap **Use demo wallet**. Ringer on, volume up. In Paywise › Settings › Results: **Snippet with a Paying with button**, **Silent island alerts** on, **Replay when offline** on. Fill in the table at the end as you go.

### 0. Shortcut and Action Button (S6), ≈2 min

Follow `ios/Shortcut/README.md` sections A–C with a stopwatch: AirDrop `Paywise.shortcut` (or build it by hand), bind **Settings › Action Button › Shortcut › Paywise**, do the practice press, answer **Always Allow**. Write down the time (target ≤2:00) and whether the signed file imported.

### 1. G1 chain and timing, ≈10 min

1. Film the phone with a second phone (Slo-mo or 60 fps) so your finger and the screen are both in shot. A screen recording can't show the press.
2. In Safari open https://paywise-store.onrender.com/checkout.html?item=laptop.
3. Press the Action Button 10 times. After each press wait for the answer, then tap **Done**.
4. Count presses where the island showed *Checking* and the answer was **Use Freedom ••1234**.
5. Open Paywise › Settings › **What we sent**. Each check shows the text that was read; it must be the store's checkout, not Shortcuts or Paywise.
6. Do 5 presses on each of 2 real apps' cart or checkout screens (look only; don't buy). Count presses that showed *Checking* and an answer about that screen. Never save those screenshots in the repo.
7. Back Tap: **Settings › Accessibility › Touch › Back Tap › Double Tap › Paywise**. Do 10 double taps on the store page and count.
8. From the video, for each press note the time from the press to *Checking* and to the answer. Targets: press → *Checking* p50 ≤1.0 s; press → answer p50 ≤3.5 s, p90 ≤5 s. Record the signposts during the presses too ([Timing a press](#timing-a-press-os_signpost)): they split each time into the app's links, and the rest is press → intent start.

Fail (<9/10) → report it with What we sent as evidence; try a Wait before Take Screenshot; fall back to the in-app check. Not the iOS 27 screenshot automation in SPEC §6.6 G1 step 1: the owner ruled it out on Oct 16 (it saves checkout screenshots to Photos and runs on every screenshot).

### 2. G2 surface (S2), ≈10 min

1. **Appearance:** 10 presses on the store laptop page. Count snippets. Then at least one press over a third-party app showing the same page, for example Chrome or Firefox if installed (u: not checked which browsers are on the phone).
2. **Button:** on each snippet tap **Paying with Freedom**. It should reload to "✓ Saved: Aero 14 · $1,499 …". Count. Once, double-tap it fast. Then Paywise › Purchases should have one planned row per snippet you tapped, and only one for the double tap. Delete the rows afterwards.
3. **5 min after Done:** after one answer tap **Done**, wait 5 minutes, and check that the island is empty.
4. **Sound:** open https://paywise-store.onrender.com/checkout.html?item=mug and press. Expect a *Keep* island alert that expands with **no sound**. Note whether the Shortcuts running indicator shows during the 4 s hold. Turn **Silent island alerts** off and press again: expect the normal alert sound.
5. `.transient` probe: not built, so write "not built".

Fails (§6.6): no snippet → pick **Island alert, held 8 s**. The button doesn't save → pick **System confirm prompt** (Pattern B) and redo step 2. A sound with Silent on → leave **Silent island alerts** off (`.default` everywhere).

### 3. G3 capture (S3), ≈3 min

1. Cable the phone to the Mac. In QuickTime Player choose **File › New Movie Recording**, then pick the iPhone in the menu next to the record button. Press on the store page: are the island and the snippet visible in the window?
2. AirPlay: **Control Center › Screen Mirroring** to the Mac (the Mac needs **AirPlay Receiver** on in System Settings) (u: menu names not checked on macOS 27). Same check.

Fail → film with an external camera and add an overlay (§14.2).

### 4. OCR time on the phone, ≈3 min

The `read` signpost from step 1 times crop + OCR + gate + redaction inside the background intent on the phone ([Timing a press](#timing-a-press-os_signpost)); write down its p50. As a cross-check, run the timing test on the phone (unlocked, on the cable). This reinstalls the same Debug build:

```bash
cd ios
xcodebuild -project Paywise.xcodeproj -scheme Paywise -destination 'id=00008140-001858591EE0801C' -derivedDataPath /tmp/paywise-dd-device -allowProvisioningUpdates -only-testing:PaywiseTests/ScreenshotReadingTests test 2>&1 | grep PAYWISE_OCR_TIMING
```

Target p50 ≤400 ms. (u: never run on the phone. It times OCR in the test host, not inside the background intent.)

### 5. Replay robustness, ≈6 min

1. Online, press once on the store laptop page.
2. Turn on Airplane Mode, wait 2 minutes, press again. Expect the Switch answer labeled "replayed" within 7 s.
3. Start a Clock timer, so another Live Activity is in the island. Press again: replayed?
4. Later in the morning, at a different battery %, press again in Airplane Mode: replayed?
5. Turn **Replay when offline** off and press: expect *Couldn't check* within 7 s. Turn replay and the network back on.

### G4: owner only, ≈3 min

1. Take a **Visa** number from Cybersource's published test-card list (`docs/visa-sandbox.md` §5).
2. Render › paywise-api › Environment: add `DEMO_TEST_CARD_MAP` (shape in `.env.example`) and set `PAY_MODE=visa_acceptance`. Saving redeploys (about 1 min).
3. Open https://paywise-api-n0f9.onrender.com/store/checkout.html?item=laptop, tap **Change**, pick **Visa ••1234** and place the order. The confirmation page should show a transaction ID. Or, with the same map in your local `.env`, run `cd backend && uv run python scripts/visa_smoke.py`: it exits 0 only on an approval.

### G5: B or D, ≈15 min

Read `docs/benefits-verification.md` §1 and open each cited URL to check the quotes. Then note the review there.

## Results (fill in)

| Item | Target | Result | When |
|---|---|---|---|
| S6 setup time | ≤2:00 | | |
| Signed Shortcut file imports | Y | | |
| G1 store presses | ≥9/10 | | |
| G1 real app 1 / app 2 | ≥9/10 overall | | |
| Back Tap | tally | | |
| Press → *Checking* p50 | ≤1.0 s | | |
| Press → answer p50 / p90 | ≤3.5 s / ≤5 s | | |
| G2 snippet appears (Safari) | ≥9/10 | | |
| G2 snippet appears (third-party app) | ≥1 | | |
| G2 button saves + reloads | ≥9/10 | | |
| Double tap → one purchase | Y | | |
| Island empty 5 min after Done | Y | | |
| Silent alert: no sound, expands | Y | | |
| Shortcuts indicator during the Keep hold | Y/N | | |
| `.transient` probe | — | not built | |
| G3 wired QuickTime / AirPlay | Y | | |
| OCR p50 on the phone | ≤400 ms | | |
| Replay after 2 min / other battery % / other Live Activity | Y / Y / Y | | |
| G4 approved transaction ID | Y | | |
| G5 human review | done | | |
