# US Online Shopping: Recommendation Algorithm for Existing Credit Cards

Version: research draft v1, October 16, 2026 (America/Los_Angeles). Audience: product and backend engineers. Scope: US consumer credit cards already held by the user, evaluated for a single online purchase. This is not a ranking of cards to apply for. Companion files: [issuer policy review](issuer-policy-review.en.md), [policy seed](card-policy-seed.json), and [acceptance vectors](acceptance-vectors.json).

**Decision framework: establish card and policy applicability, calculate the transaction's net rewards, then filter against the user's stated protection requirements. Present money and protection separately. Never treat a coverage limit as cash earnings.** This remains the full algorithm proposal. The opt-in implementation covers an initial subset described in [implementation status](implementation.md); the existing Paywise engine, SPEC, and runtime card catalog remain unchanged.

## 1. Evidence, product decisions, and user preferences

- **Issuer facts:** reward rates, spending-cap pools, activation requirements, and policy limitations. The companion policy review provides official sources, linked by source ID.
- **Research-supported direction:** a 2025 US PYMNTS survey identifies different strategies among people holding multiple cards: maximizing rewards, primarily using one card, and switching based on credit limits or balances. These percentages describe groups of consumers; they are not utility weights for an individual. [Study, Figure 3](https://www.pymnts.com/wp-content/uploads/2025/05/PYMNTS-How-Consumers-Decide-Which-Credit-Card-to-Pay-With-May-2025.pdf#page=11)
- **Product rules:** card-switch thresholds, data freshness thresholds, default modes, and item categories that merit attention. These are configurable decisions, not issuer policies or academic findings.
- **User preferences:** desired protections, maximum rewards the user is willing to give up, and expected repayment behavior. Obtain these from the user; do not infer them from age, income, or ethnicity.

Do not invent a composite score such as “40% cash back + 30% security + 20% convenience + 10% refunds.” Zero liability for unauthorized charges, damage coverage, return protection, and extended warranty are separate mechanisms.

## 2. Compatibility with existing Paywise behavior

Section 7.2 of [SPEC.md](../../SPEC.md) defines a deterministic, protection-first engine for five cards. It explicitly excludes spending caps, quarterly activation, foreign fees, and balance logic. This document describes an extension; the nine-card research dataset must not overwrite the legacy data file directly.

Suggested migration: retain the current behavior as `legacy_v1`; introduce the new rules under `policy_version=us-online-v2-draft` behind a feature flag. A shared protection type does not establish equivalent protection: compare eligible items, limits, duration, and exclusions. Use immutable, reviewed policy versions at runtime; an LLM must not rewrite rules during a recommendation.

## 3. Input contract

Use integer cents for money and integer basis points for rates; 100 bp = 1%. Use ISO 8601 dates. Model calendar quarters, calendar years, and billing cycles separately. Timestamps must carry a time zone; a policy-specified time zone takes precedence over the user's time zone.

```ts
type Truth = 'yes' | 'no' | 'unknown';
type Eligibility = 'eligible' | 'ineligible' | 'needs_info';
type Knowledge = 'verified_rule' | 'verified_summary' | 'unknown' | 'not_listed' | 'conflict';

interface Purchase {
  purchaseId: string; observedAt: string; expectedChargeAt: string | null;
  currency: string; totalMinor: number;
  merchantId: string | null; merchantCountry: string | null;
  acquirerCountry: string | null; mcc: string | null;
  issuerCategoryEvidence: Record<string, {category: string; source: string}>;
  channel: 'merchant_web' | 'merchant_app' | 'issuer_portal' | 'other';
  acceptedNetworks: string[] | null;
  paymentPaths: ('direct_card' | 'apple_pay' | 'paypal' | 'other')[];
  items: {id: string; eligibleValueMinor: number; condition: 'new'|'refurbished'|'used'|'unknown';
    category: string | null; manufacturerUsWarrantyMonths: number | null;
    otherWarrantyMonths: number | null; personalUse: Truth}[];
  amountsAllocatedToItems: Record<string, number> | null;
  foreignFeeAppliesByCard: Record<string, Truth>;
  extractionConfidence: {amount: number; merchant: number; items: number};
}

interface WalletCard {
  walletCardId: string; productId: string; network: string | null; networkTier: string | null;
  policyVariantId: string | null; active: Truth; availableCreditMinor: number | null;
  isDefault: boolean; openedAt: string | null;
  categorySelection: string | null; selectionEffectiveAt: string | null;
  activations: Record<string, Truth>;
  capUsage: Record<string, {postedMinor: number; pendingMinor: number | null;
    reservedMinor: number; periodStart: string; periodEnd: string; asOf: string}>;
  purchaseAprBps: number | null; purchaseGracePeriodActive: Truth;
  purchaseIntroApr: {aprBps: number; validThrough: string; verified: boolean} | null;
  expectedFullRepayment: Truth;
  membershipBonusBps: number | null; // For example, a 75% BofA rewards bonus = 7500; this is not the purchase reward rate.
  introOfferIds: string[]; activatedOfferIds: string[];
  repaymentPlan: unknown | null; // A computable repayment schedule is required when modeling financing costs.
}

interface Preferences {
  mode: 'cash_first' | 'protection_target';
  cashSacrificeBudgetMinor: number | null;
  protectionTargets: {itemId: string; benefitType: string;
    minNominalLimitMinor: number | null; minWindowDays: number | null;
    minExtensionMonths: number | null}[];
  allowLossOfExistingProtection: boolean; // Default: false.
  switchThresholdMinor: number; // See section 8 for example defaults; identify these as product rules.
}
```

Do not fabricate a missing amount, payment path, or applicable card version. An MCC can help determine rewards, but **cannot** substitute for item condition, manufacturer warranty, or excluded item categories. “Electronics” extracted from a screenshot is an item label; it does not establish the issuer's merchant reward category.

## 4. Policy data and applicability

The policy lookup key must include at least `issuer + product + network + networkTier + region + effective interval`. Record `observed_at` for pages without an effective date. A retrieval date is not a policy effective date; applicability to existing accounts still requires checking the account agreement.

Each rule carries `source_ids`, `knowledge`, `effective_from/effective_to`, applicable variants, and a review date. Source precedence is: the user's current account agreement and change notices > an applicable official benefits guide > official rewards terms > official product summaries. Do not resolve a conflict by automatically letting a newer webpage override an older account agreement. Return `policy_conflict`.

Seed matching semantics:

- `issuer_category` and `issuer_category_in` match evidence of the issuer's category classification.
- `issuer_category_equals_account_choice` requires both the account's selected category and its effective date.
- `issuer_category_in_current_quarter` requires a verified quarterly category snapshot.
- Multiple conditions in an object are AND conditions; candidate values in an array are OR alternatives.
- `requires` contains executable prerequisites, not explanatory notes. A rule cannot run when they are unmet.
- `enabled=false`, `automatic_activation=false`, and `automatic_item_eligibility_enabled=false` are mandatory gates. Until the complete benefit rule pack is available, its numerical values are display-only.
- An unknown foreign fee is null, not zero. Validate incoming money, cap usage, budget B, and thresholds as nonnegative integers. APR and credit-limit inputs must remain within contractually valid ranges. Reject NaN and Infinity.

Keep three dimensions separate:

1. `knowledge`: how completely the rule is known.
2. `card_eligibility`: whether this account/card variant has the benefit.
3. `item_eligibility`: whether this item and transaction satisfy the rule.

`not_listed` means the reviewed source did not list the benefit; it does not establish that the issuer formally discontinued it. `verified_summary` permits displaying that an official source lists a benefit, but does not permit automatically crediting it when material terms such as limits or exclusions are missing. The companion JSON is a research seed, **not a production policy bundle with complete eligibility evaluation**.

## 5. Hard filters and comparability

Apply these checks in order:

1. Consider only cards already in the wallet with `active=yes`. Put `active=unknown` cards in an unresolved group.
2. Mark a card unavailable if the merchant is known not to accept its network, it is locked, or its known available credit is insufficient. Unknown available credit is not sufficient credit; any ranking must be conditional on successful authorization.
3. Do not suggest additional spending, opening a new card, raising a credit limit, or using a cash advance as a workaround. Do not split the order by default.
4. Match rewards and benefits to the actual payment path. An ordinary merchant payment is not an issuer travel-portal payment.
5. Return a reward interval when a material reward input is unknown. Return `needs_info` when a material protection input is unknown.
6. Exact calculations initially cover USD eligible ordinary purchases with confirmed full repayment and an active purchase grace period. Route other cases through section 7; never silently set interest or foreign fees to zero.

Do not infer a product benefit from generic network marketing. A guide for Capital One cards on the Discover Network does not apply to every Discover it card or a Mastercard version of Savor.

## 6. Net reward calculation

Let `A` be the amount, in cents, that actually counts toward a reward rule. For one independent spending-cap pool:

```text
remaining = max(0, cap - postedUsage - knownPendingUsage - reservedUsage)
bonusSpend = min(A, remaining)
rawRewardMinor = bonusSpend * bonusRateBps / 10000
               + (A - bonusSpend) * baseRateBps / 10000
```

Do not add every matching reward rule. Use `exclusive_group` and priority to choose the applicable total reward rate. “3% total” does not mean a 1.5% base plus another 3%. Combine cap usage across the account, authorized users, and shared categories according to issuer terms.

Use Decimal or rational arithmetic. Sum unrounded reward components within the order, then round half-up to cents. This is a product estimation convention: set `estimated=true`. Issuer transaction or point rounding may differ slightly. The acceptance vectors use this convention.

### 6.1 Unknown cap usage and robust comparisons

- A verified uncapped base rate can produce a definite estimate. When cap availability is unknown, use the interval `[all spending at the base rate, all spending at the highest verified matching rate]`.
- Do not treat `activation=unknown` as activated. Show the unactivated lower bound and activated upper bound. Recalculate after the user confirms activation; do not activate an offer on the user's behalf.
- If merchant classification is unknown, enumerate scenarios supported by evidence. Do not use an LLM's self-reported confidence as a probability in an expected-value calculation.
- The difference between two reward intervals is `[candidate.low - baseline.high, candidate.high - baseline.low]`. Claim “estimated at least X more” only when the lower-bound improvement meets the switch threshold. Otherwise disclose the conditions or retain the default card.
- Do not add unverified introductory offers to an interval's upper bound unless a specific, potentially applicable official rule exists. An interval is not permission to assume that any promotion might apply.

### 6.2 Special reward structures

**Citi Double Cash:** separate the 1% earned on purchases from the 1% earned as the corresponding purchase balance is paid. The latter is a conditional receivable. Display an estimated eventual 2% only with confirmed repayment assumptions and continued eligibility under the terms; do not describe it as 2% credited at checkout. Use the official cash example of 100 points = $1 only for cash redemption, not other redemption methods. [CITI-DC]

**BofA Customized Cash Rewards:** the choice category and grocery/wholesale purchases share a $2,500 quarterly spending pool. Outside the first-year offer, membership bonus `b` applies to a verified ordinary rate: `3%*(1+75%)=5.25%`. Model the first-year additional 3 percentage points as a separate rule. Until stacking terms are verified, do not calculate `6%*1.75` or substitute a guessed rate. Authorized-user activity, pending transactions, and category-selection effective dates affect the shared pool. [BOFA-CCR, BOFA-TIER]

**Discover:** the 5% rate requires a matching quarterly category, effective dates, activation, and cap availability. Ordinary purchases earn 1%. Record first-year Cashback Match separately as a deferred reward; do not double rewards without confirmed account eligibility or count the same cash back twice. [DISC-IT, DISC-CAL]

**Card-linked offers:** include `offerCreditMinor` only after obtaining personalized terms and confirming activation, merchant, channel, amount, dates, remaining allowance, and stacking. Record a qualifying future statement credit separately; do not describe it as already posted. [WF-DEALS, CITI-DC]

**Welcome-bonus spending thresholds:** exclude these from this version's base recommendation. A later implementation must calculate the marginal reward attributable to the purchase, rather than adding the entire welcome bonus to every transaction. Do not recommend extra spending to meet a threshold.

### 6.3 Fees and annual fees

```text
netReward = baseAndCategoryReward + verifiedOfferCredit
          - incrementalForeignFee - incrementalCheckoutFee
          - incrementalFinancingCost
```

Do not deduct a previously incurred annual fee that this purchase does not change, or arbitrarily divide it by transaction count. Opening or renewing a card is a separate annual holding decision. Apply the contract's definition of foreign/cross-border transactions; a USD price on the webpage does not by itself establish a domestic US transaction. [WF-AC]

Estimating issuer currency conversion or merchant dynamic currency conversion (DCC) requires actual rate quotes. Without them, do not claim an optimal conversion method. Unverified fee fields in the seed must remain null.

## 7. Financing-cost gate

Set purchase interest to zero only when `expectedFullRepayment=yes && purchaseGracePeriodActive=yes`, or when a verified 0% **purchase** APR covers this transaction and its repayment period. A 0% balance-transfer offer does not establish a 0% purchase rate. Citi's page specifically states that its balance-transfer introductory offer does not apply to purchases. [CITI-DC]

Otherwise:

- If each card's APR, existing balance buckets, grace-period status, promotion expiry, and repayment schedule are available, simulate the contract's interest and payment-allocation rules. Compute `incrementalFinancingCost = interest(withPurchase) - interest(withoutPurchase)`, holding other transactions and payments constant. Do not attribute all interest on an existing balance to this purchase.
- If required data is missing, return `decision=needs_info, reason=financing_unknown`. You may show rewards before interest, but must not label the result “best net value” or encourage switching based on rewards alone.
- The shortcut `principal*APR*days/365` is permitted only as an educational illustration with explicit assumptions, not as the production best-card calculation. Compounding, payment allocation, and grace-period restoration rules can differ.

## 8. Protection calculation: eligibility versus nominal limits

Return the following for each item × benefit:

```ts
interface BenefitResult {
  knowledge: Knowledge; eligibility: Eligibility;
  benefitType: 'purchase_damage_theft'|'extended_warranty'|'return_protection'|'price_protection';
  nominalUpperBoundMinor: number | null; // Contractual upper bound only; not expected earnings or a payout guarantee.
  actualPayoutEstimateMinor: null; // Do not predict future incidents or claim outcomes at checkout.
  windowDays: number | null; extensionMonths: number | null;
  annualOrAccountLimitRemainingKnown: boolean;
  conditions: string[]; missingFields: string[]; sourceIds: string[];
}
```

Compute `nominalUpperBound = min(item covered value, amount attributable to that item paid by eligible means, item cap)`. Add repair/replacement cost, other insurance payments, deductibles, and exhausted account limits only when an incident occurs. A per-claim limit must not be copied onto every item: multiple items in a claim share that cap. Damage coverage and extended warranty generally cover different events; do not add their limits together.

At checkout, `eligible` means **the purchase conditions that can currently be determined have been verified**. Future merchant refusal, incident evidence, and claim deadlines must still appear in `conditions`. Return protection must never be described as a guaranteed refund.

Minimum facts for each benefit:

| Benefit | Required purchase facts | Limits on the conclusion |
|---|---|---|
| Damage/theft | Card variant, personal use, item condition and excluded categories, payment allocation, applicable region | Do not include ordinary defects, nondelivery, or loss unless the policy explicitly covers them. |
| Extended warranty | Original valid warranty territory and duration, store/purchased warranties, refurbished-item conditions, payment method | Distinguish mechanical failure from drops; do not automatically add a year when existing warranties exceed policy limits. |
| Return protection | Item category and condition, eligible US purchase, full-payment requirement | Merchant refusal, original condition, and timing remain claim conditions; categories such as formal wear may be excluded. |
| Price protection | Specific card variant, identical model, qualifying advertisement and dates | This is not a return or the merchant's ordinary price-adjustment policy. |

**Do not assign a zero score to an unverified benefit.** Missing terms should prevent an unsupported claim that a switch preserves all protections, not prevent displaying verified cash estimates. For unresolved Citi warranty terms or an unknown Capital One network, cash options may still be shown with an explicit statement that the protection comparison is incomplete.

### 8.1 Guard against losing existing protection

Default `allowLossOfExistingProtection=false`. Compare protections relevant to the current item: covered events, duration, nominal limits, eligible warranty length, payment requirements, and exclusions. A worse result on any verified dimension is `loss`; a material unknown or incomparable dimension is `unknown`.

Keeping the exact original card and payment path passes the guard because nothing changes; it does not establish that the existing protection has been verified. Changing the path on the same card still requires evaluation. If the default card is known to be unusable, do not require another card to preserve its protections for this transaction; explain that payment feasibility is driving the recommendation.

A candidate passes only if it is no worse on every relevant verified protection and material unknowns on both sides have been resolved. Added return protection does not automatically offset lost theft coverage. A higher limit but shorter duration is a tradeoff, not an unqualified upgrade. Show unknown baseline and candidate terms; do not describe unknown baseline protection as absent.

### 8.2 Recommendation modes

**Cash first (`cash_first`):** among candidates with computable fees/interest that pass the protection guard, select the highest net rewards. If every higher-reward option loses or may lose relevant protection, retain the default and show the cash alternative as a decision for the user.

**Protection target (`protection_target`):** the user specifies a requirement, such as at least 12 extra warranty months for a new laptop. First filter cards that meet every target. Then require `cashBest.netHigh - candidate.netLow <= B`, where B is the maximum rewards sacrifice the user accepts. Rank the remaining cards by net rewards. **If B is unset, do not automatically accept a positive rewards sacrifice.** Show the tradeoff, such as “$7.49 less in rewards for this protection,” for the user to choose. If no card meets the target, return `choice_required`; do not silently relax it.

Suggested product defaults: `mode=cash_first`, the protection-loss guard enabled, and B=null. To retain Paywise's existing protection-first behavior, explicitly select target mode. These defaults are not findings from a paper. The existing product's example switch thresholds—$3 for Apple Pay and $5 for other paths—may be reused as adjustable product constants.

Expensive electronics may trigger a suggestion to set a warranty target. “Prioritize electronics above $100” is a heuristic, not proof of eligibility. Do not rank cards solely by the number of benefit types or the sum of their limits.

## 9. Ranking and decision pseudocode

```python
def recommend(purchase, wallet, preferences, policy_snapshot):
    require_valid_amount_and_checkout(purchase)  # Otherwise return needs_info / not_checkout.
    options = enumerate_card_and_payment_path_options(wallet, purchase)
    evaluated = [evaluate_eligibility_rewards_fees_benefits(o) for o in options]
    # Return unresolved options to the UI; do not silently remove them from the wallet.
    ready = [o for o in evaluated if o.hard_eligibility == 'eligible']
    if not ready:
        return result('needs_info', reason='no_verified_usable_card', options=evaluated)
    if unresolved_financing_can_change_rank(ready):
        return result('needs_info', reason='financing_unknown', options=evaluated)

    # Use Pareto pruning only with complete information and comparable relevant dimensions.
    baseline = identify_exact_default_card_and_path(evaluated)
    candidates = remove_proven_dominated_options(ready, preserve=baseline)
    if (not preferences.allowLossOfExistingProtection and baseline is not None
            and baseline.hard_eligibility == 'eligible'):
        candidates = [o for o in candidates if protection_guard(o, baseline) == 'pass']
    if not candidates:
        return result('choice_required', reason='protection_tradeoff', options=evaluated)

    if preferences.mode == 'protection_target':
        targets = [o for o in candidates if meets_all_targets(o, preferences)]
        if not targets:
            return result('choice_required', reason='protection_target_unmet', options=evaluated)
        budget = preferences.cashSacrificeBudgetMinor or 0
        cash_best_high = max(o.net.high for o in ready)
        candidates = [o for o in targets if cash_best_high - o.net.low <= budget]
        if not candidates:
            return result('choice_required', reason='cash_sacrifice_budget_exceeded', options=evaluated)

    # Exact ties: original card and path, then fewer steps, then wallet order; never issuer commission.
    top = max(candidates, key=lambda o: (o.net.low, is_baseline(o, baseline), -o.steps, -o.wallet_order))
    # Confirm the top option only if its lower bound is at least every competing upper bound.
    if any(o.net.high > top.net.low for o in candidates if o.id != top.id):
        return result('needs_info', reason='ranking_uncertain', options=evaluated)

    if baseline is None or baseline.hard_eligibility == 'ineligible':
        return result('recommend', card=top, reason='best_verified_feasible_option')
    if baseline.hard_eligibility != 'eligible' or baseline.net is None:
        return result('choice_required', reason='baseline_unknown', options=evaluated)
    if top.id == baseline.id:
        return result('keep', card=top, reason='default_best')

    delta_low = top.net.low - baseline.net.high
    is_target_gain = (preferences.mode == 'protection_target'
                     and not meets_all_targets(baseline, preferences))
    if is_target_gain:
        return result('switch', card=top, reason='user_protection_target', cash_delta=delta_low)
    if delta_low >= preferences.switchThresholdMinor:
        return result('switch', card=top, reason='cash_gain', cash_delta=delta_low)
    return result('keep', card=baseline, reason='below_switch_threshold', alternative=top)
```

Pareto pruning must not remove the default merely because another option is slightly better: staying put has no switching cost. Keep the baseline as the comparison anchor. If a potentially ranking-changing option is unresolved, do not treat it as known unavailable. Return `ranking_scope=verified_options_only` or `needs_info`. Return filtering reasons alongside the recommended card ID.

## 10. Output contract and explanation templates

```json
{
  "policyVersion": "us-online-v2-draft",
  "decision": "switch",
  "reason": "user_protection_target",
  "recommendedCardId": "wallet-freedom",
  "recommendedPath": "direct_card",
  "rankingScope": "confirmed_wallet_options",
  "cash": {
    "estimateMinor": 2249,
    "bestCashAlternativeMinor": 2998,
    "sacrificeVsCashBestMinor": 749,
    "interestIncluded": true,
    "estimateIsBankSettlement": false
  },
  "protection": {
    "summary": "If the currently verified purchase conditions are met, adds one year of extended warranty and up to $500 per item in theft/damage coverage.",
    "payoutGuaranteed": false,
    "missingFields": [],
    "sources": [
      "CH-GTB"
    ]
  },
  "explanation": "Based on your extended-warranty target and your maximum $10 rewards sacrifice, use Freedom Unlimited. Estimated rewards are $7.49 lower than with Active Cash.",
  "sourceIds": [
    "CH-FU",
    "CH-GTB",
    "WF-AC",
    "WF-GTB"
  ],
  "assumptions": [
    "Full card payment and an active purchase grace period",
    "This example uses a new laptop for personal use with a 12-month US manufacturer warranty",
    "Only these two cards are compared"
  ]
}
```

This is an explanation example, not an actual account recommendation. Distinguish the difference versus the default card from the difference versus the highest-reward card. `interestIncluded=true` may represent verified interest-free treatment with a zero cost; do not use it when the grace-period status is unknown.

Suggested copy:

- Cash: “Estimated cash back: $6, or $1 more than your current card. Only $100 remains in the bonus spending allowance; the rest of this purchase earns 1%.”
- Protection: “This item may qualify for 90-day return protection, up to $300 per item. Full payment with this card and merchant refusal are required.”
- Missing information: “Citi lists extended warranty coverage, but the duration and limitations for your card have not been verified. This comparison covers cash rewards only.”

Do not use statements such as “security score: 95,” “guaranteed refund,” “$10,000 coverage means $10,020 net earnings,” or “Amex gets 10 extra points for good customer service.”

## 11. Worked examples and acceptance criteria

`acceptance-vectors.json` supplies assumptions and expected results for implementation. The amounts below use this specification's rounding convention:

| Scenario | Calculation | Required behavior |
|---|---|---|
| $1,499 new laptop; only Freedom Unlimited (FU) and Active Cash (AC) | FU at 1.5% = $22.49; AC at 2% = $29.98; difference = $7.49 | Automatically select FU only with verified interest-free treatment, a user-set warranty target, and a $10 sacrifice budget. Otherwise show the tradeoff. |
| BCE has $100 left in its annual online-retail pool; purchase is $300 | $100 × 3% + $200 × 1% = $5; AC = $6 | Do not estimate $9. A $1 improvement is below a $5 switch threshold, so do not interrupt to switch. |
| Ordinary existing BofA account has $100 left in the shared quarterly pool; online purchase is $300 | $100 × 3% + $200 × 1% = $5 | Include grocery/wholesale spending already consumed from the shared pool. |
| $200 new non-formal jacket; BCP versus AC | BCP = $2; AC = $4 | With verified purchase eligibility, a return-protection target, and a $3 budget, BCP may be selected. Do not guarantee a future refund. |
| $200 formal-wear item | BCP may have return protection as a product benefit | The policy excludes this category, so it does not meet the return-protection target. |
| Discover activation or quarterly category unknown; purchase is $100 | $1–$5 only when a verified, potentially applicable quarterly rule exists | Do not assert 5%. Without a quarterly snapshot, show the verified base rate and unresolved inputs. |
| $500 ordinary foreign purchase; Quicksilver (QS) versus AC | QS at 1.5% = $7.50; AC at 2% minus 3% = -$5 | With confirmed foreign-fee applicability and resolved protection tradeoffs, QS has $12.50 more in net rewards. |
| Capital One network unknown | Same product names have different benefits guides | Cash can be compared; do not apply the Discover Network guide automatically. |
| Repayment/grace-period status unknown | Do not set interest to zero | Return needs_info/financing_unknown. |
| Repeated request for the same transaction | Same result; no duplicate cap consumption | Use requestId and an idempotent cap-reservation key. |

Also cover: posting across quarters or years; cancellation and partial-refund reversals; authorized-user shared pools; multiple items sharing a per-claim cap; Chase's New York 90-day window; refurbished items with/without qualifying warranties; excessive original warranty duration; unactivated offers; multiple payment paths; conflicting or stale sources; an unavailable default; and a slightly higher-reward option that loses existing protection.

## 12. Implementation boundaries, updates, and release conditions

- Use the LLM only to extract merchants, items, and candidate terms. Deterministic code performs all amount, date, cap, and eligibility calculations. Every conclusion must trace to a rule ID and source ID.
- Store policy versions, actual effective intervals, and review status. Record the policy snapshot ID for every recommendation. Updating a policy must not rewrite historical purchase coverage.
- Track posted usage, known pending usage, and local reservations. Unknown pending amounts reduce certainty. Update reservations on purchase completion/cancellation; viewing a recommendation must not permanently consume a spending allowance.
- Suggested review cadence, as a product rule: verify quarterly rules before activation; review product summaries and promotions weekly; review benefits guides monthly and whenever a change notice arrives. Scheduling must be implemented separately; this document has not created a monitor.
- Minimize financial data: do not store PANs, CVVs, or login credentials. Use random card-instance IDs. Balances, limits, and preferences need timestamps and a user-controlled withdrawal mechanism.
- The seed supports basic reward logic. Before enabling automatic protection recommendations for a card, complete its executable eligibility/exclusion predicates for the applicable guide. Unresolved Citi terms, BofA benefits, Capital One variants, and Discover quarterly categories are specific data gaps, not assumed absences.

Before release, cross-check each automatically used field against its source. Missing account/variant applicability, policy validity, category/activation/cap state, required fees/financing data, or material protection terms must trigger a downgrade. Verified cash estimates can still be displayed while unrelated catalog gaps remain, provided the comparison scope is explicit.
