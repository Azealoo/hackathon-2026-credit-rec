# Apple's On-Device Model Is Slower and Less Accurate Than Claude Haiku, So Haiku Stays

Test date 2026-10-16, on branch `experiment/on-device-parser` (from `overnight/v1` 191e28a). Apple's model ran on "Carol", an iPhone 16 Pro Max (Canadian model MYWH3VC/A, iOS 27.0.1), with the Debug build from 0ec43ae. Unconfirmed items are marked **(u)**.

## Bottom line

- **Apple's model runs, but it's worse than Haiku at reading a cart.** It got the items right on 30/45 screens, against Haiku's 45/45, and the payment options on 9/45, against 41/45. It also called an unreadable screen and a product page "checkout", which would make Paywise recommend a card where there's no purchase.
- **It's too slow.** On the phone it takes 7.5 s at the median and 8.7 s at p90. Our budget is 6.0 s, and Haiku takes 1.4 s / 2.1 s.
- **It never failed while it stayed in the foreground**: 0 errors in 45 calls.
- **Recommendation:** keep Claude Haiku on the server. Apple's model isn't a drop-in replacement with this prompt.

## Side by side

Every reader got the same 15 fake screens: 7 demo-store screens plus 8 harder ones written for this test before any parser ran on them. Each model got the same prompt and schema, and its output went through the same Python post-processing and scoring, so the model is the only difference.

| | Claude Haiku 5.5 (server, today) | Apple on-device model | Rules parser (no AI) |
|---|---|---|---|
| Screen type | 45/45 | 39/45 | 15/15 |
| Store | 42/45 ¹ | 39/45 ¹ | 15/15 |
| Total | 45/45 | 42/45 | 15/15 |
| Items (name, price, category) | **45/45** | 30/45 | 12/15 ² |
| Condition | 35/36 | 33/36 | 8/12 |
| Payment options | 41/45 | 9/45 | 14/15 |
| Speed | p50 1.4 s, p90 2.1 s (Mac → API) | p50 7.5 s, p90 8.7 s (on the phone) | under 1 ms |
| Cost per check | paid per call (small, not measured) | free ([Apple, as reposted](https://matthewcassinelli.com/apples-foundation-models-framework-unlocks-new-app-experiences-powered-by-apple-intelligence)) | free |
| Where the screen text goes | our server, then Anthropic (kept up to 30 days) | stays on the phone | our server |
| Works for | everyone with a connection | only Apple Intelligence devices, turned on, in a supported region and language | everyone |
| Runs on our phones | yes | Carol only, not the CH/A phone | yes |

1. Both models missed the DoorDash store in all 3 rounds: they named the restaurant ("Spice Route Kitchen") instead of DoorDash. My label is arguable.
2. The rules parser misread multi-line Amazon items, Best Buy's offered protection plan, and DoorDash's line totals. It was written against the 7 demo screens and scores 7/7 on them.

## Apple's run in detail

- **Same answer every round.** Decoding is greedy, so all 3 rounds gave identical output. The 45 calls are really 15 answers, each counted 3 times.
- **Speed:**
  - Cold first call: 7.8 s, about the same as a warm call.
  - Median per round: 6.8 s, 7.5 s, then 7.8 s, so it got slower as the phone warmed up **(u: thermal)**.
  - Range: 4.2 s to 8.9 s.
  - The feasibility estimate was 4–5 s.
- **Tokens:**
  - The prompt's instructions use 1,151 tokens.
  - Each call reads about 2,060 tokens and writes about 200 (89–273), half of the 4,096-token window in the harness notes **(u)**.
  - No prompt caching was reported (`cachedTokenCount: 0`).
- **Errors:** none in the full run. In an earlier, aborted run, Carol locked mid-run. The next 2 calls failed inside Apple's safety filter (`ModelManagerError 1013`), and iOS then killed the app. This suggests the model refuses work once the app leaves the foreground **(u)**, which matters for the background Back Tap check (untested here).
- **What Apple's model got wrong** (each screen ×3):

| Screen | Apple's mistake | Haiku on the same screen |
|---|---|---|
| 5 checkouts (earbuds, laptop, renewed laptop, mug, Amazon) | Listed Apple Pay, which isn't on the screen | right |
| `blurry-unreadable` | Called it a checkout, with a saved card | right |
| `bestbuy-product-page` | Called it a checkout, with a cart, total and BNPL | right |
| `bestbuy-tv-plan-offer` | Added the *offered* protection plan as a bought item | items right; 1 payment miss |
| `nike-order-confirmation` | Running shoes as "appliances"; listed payment options on a confirmation | right |
| `laptop-confirmation` | Listed payment options on a confirmation | right |
| `earbuds-checkout` | Shortened the item name ("Wireless Earbuds") | right |
| `walmart-gift-card-blender` | Items in a different order (the check is order-sensitive); added a card form | 1 payment miss |
| `target-card-form-applepay` | Said a saved card was selected; the screen shows a card form | right |
| `unknown-store-open-box-bike` | Missed the BNPL and card-form options; said a saved card was selected | right |
| `doordash-line-totals` | Restaurant name as the store | same miss |

Only `feed-not-checkout` was fully right.

## Setup notes

- **The first phone can't run it.** Our first iPhone and Mac are mainland-China models (MYTP3CH/A, Z1KN00029CH/A) and report `deviceNotEligible`. Apple says Apple Intelligence "will not currently work for supported devices purchased in China mainland" ([Apple 121115](https://support.apple.com/en-us/121115)).
- **Carol needed fixes before the model downloaded.**
  - At first it reported `modelNotReady`, with Region set to China mainland.
  - After the region was changed to US, it stayed `modelNotReady` for 30 minutes, until a reboot.
  - Just after the reboot, Apple's download service unpacked about 1 GB. That this download was the model is unconfirmed **(u)**.
  - The model reported available at 15:58, 36 minutes after the reboot. It may have been ready sooner: from 15:31, another session's Paywise build without the harness was on Carol, so those checks never ran.
- **Not covered:** background speed and rate limits. This test runs in the foreground.

Raw results: `docs/parser-lab/ondevice-raw.jsonl` (Apple), `ondevice.json`, `llm.json` and `rules.json` (scored). The run steps are in [on-device-parser-handoff.md](on-device-parser-handoff.md).
