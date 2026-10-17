"""Unit tests for app/engine.py, app/copy.py and app/middleware.py beyond the 22 scenarios."""

import datetime as dt
import json
from decimal import Decimal

import pytest

from app import catalog, copy, engine, middleware, policy
from app.catalog import CARDS_FILE, Catalog
from app.models import Cart, WalletCard

DAY = dt.date(2026, 10, 17)


def wallet(*card_ids: str) -> list[WalletCard]:
    return [WalletCard(card_id=card_id, is_default=i == 0) for i, card_id in enumerate(card_ids)]


def cart(items=(("Aero 14 Laptop, 14-inch", 1499.0, "computers", "new"),), total=None, merchant=("Northbay Electronics", "northbay-electronics"),
         options=("saved_card",), items_confidence=0.92, network="unknown") -> Cart:
    """`network`: the selected saved card's network. "unknown" (the screen doesn't say) keeps the default as the
    baseline; tests of the selected-card baseline are in test_advice_correctness.py."""
    item_list = [{"name": n, "priceUsd": p, "quantity": 1, "category": c, "condition": cond, "seller": "merchant",
                  "isGiftCard": c == "gift_card", "isServicePlan": c == "services"} for n, p, c, cond in items]
    return Cart.model_validate({
        "merchant": {"name": merchant[0], "merchantId": merchant[1]}, "items": item_list,
        "totalUsd": sum(i["priceUsd"] for i in item_list) if total is None else total, "currency": "USD",
        "paymentOptionsVisible": list(options),
        "selectedPayment": {"kind": "saved_card" if "saved_card" in options else "unknown", "network": network},
        "upsells": {"protectionPlanUsd": None}, "bnplVisible": False,
        "confidence": {"merchant": 0.97, "total": 0.98, "items": items_confidence}})


def decide(c: Cart, w: list[WalletCard], cat: Catalog = catalog.CATALOG, screen="checkout"):
    return engine.decide(screen, c, w, DAY, cat)


def catalog_with(edit) -> Catalog:
    raw = json.loads(CARDS_FILE.read_text(encoding="utf-8"), parse_float=Decimal)
    raw.pop("$schema", None)
    edit(raw)
    return Catalog.model_validate(raw)


def protection(raw: dict, card_id: str, type_: str) -> dict:
    card = next(c for c in raw["cards"] if c["id"] == card_id)
    return next(p for p in card["protections"] if p["type"] == type_)


# --- Rule 1 ------------------------------------------------------------------------------------


def test_half_up_cents_before_subtracting():
    assert engine.cents(Decimal("22.485")) == Decimal("22.49")
    assert engine.cents(Decimal("3.735")) == Decimal("3.74")
    assert engine.cents(Decimal("0.005")) == Decimal("0.01")


@pytest.mark.parametrize(
    "card_id, merchant_id, category, method, rate",
    [
        ("apple-card", "nike", "apparel", "apple_pay", "3"),   # merchant rule beats the 2% Apple Pay rule
        ("apple-card", "nike", "apparel", "card", "1"),        # Nike's 3% needs Apple Pay
        ("apple-card", "apple", "electronics", "card", "3"),   # Apple's own store: any method
        ("apple-card", "northbay-electronics", "electronics", "apple_pay", "2"),
        ("chase-freedom-unlimited", "doordash", "dining", "card", "3"),  # R7: the merchant's category
        ("chase-freedom-unlimited", "walgreens", "pharmacy", "card", "3"),  # a known merchant's category
        ("chase-freedom-unlimited", "northbay-electronics", "electronics", "card", "1.5"),
        ("wf-active-cash", "nike", "apparel", "apple_pay", "2"),
    ],
)
def test_earn_rate_precedence(card_id, merchant_id, category, method, rate):
    assert engine.earn_rate(catalog.card(card_id), merchant_id, category, method).pct == Decimal(rate)


def test_unknown_merchant_earns_the_base_rate_and_a_shared_item_category_marks_it_partial():
    """v2.4 §7.2 rule 1 (replaces R10): Chase codes by merchant, so the items' category isn't counted."""
    one = cart(items=(("Multivitamin", 40.0, "pharmacy", "new"),), merchant=("Corner Drugs", None))
    mixed = cart(items=(("Multivitamin", 40.0, "pharmacy", "new"), ("Mug", 10.0, "home", "new")),
                 merchant=("Corner Drugs", None))
    fu = wallet("chase-freedom-unlimited")
    d = decide(one, fu).decision
    assert (d.cash.by_card["chase-freedom-unlimited"], d.confidence) == (0.6, "medium")
    d = decide(mixed, fu).decision  # no shared category: nothing to guess
    assert (d.cash.by_card["chase-freedom-unlimited"], d.confidence) == (0.75, "high")


