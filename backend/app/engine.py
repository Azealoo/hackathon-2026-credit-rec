"""Recommendation engine: SPEC.md §7.2 rules 0–8, exactly, in order.

Money is Decimal throughout. Each card's cash is rounded to cents (half-up) before any
subtraction (§6.3 "Where S1's numbers come from"). Card rules come only from data/cards.json
(app/catalog.py); thresholds come from app/policy.py; copy comes from app/copy.py.

Rulings applied here (see the module docstrings and the track report):
- Baseline (v2.3): rules 4–8 compare against the wallet card selected on screen when a saved card is
  selected and exactly one wallet card has its network; otherwise against the default. A Keep keeps
  the baseline, and cashBest ties go to the baseline, then the default, then wallet order.
- R7: Freedom Unlimited's 3% dining/pharmacy rules are catalog earn rules like any other.
- v2.3 (replaces R10): a category earn rule counts only at a known merchant, against its catalog
  category (Chase decides by merchant code). At an unknown store, a category rule that matches the
  items' shared category isn't counted but marks the rate partial, as does a matching rule that needs
  activation.
- Earn precedence: merchant rule > category rule > a payment-method rule with neither
  (e.g. Apple Card's 2% via Apple Pay) > base rate; the best rate wins within a tier.
- v2.3 rule 3: a protection *covers* an item when its terms do, at any price; an item *qualifies*
  for Rule P when it costs $100+ in a relevant category. No switch drops cover the baseline has.
- §8.2 display rule: confidence is worked out before the copy. A "medium" answer drops the cap
  (copy line 2 and the draft's limitUsd); a cash figure from a rate that isn't verified is stated
  without its number; the draft saves no dates for a protection that isn't verified.
"""

import calendar
import datetime as dt
from collections.abc import Sequence
from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal

from app import copy as copy_text
from app import policy
from app.catalog import CATALOG, Card, Catalog, EarnRule, ItemCategory, Protection
from app.models import (
    Cart,
    Cash,
    Confidence,
    CoverageEntry,
    Decision,
    Item,
    PaymentPath,
    ProtectionChange,
    ProtectionLimit,
    PurchaseDraft,
    ScreenType,
    Source,
    WalletCard,
)

# §7.2 rule 3: only these protection types count.
PROTECTION_TYPES = ("purchase_protection", "extended_warranty")

CENT = Decimal("0.01")
ZERO = Decimal("0")

# Eligibility notes (§6.3 Switch, cash; §7.3). Keyed by the item condition that blocked cover. The engine can't
# see whether a renewed listing has a warranty, so its note claims neither way.
CONDITION_NOTES = {
    "renewed": "Renewed: no card cover counted",
    "used": "Used item: no card covers it",
    "unknown": "Item condition unclear: no card cover counted",
}

NO_CHECKOUT_REASONS = {"not_checkout": "not_checkout", "unreadable": "unreadable",
                       "order_confirmation": "already_paid"}


@dataclass(frozen=True)
class EngineResult:
    decision: Decision
    purchase_draft: PurchaseDraft | None
    sources: list[Source]


@dataclass(frozen=True)
class Rate:
    pct: Decimal
    status: str  # verified / partial / unverified


def cents(amount: Decimal) -> Decimal:
    return amount.quantize(CENT, rounding=ROUND_HALF_UP)


def dec(value: float | int | Decimal) -> Decimal:
    """Wire floats to Decimal through their shortest repr (1499.0 -> Decimal('1499.0'))."""
    return value if isinstance(value, Decimal) else Decimal(str(value))


class DateOutOfRange(ValueError):
    """A purchaseDraft coverage date would fall after Dec 31, 9999 (a clientDate near the calendar's end): a 400."""


OUT_OF_RANGE = "A coverage date would fall after Dec 31, 9999: check clientDate."


