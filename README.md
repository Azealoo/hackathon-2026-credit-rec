# Paywise

*The perks buried in your card's fine print, at the moment you pay.*

Double-tap the back of your iPhone at checkout and Paywise tells you which of your cards covers this purchase if it breaks or gets stolen, and what that costs in cash back. It saves the purchase with its coverage dates. If the item later breaks or is stolen, it tells you whether you may be able to claim, cites the clause, and lists what to send.

DubHacks '26 (Oct 17–18) project: a native iOS 27 app with one App Intent, run by Back Tap (or, if you prefer, the Action Button), plus a small FastAPI backend that reads the cart. The full product spec is [SPEC.md](SPEC.md); §15 is the build plan.

## Status

State of `main` on Oct 16, 2026, 21:50 PDT (code at `4fcbf7e`, PR #26). [SPEC.md §15.7](SPEC.md) steps 0–14 are built except the `.transient` probe (step 7); os_signpost timing (step 6) is built but not yet read on a phone. Step 13 (Visa Acceptance) is built, but gate G4 fails, so the demo pays in mock mode. Step 15 (metrics) has its offline and live numbers, not the device ones.

| Part | State |
|---|---|
| Backend | Engine, `/v1/check` (with the public `offerContext` for promotional offers), `/v1/coverage` (+ HTML verdict), `/v1/store/pay`, rules and LLM parsers. `cd backend && uv run pytest -q`: 1,592 passed (Oct 16, 21:45). Scenarios 22/22 with 0 false switches and 0 protection drops; coverage 13/13. |
| Live | API **https://paywise-api-n0f9.onrender.com** (`/health`, `/v1/check`, `/v1/coverage`, `/v1/store/pay`, `/store/`), deployed from `main` with `PAY_MODE=visa_acceptance` (owner, Oct 16). G4 fails, so every order placed on the API's `/store/` fails until `PAY_MODE` is set back to `mock`. Demo store **https://paywise-store.onrender.com** (also from `main`) pays with its client-side mock, so it is unaffected. |
| iOS | App, Live Activity, OCR + redaction, Purchases, claim check, Back Tap setup with Try it now, the on-device `OfferResolver` and one-tap offer questions. Simulator: 289 unit tests in 52 suites passed (iPhone 18 Pro Max simulator, iOS 27.0, Oct 16, 21:55). The live UI tests and the screenshot tour weren't re-run for this update. iPhone: run on the owner's iPhone and a second iPhone on Oct 16 ([docs/spikes.md](docs/spikes.md#results-fill-in)). |
| Gates | **G1** (press chain): 5/5 Back Tap presses on the store counted so far; the gate needs ≥9/10 plus 2 real apps. In the assisted run each double tap made two checks. **G2** (snippet): 5/5 over Safari, button save 1/1 by hand; third-party app, island timeout and silent alert not run. **G3** (capture) not run. **G4 (Visa sandbox) fails on Cybersource's side**: the sandbox merchant's processor (`fdiglobal`) has no USD outlet or terminal IDs, so every authorization is a 502; the demo uses `PAY_MODE=mock` and makes no Visa-API claim (SPEC §11.2). **G5**: card values verified by an AI session in [docs/benefits-verification.md](docs/benefits-verification.md); the human review is still pending. Back Tap is the main trigger (owner, Oct 16); the Action Button is optional. |
| Metrics | [docs/metrics.md](docs/metrics.md): what is measured, and what still needs the phone or people. |

[docs/overnight-report.md](docs/overnight-report.md) and [docs/spikes.md](docs/spikes.md) are dated snapshots of the Oct 15–16 build; this table is the current state.

## Repo layout

| Path | What |
|---|---|
| `backend/` | FastAPI app (`app/`), its tests (`tests/`) and scripts (`scripts/`: parser eval, metrics, replay files, Visa smoke test) |
| `contracts/` | JSON Schema + example for each API body and on-device record (§15.5). `backend/app/models.py` mirrors them. |
| `data/cards.json` | The one card-data file: cards, earn rules, protections, merchants, item categories. Structure in `data/cards.schema.json`. |
| `fixtures/` | Demo wallets, scenarios and coverage cases (§15.4). All data obviously fake. |
| `demo-store/` | The fictional "Northbay Electronics" checkout pages (§9.3) |
| `docs/` | Spike and gate results (`spikes.md`), metrics (`metrics.md`), design, hosting, Visa sandbox, benefits verification; screenshots of every screen in `overnight-shots/` (300 JPGs; the tour's full-size PNGs are gitignored) |
| `ios/` | The app, its Live Activity extension, unit and UI tests, and the "Paywise" Shortcut (Xcode 27, iOS 27). How to build, test and install: [ios/README.md](ios/README.md) |

## Run the backend

Needs [uv](https://docs.astral.sh/uv/). It installs Python 3.12 and the dependencies on first run.

```bash
cd backend
uv run uvicorn app.main:app --reload
```

Then `curl localhost:8000/health` returns `{"ok":true,"commit":null,"modes":{…}}`: the deployed commit (on Render) and the parser, coverage and pay modes.

## Run the tests

```bash
cd backend
uv run pytest
```

`test_contracts.py` checks that every example in `contracts/` validates against its schema and `app/models.py`, and that every enum in §15.5 appears in a schema. `test_catalog.py` checks `data/cards.json` against its schema.

When you change a contract, change its schema, its example and the model in `app/models.py` together.

## Run the iOS tests

Needs a Mac with Xcode 27 and the iOS 27 simulator. From `ios/`:

```bash
# Unit tests (offline)
xcodebuild -project Paywise.xcodeproj -scheme Paywise -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath /tmp/paywise-dd -only-testing:PaywiseTests test

# Live UI tests against Render, then the screenshot tour (light, dark, XL, XXL → docs/overnight-shots/)
tools/run_ui_tour.sh          # or: tools/run_ui_tour.sh live / tools/run_ui_tour.sh tour
```

The UI tests need the network. Device build, install and the debug launch arguments are in [ios/README.md](ios/README.md); the Shortcut, Back Tap and Action Button steps are in [ios/Shortcut/README.md](ios/Shortcut/README.md).

## Metrics

```bash
cd backend
uv run python scripts/metrics.py                                               # offline
set -a && source ../.env && set +a && uv run python scripts/metrics.py --live  # + Render and the LLM evals
```

It prints aggregates only. Results: [docs/metrics.md](docs/metrics.md).

## Configuration

Copy `.env.example` to `.env` and fill in real values there. `.env` is gitignored; never commit it. `.env.example` also lists the optional keys and their defaults.

`DEMO_TEST_CARD_MAP` (needed for G4) holds processor test cards. It goes only in Render's environment and your local `.env`, never in the repo or chat.

## Team

- [@Azealoo](https://github.com/Azealoo)
- [@Carolzhxxx](https://github.com/Carolzhxxx)
- [@Michelle111213](https://github.com/Michelle111213)
- [@xiuyuan114514](https://github.com/xiuyuan114514)

## Workflow

- Branch off `main` for each feature: `git checkout -b feature/<short-name>`
- Open a pull request into `main` and ask a teammate to review
- Never commit secrets (API keys, `.env` files) or real card, account or personal data
