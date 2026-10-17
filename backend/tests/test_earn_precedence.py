"""D4: the best applicable earn rate wins (reports/Paywise offers schema.md), replacing the
merchant > category > payment method > base tiers. These tests pin the change down:

- on every card x merchant x method combination the engine can produce from data/cards.json (a known merchant
  brings its own category; an unknown one any category), the new earn_rate gives the same rate and status as
  the tiered earn_rate it replaced, given the same rules;
- on the merchants that existed before offers (schemaVersion 1), nothing changes at all;
- it differs only where a more specific rule pays less than a broader one, and then it pays more.
"""

import datetime as dt
import itertools
from decimal import Decimal

import pytest

from app import catalog, engine
from app.catalog import Card, EarnRule

CAT = catalog.CATALOG
METHODS = ("apple_pay", "card")
MERCHANTS = (None, *(m.id for m in CAT.merchants))
CATEGORIES = (None, *(c.id for c in CAT.item_categories))
# Before, on and after the Lyft 2% window ends (2027-09-30), and the demo day.
DAYS = (dt.date(2026, 10, 16), dt.date(2026, 10, 17), dt.date(2027, 9, 30), dt.date(2027, 10, 1))

# schemaVersion 1's merchants and earn rules (git 6960a66: data/cards.json before offers).
V1_MERCHANTS = (None, "northbay-electronics", "stride-athletics", "nike", "amazon", "target", "best-buy", "walgreens",
                "doordash", "apple", "walmart")
V1_RULE_IDS = {"apple-card-apple", "apple-card-bonus-merchants", "apple-card-apple-pay", "cfu-dining", "cfu-drugstores"}


def legacy_earn_rate(card: Card, merchant_id: str | None, rule_category: str | None, method: str) -> engine.Rate:
    """engine.earn_rate as it was before D4 (git 6960a66), verbatim apart from the name."""
    usable = [r for r in card.earn.rules
              if not r.needs_activation and ("any" in r.payment_methods or method in r.payment_methods)]
    merchant_rules = [r for r in usable if r.merchant_ids and merchant_id in r.merchant_ids
                      and (r.category is None or r.category == rule_category)]
    category_rules = [r for r in usable if not r.merchant_ids and r.category is not None
                      and r.category == rule_category]
    method_rules = [r for r in usable if not r.merchant_ids and r.category is None]
    for tier in (merchant_rules, category_rules, method_rules):
        if tier:
            best = max(tier, key=lambda r: r.rate_pct)
            return engine.Rate(best.rate_pct, best.status)
    return engine.Rate(card.earn.base_rate_pct, card.earn.base_rate_status)


def with_rules(card: Card, rules) -> Card:
    return card.model_copy(update={"earn": card.earn.model_copy(update={"rules": tuple(rules)})})


def live_rules(card: Card, day: dt.date) -> list[EarnRule]:
    """The rules the window and channel filters keep on `day` (what the legacy function is given)."""
    return [r for r in card.earn.rules
            if (r.window is None or r.window.contains(day)) and not engine.CHECK_CHANNELS.isdisjoint(r.channels)]


def places():
    """(merchantId, ruleCategory) pairs engine.decide can produce: a catalog merchant comes with its own category
    (ruling R10); with no merchant, the items' shared category or none."""
    return [(m.id, m.category) for m in CAT.merchants] + [(None, c) for c in CATEGORIES]


def differences(day, pairs):
    found = []
    for card, (merchant_id, category), method in itertools.product(CAT.cards, pairs, METHODS):
        new = engine.earn_rate(card, merchant_id, category, method, day)
        old = legacy_earn_rate(with_rules(card, live_rules(card, day)), merchant_id, category, method)
        if (new.pct, new.status) != (old.pct, old.status):
            found.append((card.id, merchant_id, category, method, new.pct, old.pct))
    return found


@pytest.mark.parametrize("day", DAYS, ids=str)
def test_best_rate_equals_the_tiered_rate_on_every_current_combination(day):
    assert len(CAT.cards) * len(places()) * len(METHODS) == 5 * (22 + 22) * 2
    assert differences(day, places()) == []


@pytest.mark.parametrize("day", DAYS, ids=str)
def test_off_catalog_pairs_only_ever_pay_more(day):
    """Across every merchant x every category (pairs a parser could only produce for a merchant whose catalog
    category differs, e.g. Lyft with "dining"), D4 never pays less than the tiers did."""
    pairs = list(itertools.product(MERCHANTS, CATEGORIES))
    assert all(new > old for *_, new, old in differences(day, pairs))