def test_cash_best_tie_goes_to_the_baseline_then_the_default_then_wallet_order():
    tie = decide(cart(), wallet("apple-card", "discover-it-student-cash-back")).decision
    assert tie.cash_best_card_id == "apple-card"
    selected = decide(cart(network="discover"), wallet("apple-card", "discover-it-student-cash-back")).decision
    assert selected.cash_best_card_id == "discover-it-student-cash-back"  # the card on screen
    # No card is selected and neither tied card is the default, so wallet order decides.
    ap = cart(merchant=("Best Buy", "best-buy"), options=("apple_pay", "saved_card"))
    assert decide(ap, wallet("chase-freedom-unlimited", "wf-active-cash", "apple-card")).decision.cash_best_card_id == "wf-active-cash"
    assert decide(ap, wallet("chase-freedom-unlimited", "apple-card", "wf-active-cash")).decision.cash_best_card_id == "apple-card"


@pytest.mark.parametrize(
    "options, selected, path",
    [(["apple_pay", "card_form"], "card_form", "apple_pay"), (["saved_card"], "saved_card", "saved_card"),
     (["card_form"], "card_form", "card_form"), ([], "saved_card", "saved_card"), ([], "unknown", "unknown"),
     (["paypal"], "unknown", "unknown")],
)
def test_payment_path_follows_the_visible_buttons(options, selected, path):
    c = cart().model_copy(update={"payment_options_visible": options,
                                  "selected_payment": cart().selected_payment.model_copy(update={"kind": selected})})
    assert engine.payment_path(c) == path


# --- Rules 0, 2, 3 -----------------------------------------------------------------------------


def test_checkout_without_total_or_items_is_no_checkout():
    empty = cart(items=(), total=None).model_copy(update={"total_usd": None})
    d = decide(empty, wallet("apple-card", "chase-freedom-unlimited")).decision
    assert (d.kind, d.reason, d.cash) == ("no_checkout", "not_checkout", None)


def test_missing_total_uses_the_items_sum():
    c = cart().model_copy(update={"total_usd": None})
    d = decide(c, wallet("apple-card", "wf-active-cash", "chase-freedom-unlimited")).decision
    assert d.cash.by_card["wf-active-cash"] == 29.98 and d.kind == "switch"


def test_no_items_is_items_unreadable():
    d = decide(cart(items=(), total=1499.0), wallet("apple-card", "chase-freedom-unlimited")).decision
    assert (d.kind, d.reason, d.recommended_card_id) == ("keep", "items_unreadable", "apple-card")


@pytest.mark.parametrize(
    "item, why",
    [(("2-Year Protection Plan", 199.0, "services", "new"), "service plan"),
     (("Northbay eGift Card", 500.0, "gift_card", "new"), "gift card"),
     (("Aero 14 Laptop", 99.99, "computers", "new"), "under $100"),
     (("Aero 14 Laptop", 1499.0, "computers", "used"), "used"),
     (("Aero 14 Laptop", 1499.0, "computers", "unknown"), "condition unknown"),
     (("Mystery Thing", 1499.0, "not_a_category", "new"), "category the catalog doesn't know")],
)
def test_no_protection_switch(item, why):
    d = decide(cart(items=(item,)), wallet("apple-card", "chase-freedom-unlimited")).decision
    assert d.reason != "protection", why
    assert d.protections_gained == []


def test_used_item_note_names_its_condition():
    d = decide(cart(items=(("Aero 14 Laptop", 1499.0, "computers", "used"),)),
               wallet("apple-card", "wf-active-cash", "chase-freedom-unlimited")).decision
    assert (d.kind, d.reason) == ("switch", "cash")
    assert d.eligibility_notes == ["Used item: no card covers it"]


def test_excluded_category_blocks_cover():
    def exclude_computers(raw):
        for type_ in ("purchase_protection", "extended_warranty"):
            protection(raw, "chase-freedom-unlimited", type_)["eligibility"]["excludedCategories"] = ["computers"]

    cat = catalog_with(exclude_computers)
    d = decide(cart(), wallet("apple-card", "wf-active-cash", "chase-freedom-unlimited"), cat).decision
    assert (d.kind, d.reason, d.recommended_card_id) == ("switch", "cash", "wf-active-cash")


# --- Rules 4, 5 with several items -------------------------------------------------------------