def add_months(day: dt.date, months: int) -> dt.date:
    years, month0 = divmod(day.month - 1 + months, 12)
    year, month = day.year + years, month0 + 1
    if not dt.MINYEAR <= year <= dt.MAXYEAR:
        raise DateOutOfRange(OUT_OF_RANGE)
    return dt.date(year, month, min(day.day, calendar.monthrange(year, month)[1]))


def add_days(day: dt.date, days: int) -> dt.date:
    try:
        return day + dt.timedelta(days=days)
    except OverflowError:
        raise DateOutOfRange(OUT_OF_RANGE) from None


# --- Rule 1: cash per card ----------------------------------------------------------------------


def payment_path(cart: Cart) -> PaymentPath:
    """apple_pay when an Apple Pay button is visible (every wallet card is assumed to be in
    Wallet); otherwise the saved-card or card-form path the screen shows (§7.2 rule 1)."""
    visible = cart.payment_options_visible
    if "apple_pay" in visible or cart.selected_payment.kind == "apple_pay":
        return "apple_pay"
    for path in ("saved_card", "card_form"):
        if path in visible:
            return path
    if cart.selected_payment.kind in ("saved_card", "card_form"):
        return cart.selected_payment.kind
    return "unknown"


def _applies(rule: EarnRule, merchant_id: str | None, category: str | None, method: str) -> bool:
    if "any" not in rule.payment_methods and method not in rule.payment_methods:
        return False
    if rule.merchant_ids:
        return merchant_id in rule.merchant_ids and (rule.category is None or rule.category == category)
    return rule.category is None or rule.category == category


def earn_rate(card: Card, merchant_id: str | None, category: str | None, method: str, *,
              guess_category: str | None = None) -> Rate:
    """The card's rate for this merchant and payment method ("apple_pay" or "card").

    `category` is the known merchant's catalog category: Chase decides by merchant code, so a category rule
    counts only there. `guess_category` is the items' shared category at a store the catalog doesn't know.
    A rule that may apply but isn't counted (it needs activation, or it matches only the guessed category)
    leaves the counted rate in place but marks it partial, so the copy hedges (§7.2 rule 1)."""
    counted = [r for r in card.earn.rules if not r.needs_activation and _applies(r, merchant_id, category, method)]
    tiers = ([r for r in counted if r.merchant_ids],
             [r for r in counted if not r.merchant_ids and r.category is not None],
             [r for r in counted if not r.merchant_ids and r.category is None])
    tier = next((t for t in tiers if t), None)
    if tier:
        best = max(tier, key=lambda r: r.rate_pct)
        rate = Rate(best.rate_pct, best.status)
    else:
        rate = Rate(card.earn.base_rate_pct, card.earn.base_rate_status)
    maybe = [r for r in card.earn.rules if r.needs_activation and _applies(r, merchant_id, category, method)]
    if guess_category is not None:
        maybe += [r for r in card.earn.rules if _applies(r, merchant_id, guess_category, method)]
    if rate.status == "verified" and any(r.rate_pct > rate.pct for r in maybe):
        return Rate(rate.pct, "partial")
    return rate


def cash_for(amount: Decimal, rate: Rate) -> Decimal:
    return cents(amount * rate.pct / 100)


# --- Baseline -----------------------------------------------------------------------------------


def selected_card(cards: Sequence[Card], cart: Cart) -> Card | None:
    """The wallet card selected on screen: a saved card is selected and exactly one wallet card has its network.
    None when the screen doesn't say, or when its network fits no wallet card or several (§7.2 baseline)."""
    selected = cart.selected_payment
    if selected.kind != "saved_card" or selected.network == "unknown":
        return None
    matches = [card for card in cards if card.network == selected.network]
    return matches[0] if len(matches) == 1 else None


# --- Rule 3: eligibility ------------------------------------------------------------------------


