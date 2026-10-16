# Handoff: Run the On-Device Parser Test on Your iPhone

**Who:** a teammate whose iPhone was bought in the US. **Time:** about 20 minutes, of which the run itself should take 3–5 minutes **(u)**. **Branch:** `experiment/on-device-parser`.

## Why we need you

We want to know whether Apple's on-device model can read a checkout screen as well as Claude Haiku does on our server. If it can, the phone could send only a structured cart, and screen text would never leave it.

Claude Haiku and the rules parser are already tested ([results](on-device-parser-test.md)). Apple's model couldn't be tested, because Yining's iPhone and Mac are mainland-China models (model numbers ending in CH/A), and Apple turns Apple Intelligence off on those. The test is built and ready; it only needs an eligible phone.

## Check your phone first

- iPhone 15 Pro or later, on iOS 27.
- Settings › General › About › Model Number does **not** end in CH/A. Tap the number once if it shows a code that starts with A.
- Settings has an **Apple Intelligence & Siri** page, Apple Intelligence is turned on, and it has finished downloading.
- Your iPhone's language and Siri's language are the same supported language, for example English (US).

If any of these fail, stop: the test will only report that the model is unavailable.

## Run it (on Yining's Mac)

Paywise is signed with Yining's individual Apple Developer account, which can't add team members. The simplest path is to plug your phone into Yining's Mac. Building on your own Mac would need your own team ID and different bundle IDs, and nobody has tried that yet **(u)**.

1. On your iPhone, turn on Settings › Privacy & Security › Developer Mode, then restart the phone and confirm.
2. Plug the phone into Yining's Mac by USB, tap **Trust**, and keep the phone unlocked.
3. On the Mac, in the repo on branch `experiment/on-device-parser`, find your phone's identifier (the UDID column):

```bash
xcrun devicectl list devices
```

4. Build and install. The first build registers your phone with the account automatically:

```bash
xcodebuild -project ios/Paywise.xcodeproj -scheme Paywise -configuration Debug -destination 'id=<UDID>' -derivedDataPath /tmp/paywise-dd -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
```

```bash
xcrun devicectl device install app --device <UDID> /tmp/paywise-dd/Build/Products/Debug-iphoneos/Paywise.app
```

5. Run the test: 15 fake checkout screens × 3 rounds. Leave the phone unlocked with Paywise on screen. The app keeps the screen awake and quits when it's done.

```bash
xcrun devicectl device process launch --device <UDID> --terminate-existing --console -- com.azealoo.paywise -parserLab -parserLabRounds 3 | sed -n 's/^PARSERLAB //p' > docs/parser-lab/ondevice-raw.jsonl
```

6. Check that the first line says `"availability":"available"`. If it says `unavailable(...)`, your phone isn't eligible; send us that line and stop.

```bash
head -2 docs/parser-lab/ondevice-raw.jsonl
```

7. Score the run the same way Claude was scored:

```bash
cd backend && uv run python scripts/compare_parsers.py raw ../docs/parser-lab/ondevice-raw.jsonl --show-misses --json-out ../docs/parser-lab/ondevice.json
```

## What to send back

1. Fill in the "Apple on-device model" column in [on-device-parser-test.md](on-device-parser-test.md) from the `ONDEVICE SET=all` line:
   - SCREEN → Screen type, MERCHANT → Store, TOTAL → Total, ITEMS → Items, CONDITION → Condition, PAYMENT → Payment options.
   - P50_MS / P90_MS → Speed.
2. Add one line each for:
   - the `instruction_tokens` count;
   - the first call's time (the record with `"cold":true`);
   - any `error` values, such as `rateLimited`, a context-size error or a guardrail error.
3. Commit `docs/parser-lab/ondevice-raw.jsonl`, `docs/parser-lab/ondevice.json` and the updated doc, then push to this PR's branch.
4. Remove the test build of Paywise from your phone afterwards if you like (long-press the icon › Remove App).

## Good to know

- **Same test for every model.** Every reader gets the same 15 fake screens (`fixtures/ocr`, `fixtures/ocr-hard`) and the same prompt (`ios/Paywise/Debug/parser_prompt.txt`, exported from `parser_llm.system_prompt()`). Each output goes through the same `parser_llm.build()` and scoring, so the model is the only thing that differs.
- **Nothing leaves your phone.** All of the screen text is fake, and the run makes no network calls.
- **Not covered:** Paywise's real check runs inside a background App Intent, where Apple may rate-limit the model. This test runs in the foreground, so background speed and rate limits remain unknown **(u)**.
