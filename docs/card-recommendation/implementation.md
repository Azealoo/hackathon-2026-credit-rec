# Recommendation v2 implementation

`POST /v2/recommend` implements the initial cash-estimation and ranking layer of [the proposed algorithm](algorithm-spec.en.md). It accepts structured purchase/account facts, not screenshots. It is disabled unless `RECOMMENDATION_V2_ENABLED=1`. The existing `/v1/check` route, runtime card catalog, and iOS flow continue to use the existing engine.

The versioned [research seed](card-policy-seed.json) is the single source for v2 issuer rates and benefit summaries. The v2 loader validates supported rule semantics and source references, rejects enabled unfinished benefit packs, and identifies its cached snapshot with a SHA-256 digest. Changing the seed requires review, updated contract examples, and a backend restart. This is an experimental endpoint, not a completed production policy service.

## Supported calculations

| Area | Implemented behavior |
|---|---|
| Scope | USD ordinary eligible purchases on merchant websites/apps. Each option identifies a card instance and payment path. Network acceptance, activity, payment-path eligibility, and available credit are checked. |
| Account applicability | Requires explicit confirmation of account/path policy applicability through the purchase date. Public pages alone do not establish it. |
| Rewards | Source-backed total rates within the ordinary reward group; no addition of overlapping base/category rates. Unknown category evidence produces conservative bounds. |
| Spending caps | Splits spend across bonus/base rates, with account-wide posted, pending, and reserved usage. `rewardPeriodDate` must confirm the issuer's posting/period assignment; it is not assumed to equal the charge date. Period dates must match its calendar year/quarter; the usage snapshot must be dated on the charge date and account scope confirmed. Unknown pending usage lowers certainty. Recommendation reads do not consume a cap. |
| BofA | Shared quarterly cap and verified ordinary membership multipliers. Unknown membership status creates a range. A confirmed first-year additive offer blocks automatic ranking pending supported offer/stacking rules. |
| Citi | Separates the purchase reward and conditional payment reward. The latter becomes definite only with confirmed full repayment and eligible payment/Purchase Tracker treatment. Net amounts include it as an eventual estimate, never as posted cash. |
| Fees | Deducts confirmed foreign and checkout fees. Unknown material fees prevent net ranking. A USD purchase is not assumed domestic. Previously incurred annual fees are excluded. |
| Interest | Zero only with full repayment plus active purchase grace period, or a verified zero purchase APR covering the charge and planned complete repayment. Other cases return `needs_info`; no approximate APR shortcut is used. |
| Rounding | Decimal arithmetic, summed before half-up cent rounding for net estimates. Individual displayed components may not sum to the rounded net by one cent. |
| Ranking | Cash-first or user-specified protection targets; robust interval comparisons; user sacrifice budget; configurable switch threshold; default/path tie preference. Potentially relevant unresolved options prevent an unsupported global winner. |
| Protections | Product knowledge states and source references are displayed. All seed item eligibility remains `needs_info`. The internal ranker can compare complete profiles supplied by a future reviewed evaluator; the HTTP contract does not accept eligibility/profile overrides. |
| Privacy | Existing body privacy rejection and per-client rate limits apply. Validation errors report field locations without echoing values; responses use `Cache-Control: no-store`. No account or recommendation data is persisted by this endpoint. |

Money inputs must be nonnegative integer cents; strings, Booleans, fractions, NaN, and Infinity are rejected. `membershipBonusBps` is a confirmed account multiplier, such as 7500 for a 75% bonus, not a purchase reward rate. Unknown inputs must remain null/`unknown`, rather than being replaced by zero.

The caller must obtain current, authorized account facts and issuer category/payment-path evidence. Confirmation fields are assertions about those facts, not evidence collected or verified by this service. The existing OCR result cannot automatically populate these confirmations. Separate card IDs can represent different accounts of the same product; multiple paths for the same card must agree on shared account facts.

## Protection behavior

By default, `allowLossOfExistingProtection=false`. Keeping the exact default card/path changes no protection; switching requires an adequate comparison. Since the seed has no complete item exclusion evaluators, an otherwise higher-cash card normally produces `choice_required` with its cash estimates. Unknown baseline benefits are not treated as absent.

Explicitly setting `allowLossOfExistingProtection=true` permits a cash comparison despite unresolved protection tradeoffs. This preference must come from the user; the app must not turn it on merely to obtain a recommendation. `protection_target` mode still requires verified target eligibility, so this flag cannot activate an unreviewed insurance benefit.

The internal scenario tests use independently confirmed protection profiles specified in the research vectors to exercise sacrifice budgets and dominance checks. Those profiles are test assumptions and cannot be submitted through the endpoint. Numerical coverage ceilings are not expected payouts or guaranteed refunds.

## Run and inspect locally

From `backend/`:

```bash
RECOMMENDATION_V2_ENABLED=1 uv run uvicorn app.main:app --reload
```

In a second terminal, also from `backend/`:

```bash
curl --fail-with-body http://localhost:8000/v2/recommend \
  -H 'Content-Type: application/json' \
  --data-binary @../contracts/v2/recommend.request.example.json
```

The [synthetic request](../../contracts/v2/recommend.request.example.json) explicitly allows protection tradeoffs and compares a $500 foreign transaction on Active Cash and Quicksilver. The [response](../../contracts/v2/recommend.response.example.json) selects Quicksilver with $12.50 more estimated net rewards. Setting that preference back to false returns `choice_required`, because the seed cannot establish equivalent item protection.

The [request schema](../../contracts/v2/recommend.request.schema.json) and [response schema](../../contracts/v2/recommend.response.schema.json) describe the implemented subset. They are generated from `app/recommendation_v2/models.py`; tests check schema/model equality and example validation. The larger interfaces in the research specification remain design targets.

## Deferred work

- Complete per-item benefit predicates, account/network/tier applicability, state overrides, payment allocation, exclusion checks, and shared per-claim limits before enabling automatic protection recommendations. Formal-wear exclusions and New York benefit windows in the research vectors are not yet executable item assessments.
- Review and publish an applicable Discover quarterly policy before enabling its 5% rule. The seed's disabled rule cannot be activated with client input; the API displays the 1% base estimate and returns `needs_info` for ranking.
- Implement verified personalized offers, first-year rate offers and stacking, deferred Cashback Match, issuer portals, and non-USD conversion. `rankingScope=supported_ordinary_rewards_only` explicitly excludes these from the current comparison. Known applicable BofA additive offers block ranking instead of being silently stacked or omitted.
- Implement account-specific financing simulation and payment allocation for cases without verified zero-interest treatment.
- Add durable, atomic cap reservations with purchase identity, account sharing, cancellation/refund handling, and idempotent state transitions. The current endpoint is read-only and does not claim to implement the reservation vector.
- Add the structured-input UI/account integration and user preference controls before connecting v2 to the app's checkout flow. No production deployment or UI switch is part of this implementation.

Run `uv run pytest tests/test_recommendation_v2.py` for calculation, uncertainty, internal ranking, contract, and API coverage, and `uv run pytest` for the backend regression suite. The twenty research vectors remain the broader acceptance target; not all have executable production eligibility/state-management paths yet.

Validation on October 16, 2026: `python -m pytest -q` in a temporary Python 3.12 environment with the backend dependencies passed all 1,533 tests, including 61 v2 tests. Existing scenario checks passed 22/22 with zero false switches and zero protection drops; coverage scenarios passed 13/13. These results do not validate unresolved issuer eligibility policies or an iOS integration.
