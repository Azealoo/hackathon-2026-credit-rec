"""Deterministic estimates and conservative ranking; never evaluates insurance with an LLM.

Reviewed protection profiles are internal evaluator outputs, not client input. The research
seed cannot produce a complete profile until executable issuer exclusion packs exist.
"""

from calendar import monthrange
from dataclasses import dataclass, field
from datetime import date
from decimal import Decimal, ROUND_HALF_UP

from .models import (BenefitSummary, CardOption, Interval, OptionEstimate, Preferences,
                     Purchase, RecommendRequest, RecommendResponse, Selection, Source)
from .policy import Snapshot

D = Decimal


def cents(value: Decimal) -> int:
    return int(value.quantize(D(1), rounding=ROUND_HALF_UP))


def reward_raw(amount: int, base_bps: Decimal, bonus_bps: Decimal,
               remaining: int) -> Decimal:
    bonus_spend = min(amount, max(0, remaining))
    return (D(bonus_spend) * bonus_bps + D(amount - bonus_spend) * base_bps) / D(10000)


def difference(candidate: Interval, baseline: Interval) -> Interval:
    return Interval(low_minor=candidate.low_minor - baseline.high_minor,
                    high_minor=candidate.high_minor - baseline.low_minor)


@dataclass(frozen=True)
class Coverage:
    benefit_type: str
    nominal_limit_minor: int
    window_days: int = 0
    extension_months: int = 0
    # Equal only after an evaluator establishes equal relevant event/item/payment scope.
    comparability_key: str = ""


@dataclass(frozen=True)
class ProtectionProfile:
    complete: bool = False
    coverages: tuple[Coverage, ...] = ()


@dataclass
class Evaluated:
    estimate: OptionEstimate
    is_default: bool
    profile: ProtectionProfile = field(default_factory=ProtectionProfile)

    @property
    def key(self):
        return self.estimate.wallet_card_id, self.estimate.payment_path


def protection_guard(candidate: Evaluated, baseline: Evaluated) -> str:
    if candidate.key == baseline.key:
        return "pass"
    if not candidate.profile.complete or not baseline.profile.complete:
        return "unknown"
    unknown = False
    for old in baseline.profile.coverages:
        same_type = [new for new in candidate.profile.coverages if new.benefit_type == old.benefit_type]
        if not same_type:
            return "loss"
        comparable = [new for new in same_type if old.comparability_key
                      and new.comparability_key == old.comparability_key]
        if not comparable:
            unknown = True
            continue
        if not any(new.nominal_limit_minor >= old.nominal_limit_minor
                   and new.window_days >= old.window_days
                   and new.extension_months >= old.extension_months for new in comparable):
            return "loss"
    return "unknown" if unknown else "pass"


def meets_targets(option: Evaluated, prefs: Preferences) -> bool:
    return option.profile.complete and all(
        any(c.benefit_type == t.benefit_type and c.nominal_limit_minor >= t.min_nominal_limit_minor
            and c.window_days >= t.min_window_days and c.extension_months >= t.min_extension_months
            for c in option.profile.coverages) for t in prefs.protection_targets)


