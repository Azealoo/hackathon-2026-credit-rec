# Paywise

*The perks buried in your card's fine print, at the moment you pay.*

Press one button at checkout and Paywise tells you which of your cards covers this purchase if it breaks or gets stolen, and what that costs in cash back. It saves the purchase with its coverage dates. If the item later breaks or is stolen, it tells you whether you may be able to claim, cites the clause, and lists what to send.

DubHacks '26 (Oct 17–18) project: a native iOS 27 app with one App Intent, run from the Action Button, plus a small FastAPI backend that reads the cart. The full product spec is [SPEC.md](SPEC.md); §15 is the build plan.

## Status

v1 build, [SPEC.md §15.7](SPEC.md) steps 0–1: repo skeleton, API contracts and a `data/cards.json` skeleton. The engine, demo store and iOS app aren't built yet. Every card value is `unverified` until the team checks it against the issuer's Guide to Benefits (gate G5).

## Repo layout

| Path | What |
|---|---|
| `backend/` | FastAPI app (`app/`) and its tests (`tests/`) |
| `contracts/` | JSON Schema + example for each API body and on-device record (§15.5). `backend/app/models.py` mirrors them. |
| `data/cards.json` | The one card-data file: cards, earn rules, protections, merchants, item categories. Structure in `data/cards.schema.json`. |
| `fixtures/` | Demo wallets, scenarios and coverage cases (§15.4). All data obviously fake. |
| `demo-store/` | The fictional "Northbay Electronics" checkout pages (§9.3) |
| `docs/` | Spike results and metrics |
| `ios/` | The app (needs a Mac with Xcode 27); not started |

## Run the backend

Needs [uv](https://docs.astral.sh/uv/). It installs Python 3.12 and the dependencies on first run.

```bash
cd backend
uv run uvicorn app.main:app --reload
```

Then `curl localhost:8000/health` returns `{"ok":true}`.

## Run the tests

```bash
cd backend
uv run pytest
```

`test_contracts.py` checks that every example in `contracts/` validates against its schema and `app/models.py`, and that every enum in §15.5 appears in a schema. `test_catalog.py` checks `data/cards.json` against its schema.

When you change a contract, change its schema, its example and the model in `app/models.py` together.

## Configuration

Copy `.env.example` to `.env` and fill in real values there. `.env` is gitignored; never commit it.

## Team

- [@Azealoo](https://github.com/Azealoo)
- [@Carolzhxxx](https://github.com/Carolzhxxx)
- [@Michelle111213](https://github.com/Michelle111213)
- [@wena04](https://github.com/wena04)
- [@xiuyuan114514](https://github.com/xiuyuan114514)

## Workflow

- Branch off `main` for each feature: `git checkout -b feature/<short-name>`
- Open a pull request into `main` and ask a teammate to review
- Never commit secrets (API keys, `.env` files) or real card, account or personal data