def _payment_requirement_met(requirement: str | None, path: PaymentPath) -> bool:
    """v1 pays the whole cart with the picked card on every path (Apple Pay charges the card too),
    so "some_portion" and "full" are both met. BNPL or split tender (P1) would fail "full"."""
    return requirement in (None, "some_portion", "full") and path in ("apple_pay", "saved_card", "card_form", "unknown")


class _Rules:
    """§7.2 rule 3 for one cart, with the catalog looked up once."""

    def __init__(self, cat: Catalog, cart: Cart, path: PaymentPath):
        self.cat, self.cart, self.path = cat, cart, path

    def category(self, item: Item) -> ItemCategory | None:
        try:
            return self.cat.item_category(item.category)
        except KeyError:  # a parser produced an id the catalog doesn't know: treat as not covered
            return None

    def relevant_types(self, item: Item) -> set[str]:
        category = self.category(item)
        if category is None:
            return set()
        types = set()
        if category.theft_damage_relevant:
            types.add("purchase_protection")
        if category.warranty_relevant:
            types.add("extended_warranty")
        return types

    def qualifying_types(self, item: Item) -> set[str]:
        """Types the item qualifies for (Rule P): price ≥ PROTECTION_MIN_ITEM_USD and a relevant category."""
        if dec(item.price_usd) < policy.PROTECTION_MIN_ITEM_USD:
            return set()
        return self.relevant_types(item)

    def blockers(self, protection: Protection, item: Item) -> list[str]:
        """Why this protection's terms don't cover this item ([] = covered, at any price)."""
        why = []
        rules = protection.eligibility
        category = self.category(item)
        if rules.conditions_allowed is not None and item.condition not in rules.conditions_allowed:
            why.append(f"condition:{item.condition}")
        if item.is_gift_card:
            why.append("gift_card")
        if item.is_service_plan:
            why.append("service_plan")
        if not _payment_requirement_met(rules.payment_requirement, self.path):
            why.append("payment")
        if category is None:
            why.append("unknown_category")
        elif item.category in rules.excluded_categories:
            why.append("excluded_category")
        elif protection.type == "extended_warranty" and not category.warranty_relevant:
            why.append("no_maker_warranty")  # warrantyRelevant stands in for "comes with a maker's warranty"
        return why

    def covers(self, card: Card, item: Item) -> dict[str, Protection]:
        """The card's protections of the counted types whose terms cover this item, by type."""
        return {p.type: p for p in card.protections if p.type in PROTECTION_TYPES and not self.blockers(p, item)}

    def eligible(self, card: Card, item: Item) -> dict[str, Protection]:
        """Covered types the item also qualifies for (Rule P, Guard G, rule 8), by type."""
        wanted = self.qualifying_types(item)
        return {t: p for t, p in self.covers(card, item).items() if t in wanted}


def _ordered(types: set[str]) -> list[str]:
    return [t for t in PROTECTION_TYPES if t in types]


def _change(protection: Protection) -> ProtectionChange:
    limits = protection.limits
    applies_to = limits.applies_to or ("item" if limits.per_item_usd is not None else "claim")
    amount = limits.per_item_usd if applies_to == "item" else limits.per_claim_usd
    fields = {"type": protection.type,
              "limit": ProtectionLimit(amount_usd=None if amount is None else float(amount), applies_to=applies_to),
              "verification": protection.verification.status}
    if protection.type == "purchase_protection":
        fields["window_days"] = protection.window_days
    elif protection.type == "extended_warranty":
        fields["extends_by_months"] = protection.extends_by_months
    return ProtectionChange(**fields)


# --- The decision -------------------------------------------------------------------------------


def _wallet(cat: Catalog, wallet: Sequence[WalletCard]) -> tuple[list[Card], Card]:
    cards = [cat.card(entry.card_id) for entry in wallet]
    defaults = [card for card, entry in zip(cards, wallet) if entry.is_default]
    if len(defaults) != 1:
        raise ValueError("exactly one wallet card must be the default")
    return cards, defaults[0]


