# Apple's On-Device Model Can't Run on Our Devices, So Claude Haiku Stays

Test date 2026-10-16, on branch `experiment/on-device-parser` (from `overnight/v1` 191e28a). Unconfirmed items are marked **(u)**.

## Bottom line

- **We couldn't test Apple's model at all.** Our iPhone 16 Pro Max (iOS 27.0.1) and our M5 Mac both report `deviceNotEligible`, and the phone has no "Apple Intelligence & Siri" menu.
- **The cause is where the devices were sold.** Both are mainland-China models: the iPhone's model number is MYTP3CH/A (checked in Settings › General › About through iPhone Mirroring) and the Mac's is Z1KN00029CH/A (`system_profiler`). Apple says Apple Intelligence "will not currently work for supported devices purchased in China mainland" ([Apple 121115](https://support.apple.com/en-us/121115), Sep 14, 2026). Changing the region or language settings doesn't help: the phone is already set to region US and English (US).
- **Claude Haiku is accurate and fast enough.** On 15 fake screens × 3 rounds it made no errors and got every item and total right. Median time is 1.4 s.
- **Recommendation:** keep Claude Haiku on the server. To test Apple's model, a teammate with an iPhone 15 Pro or later bought outside mainland China, with Apple Intelligence turned on, runs the ready-made test (see the end of this doc).

## Side by side

Every reader got the same 15 fake screens: 7 demo-store screens plus 8 harder ones written for this test before any parser ran on them. Each model got the same prompt and schema, and its output went through the same Python post-processing and scoring, so the model is the only difference.

| | Claude Haiku 5.5 (server, today) | Apple on-device model | Rules parser (no AI) |
|---|---|---|---|
| Screen type | 45/45 | not run | 15/15 |
| Store | 42/45 ¹ | not run | 15/15 |
| Total | 45/45 | not run | 15/15 |
| Items (name, price, category) | **45/45** | not run | 12/15 ² |
| Condition | 35/36 | not run | 8/12 |
| Payment options | 41/45 | not run | 14/15 |
| Speed | p50 1.4 s, p90 2.1 s (Mac → API) | ~4–5 s estimated **(u)** ³ | under 1 ms |
| Cost per check | paid per call (small, not measured) | free ([Apple, as reposted](https://matthewcassinelli.com/apples-foundation-models-framework-unlocks-new-app-experiences-powered-by-apple-intelligence)) | free |
| Where the screen text goes | our server, then Anthropic (kept up to 30 days) | stays on the phone | our server |
| Works for | everyone with a connection | only Apple Intelligence devices, turned on, in a supported region and language | everyone |
| Runs on our demo phone | yes | **no** | yes |

1. All 3 store misses are the DoorDash screen. Haiku named the restaurant ("Spice Route Kitchen") instead of DoorDash. My label is arguable.
2. The rules parser misread multi-line Amazon items, Best Buy's offered protection plan, and DoorDash's line totals. It was written against the 7 demo screens and scores 7/7 on them.
3. Apple's published iPhone 15 Pro figures (about 0.6 ms per prompt token, 30 tokens/s output) put a cart at 4–5 s. That estimate is from the other session; I didn't measure it.

## What this means

- **Apple's model can't replace Haiku.** Not every user can run it, so the server path is needed anyway. At most it could be an extra "keep on device" mode.
- **We can't demo it.** Our demo phone can't run it.
- **Haiku's real weak spot is the store when an app sells for someone else**, as with DoorDash showing a restaurant name. That's a prompt fix, not a model change.
- **The cheaper privacy fix still stands:** make the Redactor an allow-list.

## Next: run it on an eligible iPhone

A teammate with a US-bought iPhone runs the test by following [on-device-parser-handoff.md](on-device-parser-handoff.md), then fills in the "Apple on-device model" column above. Raw results so far are in `docs/parser-lab/llm.json` and `docs/parser-lab/rules.json`.