@pytest.mark.parametrize("day", DAYS, ids=str)
def test_nothing_changes_on_the_v1_merchants(day):
    """The v2 rules only add merchants, so every rate on a v1 merchant (or none) is what v1 paid."""
    for card, merchant_id, category, method in itertools.product(CAT.cards, V1_MERCHANTS, CATEGORIES, METHODS):
        v1_card = with_rules(card, [r for r in card.earn.rules if r.id in V1_RULE_IDS])
        new = engine.earn_rate(card, merchant_id, category, method, day)
        old = legacy_earn_rate(v1_card, merchant_id, category, method)
        assert (new.pct, new.status) == (old.pct, old.status), (card.id, merchant_id, category, method)


def test_v1_rule_ids_are_all_still_there():
    ids = {r.id for card in CAT.cards for r in card.earn.rules}
    assert V1_RULE_IDS <= ids


def rule(id_, rate, *, merchants=None, category=None, methods=("any",), status="verified", **extra) -> EarnRule:
    return EarnRule(id=id_, category=category, merchant_ids=merchants, payment_methods=methods, rate_pct=Decimal(rate),
                    cap=None, needs_activation=False, status=status, **extra)


def test_a_broader_rule_that_pays_more_now_wins():
    """The one place D4 differs from the tiers: a merchant rule below a category rule."""
    card = with_rules(CAT.card("chase-freedom-unlimited"),
                      [rule("m", "2", merchants=("doordash",)), rule("c", "3", category="dining")])
    assert legacy_earn_rate(card, "doordash", "dining", "card").pct == Decimal("2")
    best = engine.earn_rate(card, "doordash", "dining", "card")
    assert (best.pct, best.rule_id) == (Decimal("3"), "c")


def test_the_base_rate_is_always_a_candidate():
    card = with_rules(CAT.card("chase-freedom-unlimited"), [rule("low", "1", merchants=("doordash",))])
    assert legacy_earn_rate(card, "doordash", "dining", "card").pct == Decimal("1")
    assert engine.earn_rate(card, "doordash", "dining", "card") == engine.Rate(Decimal("1.5"), "verified", None)


def test_ties_go_to_the_more_specific_rule():
    card = with_rules(CAT.card("apple-card"),
                      [rule("method", "3", methods=("apple_pay",), status="partial"), rule("merchant", "3", merchants=("nike",))])
    best = engine.earn_rate(card, "nike", "apparel", "apple_pay")
    assert (best.rule_id, best.status) == ("merchant", "verified")


def test_windows_follow_client_date():
    cfu = CAT.card("chase-freedom-unlimited")
    assert engine.earn_rate(cfu, "lyft", "travel", "card", dt.date(2027, 9, 30)).rule_id == "cfu-lyft"
    assert engine.earn_rate(cfu, "lyft", "travel", "card", dt.date(2027, 10, 1)).pct == Decimal("1.5")
    assert engine.earn_rate(cfu, "lyft", "travel", "card").pct == Decimal("2")  # no day: windows not checked


def test_in_store_only_rules_never_match_a_phone_checkout():
    apple = CAT.card("apple-card")
    duane = engine.earn_rate(apple, "duane-reade", "pharmacy", "apple_pay", dt.date(2026, 10, 17))
    assert (duane.pct, duane.rule_id) == (Decimal("2"), "apple-card-apple-pay")


@pytest.mark.parametrize("merchant_id", ["ace-hardware", "chargepoint", "exxon-mobil", "hertz", "uber", "uber-eats"])
def test_apple_pay_partners_pay_3_with_apple_pay_only(merchant_id):
    apple, day = CAT.card("apple-card"), dt.date(2026, 10, 17)
    category = CAT.merchant(merchant_id).category
    assert engine.earn_rate(apple, merchant_id, category, "apple_pay", day).pct == Decimal("3")
    assert engine.earn_rate(apple, merchant_id, category, "card", day).pct == Decimal("1")


def test_chase_travel_and_lyft():
    day = dt.date(2026, 10, 17)
    cfu, rise = CAT.card("chase-freedom-unlimited"), CAT.card("chase-freedom-rise")
    assert engine.earn_rate(cfu, "chase-travel", "travel", "card", day).pct == Decimal("5")
    assert engine.earn_rate(cfu, "chase-travel", "travel", "apple_pay", day).pct == Decimal("1.5")  # card only
    assert engine.earn_rate(rise, "lyft", "travel", "card", day).rule_id == "rise-lyft"
    assert engine.earn_rate(rise, "chase-travel", "travel", "card", day).pct == Decimal("1.5")