def test_rule_p_never_drops_a_protection_on_any_item():
    # Rise default; FU has the same protections, so nothing is gained: guard keeps Rise (cash-best AC lacks them).
    two = cart(items=(("Aero 14 Laptop", 1200.0, "computers", "new"), ("Studio Headphones", 120.0, "audio", "new")))
    d = decide(two, wallet("chase-freedom-rise", "wf-active-cash", "chase-freedom-unlimited")).decision
    assert (d.kind, d.reason, d.recommended_card_id) == ("keep", "already_protected", "chase-freedom-rise")
    assert d.presentation == "snippet"


def test_rule_p_breaks_ties_by_cash_then_wallet_order():
    d = decide(cart(), wallet("apple-card", "chase-freedom-rise", "chase-freedom-unlimited")).decision
    assert d.recommended_card_id == "chase-freedom-rise"  # same cash, same protections: wallet order
    dining = cart(items=(("Aero 14 Laptop", 1499.0, "computers", "new"),), merchant=("DoorDash", "doordash"))
    d = decide(dining, wallet("apple-card", "chase-freedom-rise", "chase-freedom-unlimited")).decision
    assert d.recommended_card_id == "chase-freedom-unlimited"  # FU's 3% dining earns more


def test_purchase_draft_follows_the_most_expensive_qualifying_item():
    two = cart(items=(("Ceramic Coffee Mug", 18.0, "home", "new"), ("Wireless Earbuds", 249.0, "audio", "new")))
    result = decide(two, wallet("apple-card", "chase-freedom-unlimited"))
    assert result.purchase_draft.item == "Wireless Earbuds"
    assert [c.type for c in result.purchase_draft.coverage] == ["purchase_protection", "extended_warranty"]


RENEWED_LAPTOP_AND_EARBUDS = (("Aero 14 Laptop, 14-inch", 1099.0, "computers", "renewed"),
                              ("Wireless Earbuds", 249.0, "audio", "new"))


def test_protection_switch_draft_saves_the_item_the_cover_is_for():
    """BE-2: the renewed laptop costs more but no card covers it; the draft saves the earbuds the switch is for."""
    result = decide(cart(items=RENEWED_LAPTOP_AND_EARBUDS),
                    wallet("apple-card", "wf-active-cash", "chase-freedom-unlimited"))
    assert (result.decision.kind, result.decision.reason) == ("switch", "protection")
    draft = result.purchase_draft
    assert (draft.item, draft.condition, draft.price_usd) == ("Wireless Earbuds", "new", 249.0)
    assert [c.type for c in draft.coverage] == ["purchase_protection", "extended_warranty"]


def test_already_protected_draft_saves_the_covered_item():
    result = decide(cart(items=RENEWED_LAPTOP_AND_EARBUDS),
                    wallet("chase-freedom-unlimited", "wf-active-cash", "apple-card"))
    assert (result.decision.kind, result.decision.reason) == ("keep", "already_protected")
    assert result.purchase_draft.item == "Wireless Earbuds" and result.purchase_draft.coverage


def test_switch_cash_draft_has_no_coverage():
    result = decide(cart(), wallet("apple-card", "wf-active-cash"))
    assert result.decision.reason == "cash" and result.purchase_draft.coverage == []
    assert result.sources and all(s.card_id == "wf-active-cash" for s in result.sources)


def test_add_months_clamps_to_the_month_end():
    assert engine.add_months(dt.date(2026, 1, 31), 1) == dt.date(2026, 2, 28)
    assert engine.add_months(dt.date(2026, 10, 17), 24) == dt.date(2028, 10, 17)


def test_draft_dates_past_year_9999_raise_date_out_of_range():
    """BE-5: a typed error the route turns into 400 bad_request, not an OverflowError (500)."""
    with pytest.raises(engine.DateOutOfRange):
        engine.add_months(dt.date(9999, 10, 1), 24)
    with pytest.raises(engine.DateOutOfRange):
        engine.add_days(dt.date(9999, 12, 31), 120)
    with pytest.raises(engine.DateOutOfRange):
        engine.decide("checkout", cart(), wallet("apple-card", "chase-freedom-unlimited"), dt.date(9999, 12, 31))


# --- §8.2 display rule ------------------------------------------------------------------------


S1_WALLET = ("apple-card", "wf-active-cash", "chase-freedom-unlimited")


def partial_base_rate(card_id: str):
    def edit(raw):
        next(c for c in raw["cards"] if c["id"] == card_id)["earn"]["baseRateStatus"] = "partial"
    return edit


def partial_protection(card_id: str, type_: str):
    def edit(raw):
        protection(raw, card_id, type_)["verification"]["status"] = "partial"
    return edit


def coverage_by_type(result) -> dict:
    return {entry.type: entry for entry in result.purchase_draft.coverage}