def _no_checkout(screen_type: ScreenType, default: Card) -> EngineResult:
    reason = NO_CHECKOUT_REASONS[screen_type]
    decision = Decision(
        kind="no_checkout", reason=reason, presentation="island", recommended_card_id=None,
        default_card_id=default.id, cash_best_card_id=None, payment_path="unknown", instruction="none",
        cash=None, protections_gained=[], protections_lost=[], eligibility_notes=[], confidence="high",
        copy=copy_text.no_checkout(reason),
    )
    return EngineResult(decision, None, [])


def decide(screen_type: ScreenType, cart: Cart | None, wallet: Sequence[WalletCard],
           client_date: dt.date, cat: Catalog = CATALOG) -> EngineResult:
    """Run §7.2 rules 0–8 on one parsed screen for one wallet (in wallet order)."""
    cards, default = _wallet(cat, wallet)

    # Rule 0: screen type. A "checkout" with neither a total nor items is no checkout either.
    if screen_type != "checkout":
        return _no_checkout(screen_type, default)
    if cart is None or (cart.total_usd is None and not cart.items):
        return _no_checkout("not_checkout", default)

    # Baseline: the card selected on screen when it's known, else the default.
    baseline = selected_card(cards, cart) or default

    # Rule 1: cash per card.
    path = payment_path(cart)
    method = "apple_pay" if path == "apple_pay" else "card"
    amount = dec(cart.total_usd) if cart.total_usd is not None else sum(
        (dec(i.price_usd) * i.quantity for i in cart.items), ZERO)
    merchant = _merchant(cat, cart)
    merchant_id = merchant.id if merchant else None
    category = merchant.category if merchant else None
    guess = None if merchant else _shared_category(cart)
    rates = {c.id: earn_rate(c, merchant_id, category, method, guess_category=guess) for c in cards}
    cash = {c.id: cash_for(amount, rates[c.id]) for c in cards}
    best_cash = max(cash.values())
    tied = [c for c in cards if cash[c.id] == best_cash]
    cash_best = next((c for c in (baseline, default) if c in tied), tied[0])

    rules = _Rules(cat, cart, path)
    ctx = _Context(cat, cart, path, cards, default, baseline, cash_best, cash, rates, rules, client_date)

    # Rule 2: items unreadable.
    if not cart.items or cart.confidence.items < policy.ITEM_CONFIDENCE_MIN:
        return ctx.keep("items_unreadable", copy_text.keep_items_unreadable(baseline), ctx.confidence())

    # Rule 3: eligible protections per card, on qualifying items; and what the baseline covers on every item.
    qualifying = [item for item in cart.items if rules.qualifying_types(item)]
    eligible = {c.id: [rules.eligible(c, item) for item in qualifying] for c in cards}
    baseline_types = [set(e) for e in eligible[baseline.id]]
    baseline_covers = [rules.covers(baseline, item) for item in cart.items]

    # Rule 4 (P): a card that adds a type the baseline lacks on a qualifying item and keeps every type the
    # baseline covers on every item.
    candidates = []
    for index, card in enumerate(cards):
        if card is baseline:
            continue
        if not all(set(rules.covers(card, item)) >= set(mine) for item, mine in zip(cart.items, baseline_covers)):
            continue
        card_types = [set(e) for e in eligible[card.id]]
        gained = sum(len(mine - theirs) for mine, theirs in zip(card_types, baseline_types))
        if gained:
            candidates.append((gained, cash[card.id], -index, card))
    if candidates:
        pick = max(candidates, key=lambda c: c[:3])[3]
        gained_types = set().union(*(set(e) - b for e, b in zip(eligible[pick.id], baseline_types)))
        gained = _protections(eligible[pick.id], gained_types)
        delta = cash[pick.id] - cash[cash_best.id]
        confidence = ctx.confidence(gained)
        return ctx.switch("protection", pick, gained, confidence, copy_text.switch_protection(
            pick, gained, delta, cash_best, path, show_cap=confidence == "high",
            cash_verified=_verified(rates[pick.id], rates[cash_best.id])))

    # Rule 5 (G): the baseline has an eligible type cashBest lacks on a qualifying item -> keep.
    kept = _protections(eligible[baseline.id], set().union(*baseline_types))
    kept_confidence = ctx.confidence(kept)
    if cash_best is not baseline:
        best_types = [set(e) for e in eligible[cash_best.id]]
        if any(theirs - mine for mine, theirs in zip(best_types, baseline_types)):
            return ctx.keep("already_protected", copy_text.keep_protected(
                baseline, kept, show_cap=kept_confidence == "high"), kept_confidence, kept=kept)

    # Rule 6 (C): cash switch above the path's threshold, unless it drops cover the baseline has on any item.
    threshold = policy.CASH_SWITCH_MIN_USD[path]
    gain = cash[cash_best.id] - cash[baseline.id]
    if cash_best is not baseline and gain >= threshold:
        if ctx.lost(cash_best):
            covered = _protections(baseline_covers, set().union(*(set(c) for c in baseline_covers)))
            covered_confidence = ctx.confidence(covered)
            return ctx.keep("already_protected", copy_text.keep_protected(
                baseline, covered, show_cap=covered_confidence == "high"), covered_confidence, kept=covered)
        notes = ctx.notes()
        return ctx.switch("cash", cash_best, [], ctx.confidence(), copy_text.switch_cash(
            cash_best, gain, baseline, notes, path, cash_verified=_verified(rates[cash_best.id], rates[baseline.id])),
            notes=notes)

    # Rule 7 (M): the baseline earns more via Apple Pay than typed, and the button is visible.
    if path == "apple_pay":
        apple_pay_rate = earn_rate(baseline, merchant_id, category, "apple_pay", guess_category=guess)
        typed_rate = earn_rate(baseline, merchant_id, category, "card", guess_category=guess)
        apple_pay_cash = cash_for(amount, apple_pay_rate)
        if apple_pay_cash > cash_for(amount, typed_rate):
            return ctx.keep("method", copy_text.keep_method(
                baseline, apple_pay_rate.pct, apple_pay_cash, typed_rate.pct,
                verified=_verified(apple_pay_rate, typed_rate)),
                ctx.confidence(extra_rates=[apple_pay_rate, typed_rate]))

    # Rule 8: keep. "Best of" and "gains under" compare every card, so every rate must be verified to say so flat.
    if kept:
        return ctx.keep("already_protected", copy_text.keep_protected(
            baseline, kept, show_cap=kept_confidence == "high"), kept_confidence, kept=kept)
    every_rate = _verified(*rates.values())
    if cash_best is not baseline:
        return ctx.keep("below_threshold", copy_text.keep_below_threshold(baseline, threshold, verified=every_rate),
                        ctx.confidence())
    return ctx.keep("default_best", copy_text.keep_default_best(baseline, len(cards), verified=every_rate),
                    ctx.confidence())


