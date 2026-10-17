# Metrics

SPEC §13 targets, §15.7 step 15. Aggregates only: no screenshots, OCR text or request bodies here.

> **Dated:** every number here is from the Oct 15 runs below, not re-run since. Current test counts: [README Status](../README.md#status).

**Runs:** Oct 15, 2026, commit `86dd685` (backend code as committed, plus the new `scripts/metrics.py`). Two `--live --rounds 5` runs at 18:50 and 18:53 PDT. Live numbers are from the build Mac (u: its network wasn't recorded).

**Render** ran `86dd685` (branch `overnight/v1`, since merged into `main` and deleted; auto-deploy on; Render API, 18:50). Its environment has `PARSER_MODE=llm`, `COVERAGE_MODE=llm`, `PAY_MODE=mock`, and no `DEMO_TEST_CARD_MAP`.

```bash
cd backend
uv run python scripts/metrics.py                                                          # offline
set -a && source ../.env && set +a && uv run python scripts/metrics.py --live --rounds 5  # + Render and the LLM evals
```

Raw output of the 18:53 run:

```
METRICS commit=86dd685 at=2026-10-15T18:53:14-07:00
SCENARIOS pass=22/22 false_switches=0 protection_drops=0 must_pass_5_21_22=yes
COVERAGE pass=13/13 not_covered_right=7/7 cites_section_and_date=13/13 cap500_cases_3_13=yes
CHECK_LOCAL runs=200 ok=200/200 p50_ms=0.64 p90_ms=0.87 max_ms=1.68 s1_copy=200/200 parser=rulesx200
LIVE_HEALTH runs=10 ok=10/10 p50_ms=91 p90_ms=147 max_ms=170 http=200x10 warmup_ms=99 warmup_http=200
LIVE_CHECK runs=10 ok=10/10 p50_ms=1197 p90_ms=1451 max_ms=1584 s1_copy=10/10 http=200x10 server_parse_p50_ms=1050 server_parse_p90_ms=1227 warmup_ms=1305 warmup_http=200
LLM_PARSER rounds=5 fixtures=fixtures/ocr/*.txt
MERCHANT=35/35 TOTAL=35/35 ITEMS=35/35 CONDITION=25/25 SCREEN=35/35 P50_MS=1129 P90_MS=1921
EXTRA PAYMENT=35/35 ITEMS_CONF_OK=20/20 ERRORS=0 CALLS=35 API_CALLS=36 MODEL=claude-haiku-5-5
LLM_CAUSES rounds=5 cases=fixtures/coverage_cases.json
CAUSE=65/65 P50_MS=998 P90_MS=1118 MODEL=claude-haiku-5-5
```

How it measures: p50 = median, p90 = nearest rank. Each live request opens a new connection, as a press after a pause would. The first live request is a warm-up: it's reported as `warmup_ms` and left out of p50/p90. `parser=` on `CHECK_LOCAL` counts the parser each request really used; the script stops before any request if `PARSER_MODE` isn't `rules`. Hedges = `API_CALLS − CALLS`.

## Measured

Same result in both runs unless two numbers are given (18:50 / 18:53).

| Metric (§13) | Target | Result | How |
|---|---|---|---|
| Correct pick | ≥20/22 | **22/22** ✓ | `fixtures/scenarios.json` through the engine |
| False switches | 0/22 | **0/22** ✓ | Same |
| Protection drops | 0; scenarios 5, 21, 22 pass | **0**; 5, 21, 22 pass ✓ | Same |
| Coverage verdicts | ≥12/13; every not_covered right; 13/13 cite section + version date; capped cases show the cap | **13/13**; not_covered **7/7**; cites **13/13**; cases 3 and 13 cap **$500** ✓ | `fixtures/coverage_cases.json` through `POST /v1/coverage` (rules) |
| Checkout read: merchant + total | ≥95% | **35/35** merchant, **35/35** total ✓ (7 OCR fixtures × 5 rounds; not the 30-screenshot set) | LLM parser (`claude-haiku-5-5`) on `fixtures/ocr/*.txt` |
| Items + condition | ≥85% | **35/35** items, **25/25** condition ✓ (same set) | Same |
| Privacy | Backend rejects ≥12-digit runs; no card numbers or real-app files in the repo | ✓ `pytest` green (1312 passed, 18:50), including `test_privacy`, `test_privacy_guard` and the `/v1/check` privacy tests | `cd backend && uv run pytest -q` |

Other numbers:

| What | Target | Result |
|---|---|---|
| `/v1/check` S1, local (TestClient, rules parser), 200 runs | p50 <50 ms (§15.7 step 4) | p50 **0.57 / 0.64 ms**, p90 0.62 / 0.87 ms; exact S1 copy 200/200; parser `rules` 200/200 ✓ |
| `/v1/check` S1, live on Render, Mac → Render, 10 runs | none set; feeds press → result | p50 **1331 / 1197 ms**, p90 1572 / 1451 ms; exact S1 copy 10/10 |
| Server-side parse time on Render (`timingMs.parse`) | — | p50 1234 / 1050 ms, p90 1471 / 1227 ms (Render uses the LLM parser) |
| `/health`, live, 10 runs | — | p50 104 / 91 ms, p90 196 / 147 ms |
| LLM parser latency (direct, from the Mac) | p50 ≤1500 ms, p90 ≤3000 ms (`scripts/eval_parser.py`) | **Borderline.** p50 1095–1704 ms over 4 runs, under target in 3 of them; p90 1848–2012 ms, under target in all 4. See below |
| LLM cause classification | — | **65/65** right (13 cases × 5); p50 1015 / 998 ms, p90 1163 / 1118 ms |

LLM parser and live check across runs (ms):

| Run (PDT) | Rounds | Parser p50 / p90 | Hedges | LIVE_CHECK p50 / p90 | Source |
|---|---|---|---|---|---|
| 18:28 | 3 | 1095 / 1848 | 0 | 1121 / 1204 | (u) an earlier run; its output was on this page, I didn't see it run |
| 18:40 | 3 | **1704** / 2012 | 3 | 1471 / — | (u) a reviewer's run; I saw only these numbers |
| 18:50 | 5 | 1268 / 1879 | 0 | 1331 / 1572 | this run |
| 18:53 | 5 | 1129 / 1921 | 1 | 1197 / 1451 | this run (raw output above) |

## Simulator run (18:02)

iPhone 18 Pro simulator, iOS 27.0, full `xcodebuild test` started 18:02 (not re-run for this page). The log is in a temporary session folder that will be deleted (`/private/tmp/claude-501/-Users-user-credit-rec--claude-worktrees-ios-s0-1cea9d/d1761ea0-563f-42f4-9d26-8509521f523d/scratchpad/fulltest-1802.log`, result bundle in `scratchpad/dd-full`), so its summary lines are copied here:

```
✔ Test readsAndRedacts(_:) with 7 test cases passed after 2.933 seconds.
PAYWISE_OCR_TIMING cold=442 ms p50=443 ms p90=527 ms max=620 ms n=21
✔ Test run with 159 tests in 29 suites passed after 18.025 seconds.
PAYWISE_UI testCheckAScreenshotLive: Switch copy on screen 4.17 s after the pick
	 Executed 4 tests, with 0 failures (0 unexpected) in 377.782 (377.789) seconds
** TEST SUCCEEDED **
```

| What | Target | Result |
|---|---|---|
| On-device read of the 7 demo screenshots: merchant and total kept, nothing identifying left | 7/7 (§15.7 step 8) | 7/7 ✓ (`readsAndRedacts`) |
| OCR + redaction time | p50 ≤400 ms **on the phone** | p50 443 ms, p90 527 ms, n = 21 on the Mac's simulator: not the phone |
| "Check a screenshot" → Switch copy on screen, live backend | ≤6 s (overnight brief) | 4.17 s, n = 1 |

## Not measured yet

| Metric (§13) | Target | Needs | Owner |
|---|---|---|---|
| Press → *Checking* | p50 ≤1.0 s | iPhone, 20 presses. The `intent-to-checking` signpost times the app's part (`docs/spikes.md` › Timing a press); press → intent start needs a video (step 1) | A |
| Press → result | p50 ≤3.5 s, p90 ≤5 s on venue Wi-Fi or a hotspot | Same. The live `/v1/check` above (p50 1.1–1.5 s) is only the network + server part | A |
| Chain reliability | ≥19/20 presses capture the right screen and show a result | iPhone (G1) | C |
| Snippet save | ≥9/10 taps create a planned Purchase and reload to Saved | iPhone (G2). The simulator only shows two racing saves make one purchase | C |
| Replay robustness | Hits after ≥2 min, at another battery %, with another Live Activity | iPhone (`docs/spikes.md` step 5) | A |
| OCR time on the phone | p50 ≤400 ms | iPhone (`docs/spikes.md` step 4) | A |
| Checkout read and items on 30 screenshots | ≥95% / ≥85% | The accuracy set: 10 demo-store images (7 exist) + 20 real-app images kept outside the repo, and a harness for them | A |
| False switches on real screenshots | ≤1/30 | Same set | A |
| 3-second comprehension | ≥8/10 name the card; ≥6/10 a reason; ≤2/10 misread the cost line | 10 non-teammates, Sat 8–9 PM | D |
| Stranger trigger | ≥9/10 first presses start a check | Same session | D |
| Right card used | ≥9/10 | Same session | D |
| Time to "am I covered + what do I send?" | ≤60 s vs a manual baseline | Stopwatch, 3 non-teammates | D |
| Unaided setup | ≥4/5 finish in ≤2:00; first result ≤60 s | Stopwatch, 5 non-teammates | D |
| Demo reliability | 10 clean runs of the full arc | Rehearsal log | All |
| Demand and awareness | Counts per card family (n = 10–12) | Interviews; aggregates only | D |
| Privacy on the phone | 0 screenshots, last 4 or card numbers in any request | What we sent review on the iPhone (the simulator's `PrivacyGuardTests` pass) | A, B |