def test_shipped_catalog_s1_states_the_cap_and_the_cash_figure():
    result = decide(cart(), wallet(*S1_WALLET))
    assert result.decision.confidence == "high"
    assert result.decision.copy_.line2 == "Adds a warranty year + $500 theft cover"
    assert result.decision.copy_.line3 == "$7.49 less cash back than Active Cash"
    assert coverage_by_type(result)["purchase_protection"].limit_usd == 500


def test_unverified_cap_drops_from_the_copy_and_lowers_confidence():
    result = decide(cart(), wallet(*S1_WALLET),
                    catalog_with(partial_protection("chase-freedom-unlimited", "purchase_protection")))
    assert result.decision.confidence == "medium"
    assert result.decision.copy_.line2 == "Adds a warranty year + theft cover"
    assert result.decision.copy_.line3 == "$7.49 less cash back than Active Cash"  # both rates are verified
    # The Saved view would state the partial protection's window and cap as fact: no entry for it.
    assert set(coverage_by_type(result)) == {"extended_warranty"}


@pytest.mark.parametrize("card_id", ["wf-active-cash", "chase-freedom-unlimited"])
def test_medium_confidence_from_a_partial_rate_drops_the_verified_cap_and_the_cash_figure(card_id):
    """§8.2: a partial value used -> confidence medium -> no cap in the copy, and no partial figure as fact."""
    result = decide(cart(), wallet(*S1_WALLET), catalog_with(partial_base_rate(card_id)))
    d = result.decision
    assert (d.kind, d.reason, d.recommended_card_id, d.confidence) == (
        "switch", "protection", "chase-freedom-unlimited", "medium")
    assert d.copy_.line2 == "Adds a warranty year + theft cover"
    assert d.copy_.line3 == "Likely less cash back than Active Cash"
    by_type = coverage_by_type(result)
    assert by_type["purchase_protection"].limit_usd is None  # the Saved view drops the cap as line 2 does
    assert by_type["purchase_protection"].until == dt.date(2027, 2, 14)  # the protection itself is verified
    assert by_type["extended_warranty"].until == dt.date(2028, 10, 17)


def test_partial_extended_warranty_saves_no_warranty_dates():
    result = decide(cart(), wallet(*S1_WALLET),
                    catalog_with(partial_protection("chase-freedom-unlimited", "extended_warranty")))
    assert result.decision.confidence == "medium"
    assert result.decision.copy_.line2 == "Adds extra warranty + theft cover"
    assert set(coverage_by_type(result)) == {"purchase_protection"}
    assert coverage_by_type(result)["purchase_protection"].limit_usd is None


def test_pick_also_cash_best_with_a_partial_rate_is_hedged():
    result = decide(cart(), wallet("apple-card", "chase-freedom-unlimited"),
                    catalog_with(partial_base_rate("chase-freedom-unlimited")))
    assert result.decision.cash_best_card_id == "chase-freedom-unlimited"
    assert result.decision.copy_.line3 == "Likely also earns the most cash back here"


def test_keep_protected_with_a_partial_rate_drops_the_cap():
    result = decide(cart(), wallet("chase-freedom-unlimited", "wf-active-cash"),
                    catalog_with(partial_base_rate("wf-active-cash")))
    d = result.decision
    assert (d.kind, d.reason, d.confidence) == ("keep", "already_protected", "medium")
    assert d.copy_.line2 == "Adds a warranty year + theft cover"
    assert coverage_by_type(result)["purchase_protection"].limit_usd is None


def test_cash_switch_with_a_partial_rate_states_no_amount():
    result = decide(cart(), wallet("apple-card", "wf-active-cash"), catalog_with(partial_base_rate("wf-active-cash")))
    d = result.decision
    assert (d.kind, d.reason, d.confidence) == ("switch", "cash", "medium")
    assert d.copy_.line2 == "Likely more cash back than Apple Card"


def test_keep_method_with_a_partial_rate_states_no_rates():
    def partial_nike(raw):
        apple = next(c for c in raw["cards"] if c["id"] == "apple-card")
        next(r for r in apple["earn"]["rules"] if r["id"] == "apple-card-bonus-merchants")["status"] = "partial"

    nike = cart(items=(("Running Shoes", 180.0, "apparel", "new"),), merchant=("Nike", "nike"), options=("apple_pay",))
    d = decide(nike, wallet("apple-card"), catalog_with(partial_nike)).decision
    assert (d.kind, d.reason, d.confidence) == ("keep", "method", "medium")
    assert d.copy_.line2 == "Likely more cash back with Apple Pay"
    assert decide(nike, wallet("apple-card")).decision.copy_.line2 == "3% ($5.40) with Apple Pay vs 1% typed"