def _verified(*rates: Rate) -> bool:
    """§8.2: a cash figure is stated as fact only when every rate behind it is verified."""
    return all(rate.status == "verified" for rate in rates)


def _merchant(cat: Catalog, cart: Cart):
    if cart.merchant.merchant_id:
        try:
            return cat.merchant(cart.merchant.merchant_id)
        except KeyError:
            pass
    return cat.find_merchant(cart.merchant.name) if cart.merchant.name else None


def _shared_category(cart: Cart) -> str | None:
    categories = {item.category for item in cart.items}
    return categories.pop() if len(categories) == 1 else None


def _protections(per_item: list[dict[str, Protection]], types: set[str]) -> list[Protection]:
    """One Protection per type (the first item that has it), in PROTECTION_TYPES order."""
    found: dict[str, Protection] = {}
    for eligible in per_item:
        for type_, protection in eligible.items():
            if type_ in types:
                found.setdefault(type_, protection)
    return [found[t] for t in _ordered(set(found))]


@dataclass
class _Context:
    """Everything rules 1–3 worked out, for building the decision."""

    cat: Catalog
    cart: Cart
    path: PaymentPath
    cards: list[Card]
    default: Card
    baseline: Card
    cash_best: Card
    cash: dict[str, Decimal]
    rates: dict[str, Rate]
    rules: _Rules
    client_date: dt.date

    def notes(self) -> list[str]:
        """Why an item that would qualify gets no card cover (only when its condition blocks a
        protection a wallet card has; gift cards and service plans aren't protectable items)."""
        notes: list[str] = []
        for item in self.cart.items:
            if item.is_gift_card or item.is_service_plan or not self.rules.qualifying_types(item):
                continue
            if any(self.rules.eligible(card, item) for card in self.cards):
                continue
            blocked_by_condition = any(
                f"condition:{item.condition}" in self.rules.blockers(p, item)
                for card in self.cards for p in card.protections
                if p.type in PROTECTION_TYPES and p.type in self.rules.qualifying_types(item))
            note = CONDITION_NOTES.get(item.condition)
            if blocked_by_condition and note and note not in notes:
                notes.append(note)
        return notes

    def _cash(self, picked: Card) -> Cash:
        return Cash(by_card={card_id: float(value) for card_id, value in self.cash.items()},
                    delta_vs_cash_best=float(self.cash[picked.id] - self.cash[self.cash_best.id]),
                    delta_vs_default=float(self.cash[picked.id] - self.cash[self.default.id]))

    def lost(self, picked: Card) -> list[Protection]:
        """Types the baseline covers on some item (any price or category its terms allow) that `picked` doesn't."""
        if picked is self.baseline:
            return []
        lost: set[str] = set()
        baseline_covers: list[dict[str, Protection]] = []
        for item in self.cart.items:
            mine = self.rules.covers(self.baseline, item)
            lost |= set(mine) - set(self.rules.covers(picked, item))
            baseline_covers.append(mine)
        return _protections(baseline_covers, lost)

    def confidence(self, protections: Sequence[Protection] = (), extra_rates: Sequence[Rate] = ()) -> Confidence:
        """medium when the answer leans on a partial or unverified value (§8.2), else high. Every answer
        compares the wallet's cards, so every card's rate here counts."""
        statuses = ([r.status for r in self.rates.values()] + [r.status for r in extra_rates]
                    + [p.verification.status for p in protections])
        return "high" if all(s == "verified" for s in statuses) else "medium"

    def _main_item(self, picked: Card, prefer: set[str]) -> Item:
        """The item the draft saves: the priciest qualifying item the picked card covers (one holding a `prefer`
        type first, e.g. the cover a protection switch gains), so the draft matches the copy; else the priciest
        item it covers at all (Rule C's cover check); else the priciest qualifying item; else the priciest item."""
        eligible = [i for i in self.cart.items if self.rules.eligible(picked, i)]
        preferred = [i for i in eligible if prefer & set(self.rules.eligible(picked, i))]
        covered = [i for i in self.cart.items if self.rules.covers(picked, i)]
        qualifying = [i for i in self.cart.items if self.rules.qualifying_types(i)]
        return max(preferred or eligible or covered or qualifying or self.cart.items, key=lambda i: dec(i.price_usd))

    def _draft(self, picked: Card, confidence: Confidence, prefer: set[str] = frozenset()) -> PurchaseDraft:
        """The purchase [Paying with …] saves, with coverage dates (§5.4, §15.5). The phone states these dates and
        the cap as fact (Saved, Purchases), so §8.2 applies: a protection that isn't verified saves no entry, and a
        medium-confidence answer saves no cap, as its copy line 2 shows none."""
        item = self._main_item(picked, prefer)
        coverage = []
        for protection in self.rules.covers(picked, item).values():
            if protection.verification.status != "verified":
                continue
            if protection.type == "purchase_protection" and protection.window_days:
                cap = copy_text.verified_cap(protection) if confidence == "high" else None
                coverage.append(CoverageEntry(
                    type=protection.type,
                    until=add_days(self.client_date, protection.window_days),
                    limit_usd=_float(cap)))
            elif protection.type == "extended_warranty" and protection.extends_by_months:
                maker = policy.ASSUMED_MANUFACTURER_WARRANTY_MONTHS
                if protection.max_original_warranty_months is not None and maker > protection.max_original_warranty_months:
                    continue
                months = maker + protection.extends_by_months
                if protection.max_total_from_purchase_months is not None:
                    months = min(months, protection.max_total_from_purchase_months)
                coverage.append(CoverageEntry(type=protection.type, until=add_months(self.client_date, months),
                                              assumes_manufacturer_warranty_months=maker))
        coverage.sort(key=lambda entry: PROTECTION_TYPES.index(entry.type))
        return PurchaseDraft(
            merchant=self.cart.merchant.name or "Unknown store", item=item.name, category=item.category,
            condition=item.condition, price_usd=item.price_usd, purchase_date=self.client_date,
            card_id=picked.id, coverage=coverage)

    def _sources(self, picked: Card, protections: list[Protection], cash_copy: bool) -> list[Source]:
        sources = [Source(card_id=picked.id, document=p.source.document, section=p.source.section,
                          version_date=p.source.version_date, verification=p.verification.status)
                   for p in protections if p.source.document]
        if cash_copy:  # the copy states cash numbers: cite where the rate comes from
            status = self.rates[picked.id].status
            sources += [Source(card_id=picked.id, document=s.document, section=s.section,
                               version_date=s.version_date, verification=status)
                        for s in picked.sources if s.document]
        return sources

    def _decision(self, kind: str, reason: str, picked: Card, gained: list[Protection], copy,
                  notes: list[str], confidence: Confidence) -> Decision:
        if kind == "switch":
            instruction = {"apple_pay": "apple_pay_swipe", "saved_card": "change_saved_card",
                           "card_form": "enter_card"}.get(self.path, "none")
        else:
            instruction = "use_apple_pay" if reason == "method" else "none"
        presentation = "snippet" if kind == "switch" or reason == "already_protected" else "island"
        return Decision(
            kind=kind, reason=reason, presentation=presentation, recommended_card_id=picked.id,
            default_card_id=self.default.id, cash_best_card_id=self.cash_best.id, payment_path=self.path,
            instruction=instruction, cash=self._cash(picked),
            protections_gained=[_change(p) for p in gained], protections_lost=[_change(p) for p in self.lost(picked)],
            eligibility_notes=notes, confidence=confidence, copy=copy)

    def switch(self, reason: str, picked: Card, gained: list[Protection], confidence: Confidence, copy,
               notes: list[str] | None = None) -> EngineResult:
        notes = self.notes() if notes is None else notes
        decision = self._decision("switch", reason, picked, gained, copy, notes, confidence)
        return EngineResult(decision, self._draft(picked, confidence, {p.type for p in gained}),
                            self._sources(picked, gained, cash_copy=reason == "cash"))

    def keep(self, reason: str, copy, confidence: Confidence, kept: list[Protection] | None = None) -> EngineResult:
        """Keep the baseline: the card on screen when it's known, else the default."""
        kept = kept or []
        notes = [] if reason == "items_unreadable" else self.notes()
        decision = self._decision("keep", reason, self.baseline, [], copy, notes, confidence)
        draft = self._draft(self.baseline, confidence) if reason == "already_protected" else None
        return EngineResult(decision, draft, self._sources(self.baseline, kept, cash_copy=reason == "method"))


def _float(value: Decimal | None) -> float | None:
    return None if value is None else float(value)