def period_bounds(day: date, kind: str) -> tuple[date, date]:
    if kind == "calendar_year":
        return date(day.year, 1, 1), date(day.year, 12, 31)
    first = ((day.month - 1) // 3) * 3 + 1
    last = first + 2
    return date(day.year, first, 1), date(day.year, last, monthrange(day.year, last)[1])


def cap_remaining(card: CardOption, pool: dict, day: date) -> tuple[int, int, list[str]]:
    usage = card.cap_usage.get(pool["id"])
    cap = pool["spend_cap_minor"]
    missing = ["cap_usage:" + pool["id"]]
    period_day = card.reward_period_date
    if (period_day is None or period_day < day):
        return 0, cap, ["reward_period_date"]
    if (usage is None or not usage.account_scope_confirmed or usage.as_of != day
            or (usage.period_start, usage.period_end) != period_bounds(period_day, pool["period"])):
        return 0, cap, missing
    maximum = max(0, cap - usage.posted_minor - usage.reserved_minor)
    if usage.pending_minor is None:
        return 0, maximum, ["pending_usage:" + pool["id"]]
    remaining = max(0, maximum - usage.pending_minor)
    return remaining, remaining, []


def category_match(rule: dict, card: CardOption, day: date) -> str:
    match = rule["match"]
    states = []
    if match.get("eligible_purchase"):
        states.append(card.issuer_eligible_purchase)
    has_category = card.issuer_category is not None and card.category_confirmed_through is not None
    has_category = has_category and card.category_confirmed_through >= day
    if "issuer_category" in match:
        states.append(("yes" if card.issuer_category == match["issuer_category"] else "no")
                      if has_category else "unknown")
    if "issuer_category_in" in match:
        states.append(("yes" if card.issuer_category in match["issuer_category_in"] else "no")
                      if has_category else "unknown")
    if match.get("issuer_category_equals_account_choice"):
        selected = (card.category_selection is not None and card.selection_effective_at is not None
                    and card.selection_effective_at <= day)
        states.append(("yes" if card.issuer_category == card.category_selection else "no")
                      if has_category and selected else "unknown")
    if "no" in states:
        return "no"
    return "unknown" if "unknown" in states else "yes"


def zero_interest(card: CardOption, day: date) -> bool:
    if card.expected_full_repayment == "yes" and card.purchase_grace_period_active == "yes":
        return True
    promo = card.purchase_intro_apr
    return bool(promo and promo.verified and promo.apr_bps == 0
                and promo.valid_from <= day <= promo.repayment_complete_by <= promo.valid_through)


def evaluate(card: CardOption, purchase: Purchase, policy: dict) -> Evaluated:
    day, amount = purchase.charge_date, purchase.total_minor
    out = OptionEstimate(wallet_card_id=card.wallet_card_id, product_id=card.product_id,
                         payment_path=card.payment_path, availability="eligible")
    result = Evaluated(out, card.is_default)
    if not set(card.confirmed_intro_offer_ids) <= {o["id"] for o in policy.get("intro_offers", [])}:
        raise ValueError("unknown account offer")
    out.benefits = [BenefitSummary(benefit_type=b["type"], knowledge=b["knowledge"],
                                  source_ids=b["source_ids"]) for b in policy["benefits"]]
    out.notes.append("benefit_summaries_are_display_only")
    out.notes.append("excludes_welcome_bonuses_personalized_offers_deferred_matches_and_portals")

    unavailable, unresolved = [], []
    for name, truth in (("active", card.active), ("path_eligible", card.path_eligible),
                        ("issuer_eligible_purchase", card.issuer_eligible_purchase)):
        if truth == "no":
            unavailable.append(name)
        elif truth == "unknown":
            unresolved.append(name)
    if purchase.accepted_networks is None or card.network is None:
        unresolved.append("network_acceptance")
    elif card.network not in purchase.accepted_networks:
        unavailable.append("network_not_accepted")
    if card.available_credit_minor is None:
        unresolved.append("available_credit")
    elif card.available_credit_minor < amount:
        unavailable.append("insufficient_credit")
    if unavailable:
        out.availability = "ineligible"
        out.notes.extend(unavailable)
        return result
    if unresolved:
        out.availability = "needs_info"
        out.missing_fields.extend(unresolved)
    if card.policy_confirmed_through is None or card.policy_confirmed_through < day:
        out.missing_fields.append("account_policy_applicability")
        return result
    if card.issuer_eligible_purchase != "yes" or card.path_eligible != "yes":
        return result
    for key in ("effective_from", "effective_to"):
        boundary = policy.get(key)
        if boundary and ((key == "effective_from" and day < date.fromisoformat(boundary))
                         or (key == "effective_to" and day > date.fromisoformat(boundary))):
            out.missing_fields.append("policy_effective_interval")
            return result

    def valid_now(rule):
        starts = [rule[k] for k in ("valid_from", "effective_from") if rule.get(k)]
        ends = [rule[k] for k in ("valid_to", "effective_to") if rule.get(k)]
        return (all(day >= date.fromisoformat(start) for start in starts)
                and all(day <= date.fromisoformat(end) for end in ends))

    rules = [r for r in policy["reward_rules"] if r.get("enabled", True) and valid_now(r)]
    if not any(r["match"] == {"eligible_purchase": True} for r in rules):
        out.missing_fields.append("policy_effective_interval")
        return result
    base = next(r for r in rules if r["match"] == {"eligible_purchase": True})
    multiplier_low = multiplier_high = D(1)
    membership = policy.get("membership_bonus")
    if membership:
        bonus = card.membership_bonus_bps
        if bonus is None:
            out.missing_fields.append("membership_bonus")
            multiplier_high += D(max(membership["allowed_bonus_bps"])) / D(10000)
        elif bonus not in membership["allowed_bonus_bps"]:
            raise ValueError("unsupported membership bonus")
        else:
            multiplier_low = multiplier_high = D(1) + D(bonus) / D(10000)
        out.source_ids.extend(membership["source_ids"])
    base_rate = D(base["rate_bps"])
    low = D(amount) * base_rate * multiplier_low / D(10000)
    high = D(amount) * base_rate * multiplier_high / D(10000)
    pools = {p["id"]: p for p in policy["cap_pools"]}
    for rule in rules:
        state = category_match(rule, card, day)
        if state == "no":
            continue
        remaining_low = remaining_high = amount
        if rule.get("cap_pool_id"):
            remaining_low, remaining_high, missing = cap_remaining(card, pools[rule["cap_pool_id"]], day)
            out.missing_fields.extend(missing)
        rule_low = reward_raw(amount, base_rate, D(rule["rate_bps"]), remaining_low) * multiplier_low
        rule_high = reward_raw(amount, base_rate, D(rule["rate_bps"]), remaining_high) * multiplier_high
        if state == "yes":
            low = max(low, rule_low)
        else:
            out.missing_fields.append("issuer_category_or_selection")
        high = max(high, rule_high)
        out.rule_ids.append(rule["id"])
        out.source_ids.extend(rule["source_ids"])
    out.reward = Interval(low_minor=cents(low), high_minor=cents(high))

    payment_low = payment_high = D(0)
    for conditional in policy.get("conditional_rewards", []):
        payment_high += D(amount) * D(conditional["rate_bps"]) / D(10000)
        if card.eligible_payment_and_tracker_confirmed == "yes" and card.expected_full_repayment == "yes":
            payment_low = payment_high
        elif card.eligible_payment_and_tracker_confirmed == "no":
            payment_high = D(0)
        else:
            out.missing_fields.append("eligible_payment_and_purchase_tracker")
        out.rule_ids.append(conditional["id"])
        out.source_ids.extend(conditional["source_ids"])
        out.notes.append("payment_reward_is_conditional_and_not_credited_at_checkout")
    out.conditional_payment_reward = Interval(low_minor=cents(payment_low), high_minor=cents(payment_high))

    blockers = []
    for offer in policy.get("intro_offers", []):
        if offer["id"] in card.confirmed_intro_offer_ids and offer["kind"] == "additive_rate_bps":
            blockers.append("offer_stacking_unknown" if card.membership_bonus_bps else "intro_offer_not_supported")
    if any(not r.get("enabled", True) for r in policy["reward_rules"]):
        # A disabled quarter cannot be enabled by client assertions. Base rewards remain displayable.
        blockers.append("quarter_category_unknown")
    if not zero_interest(card, day):
        blockers.append("financing_unknown")
    fee = policy["foreign_fee_bps"]
    fee_raw = D(0)
    if card.foreign_fee_applies != "no":
        if fee["value"] is None or fee["knowledge"] not in ("verified_rule", "verified_summary"):
            blockers.append("foreign_fee_unknown")
        elif fee["value"] == 0:
            out.source_ids.extend(fee["source_ids"])
        elif card.foreign_fee_applies == "unknown":
            blockers.append("foreign_fee_unknown")
        else:
            fee_raw = D(amount) * D(fee["value"]) / D(10000)
            out.source_ids.extend(fee["source_ids"])
    if card.checkout_fee_minor is None:
        blockers.append("checkout_fee_unknown")
    if not blockers:
        fees = fee_raw + D(card.checkout_fee_minor)
        out.net = Interval(low_minor=cents(low + payment_low - fees), high_minor=cents(high + payment_high - fees))
    out.missing_fields = sorted(set(out.missing_fields + blockers))
    out.source_ids = sorted(set(out.source_ids))
    out.rule_ids = sorted(set(out.rule_ids))
    return result


def select(options: list[Evaluated], prefs: Preferences) -> tuple[str, str, Evaluated | None, Interval | None]:
    """Rank evaluated options. Does not know issuer names or reward rates."""
    ready = [o for o in options if o.estimate.availability == "eligible" and o.estimate.net is not None]
    unresolved = [o for o in options if o.estimate.availability != "ineligible" and o not in ready]
    if unresolved:
        missing = {f for o in unresolved for f in o.estimate.missing_fields}
        reason = next((r for r in ("financing_unknown", "offer_stacking_unknown", "quarter_category_unknown",
                                   "foreign_fee_unknown", "account_policy_applicability") if r in missing),
                      "unresolved_option")
        return "needs_info", reason, None, None
    if not ready:
        return "needs_info", "no_verified_usable_card", None, None
    baseline = next(o for o in options if o.is_default)
    baseline_usable = baseline in ready
    allowed = ready
    if not prefs.allow_loss_of_existing_protection and baseline_usable:
        allowed = [o for o in ready if protection_guard(o, baseline) == "pass"]
    if prefs.mode == "protection_target":
        targets = [o for o in allowed if meets_targets(o, prefs)]
        if not targets:
            reason = "protection_target_unverified" if any(not o.profile.complete for o in ready) else "protection_target_unmet"
            return "choice_required", reason, None, None
        cash_best_high = max(o.estimate.net.high_minor for o in ready)
        allowed = [o for o in targets if cash_best_high - o.estimate.net.low_minor <= (prefs.cash_sacrifice_budget_minor or 0)]
        if not allowed:
            return "choice_required", "cash_sacrifice_budget_exceeded", None, None
    top = max(allowed, key=lambda o: (o.estimate.net.low_minor, o.is_default, -options.index(o)))
    if prefs.mode == "cash_first" and any(o.estimate.net.high_minor > top.estimate.net.low_minor for o in ready if o not in allowed):
        return "choice_required", "protection_comparison_incomplete_or_loss", None, None
    if any(o.estimate.net.high_minor > top.estimate.net.low_minor for o in allowed if o is not top):
        return "needs_info", "ranking_uncertain", None, None
    if not baseline_usable:
        return "recommend", "best_verified_feasible_option", top, None
    if top is baseline:
        return "keep", "default_best", top, None
    delta = difference(top.estimate.net, baseline.estimate.net)
    if prefs.mode == "protection_target" and not meets_targets(baseline, prefs):
        return "switch", "user_protection_target", top, delta
    if delta.low_minor >= prefs.switch_threshold_minor:
        return "switch", "cash_gain", top, delta
    return "keep", "below_switch_threshold", baseline, None


def recommend(request: RecommendRequest, snapshot: Snapshot) -> RecommendResponse:
    options = [evaluate(o, request.purchase, snapshot.card(o.product_id)) for o in request.options]
    decision, reason, selected, delta = select(options, request.preferences)
    estimates = [o.estimate for o in options]
    used = {sid for o in estimates for sid in o.source_ids}
    used.update(sid for o in estimates for b in o.benefits for sid in b.source_ids)
    return RecommendResponse(request_id=request.request_id, policy_version=snapshot.version,
                             policy_snapshot_id=snapshot.snapshot_id, decision=decision, reason=reason,
                             selected=Selection(wallet_card_id=selected.key[0], payment_path=selected.key[1]) if selected else None,
                             cash_delta=delta, options=estimates,
                             sources=[Source(**{k: s[k] for k in ("id", "title", "url", "observed_at")})
                                      for s in snapshot.sources if s["id"] in used])