@pytest.mark.parametrize("other_id", catalog.card_ids())
@pytest.mark.parametrize("card_id", catalog.card_ids())
def test_hedged_cash_lines_fit_44_characters(card_id, other_id):
    card, other = catalog.card(card_id), catalog.card(other_id)
    lines = [copy.switch_protection(card, [], Decimal("-1"), other, "saved_card", cash_verified=False).line3,
             copy.switch_protection(card, [], Decimal("0"), other, "saved_card", cash_verified=False).line3,
             copy.switch_cash(card, Decimal("1"), other, [], "saved_card", cash_verified=False).line2,
             copy.keep_method(card, Decimal("2"), Decimal("1"), Decimal("1"), verified=False).line2]
    assert all(copy.filled_length(line) <= copy.LINE_MAX for line in lines), lines
    assert not any(ch.isdigit() or ch == "$" for line in lines for ch in line)


# --- Copy ----------------------------------------------------------------------------------------


@pytest.mark.parametrize("card_id", catalog.card_ids())
@pytest.mark.parametrize("path", ["apple_pay", "saved_card", "card_form", "unknown"])
def test_instruction_fits_48_characters(card_id, path):
    text = copy.instruction_text(catalog.card(card_id), path)
    assert copy.filled_length(text) <= copy.INSTRUCTION_MAX


def test_protection_line_variants():
    fu = catalog.card("chase-freedom-unlimited")
    pp, ew = fu.protection("purchase_protection"), fu.protection("extended_warranty")
    assert copy.protection_line([pp, ew]) == "Adds a warranty year + $500 theft cover"
    assert copy.protection_line([pp]) == "Adds $500 theft & damage cover"
    assert copy.protection_line([ew]) == "Adds a warranty year"
    unverified = pp.model_copy(update={"verification": pp.verification.model_copy(update={"status": "unverified"})})
    assert copy.protection_line([unverified, ew]) == "Adds a warranty year + theft cover"
    assert copy.protection_line([pp, ew], show_cap=False) == "Adds a warranty year + theft cover"
    assert copy.protection_line([pp], show_cap=False) == "Adds theft & damage cover"


def test_money_and_rate_formats():
    assert copy.usd(Decimal("7.49"), cents=True) == "$7.49"
    assert copy.usd(Decimal("1499"), cents=True) == "$1,499.00"
    assert copy.usd(Decimal("500")) == "$500"
    assert copy.usd(Decimal("5")) == "$5"
    assert copy.pct(Decimal("1.5")) == "1.5%" and copy.pct(Decimal("3")) == "3%"


def test_apple_pay_threshold_is_three_dollars():
    assert policy.CASH_SWITCH_MIN_USD["apple_pay"] == 3
    # Discover default (1%) vs Apple Card via Apple Pay (2%): $50 gains $0.50, $300 gains exactly $3.00.
    c = cart(items=(("Ceramic Coffee Mug", 50.0, "home", "new"),), options=("apple_pay",))
    d = decide(c, wallet("discover-it-student-cash-back", "apple-card")).decision
    assert (d.kind, d.reason) == ("keep", "below_threshold")  # gain 0.50 < $3
    big = cart(items=(("Ceramic Coffee Mug", 300.0, "home", "new"),), options=("apple_pay",))
    d = decide(big, wallet("discover-it-student-cash-back", "apple-card")).decision
    assert (d.kind, d.reason, d.instruction) == ("switch", "cash", "apple_pay_swipe")  # gain 3.00 >= $3
    assert d.copy_.instruction == "In Apple Pay, swipe to this card"
    assert d.copy_.line2 == "$3.00 more cash back than Discover"


# --- Privacy guard helpers ----------------------------------------------------------------------


@pytest.mark.parametrize(
    "text, rejected",
    [
        ("4" + "1" * 15, True),
        ("1234567890" + "12", True),
        ("Card " + " ".join(["4" + "1" * 3] + ["1" * 4] * 3), True),
        ("Card " + "-".join(["4" + "1" * 3] + ["1" * 4] * 3), True),
        ("Card " + " ".join(["4111"] + ["1" * 4] * 2 + ["1112"]), False),  # card-shaped but fails Luhn
        ("Order #112-3456789-1234567", False),
        ("2026-10-17 (555) 010-0000", False),
        ("12345678901", False),
    ],
)
def test_card_like_runs(text, rejected):
    assert middleware.has_card_like_run(text) is rejected


def test_luhn():
    assert middleware.luhn_ok("4" + "1" * 15)
    assert not middleware.luhn_ok("4" + "1" * 14 + "2")
