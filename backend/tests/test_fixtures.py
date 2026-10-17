"""fixtures/ (SPEC v2.1 §15.4, §15.7 step 3): shape tests only, no engine.

The fixtures are D's hand-computed expectations. These tests check their shape, that they match
the contracts and data/cards.json, and that each one still says what the §15.4 tables say: wallet,
kind, reason, card, the stated numbers, and each cart's price, category, condition, merchant and
payment buttons. cashByCard is recomputed from the data/cards.json rates (§7.2 rule 1 only).
They never run the engine: test_scenarios.py and test_coverage.py do that.
"""

import datetime as dt
import json
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator
from referencing import Registry
from referencing.jsonschema import DRAFT202012

from app.models import Cart, CoverageRequest

REPO = Path(__file__).resolve().parents[2]
FIXTURES = REPO / "fixtures"
CONTRACTS_DIR = REPO / "contracts"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


CATALOG = load(REPO / "data" / "cards.json")
CARDS = {card["id"]: card for card in CATALOG["cards"]}
MERCHANTS = {merchant["id"]: merchant for merchant in CATALOG["merchants"]}
CARD_IDS = set(CARDS)
MERCHANT_IDS = set(MERCHANTS)
CATEGORY_IDS = {category["id"] for category in CATALOG["itemCategories"]}

WALLETS = {wallet["id"]: wallet for wallet in load(FIXTURES / "wallets.json")["wallets"]}
SCENARIOS = load(FIXTURES / "scenarios.json")["scenarios"]
CASES = load(FIXTURES / "coverage_cases.json")["cases"]

# §15.4 screenshot list: one fixtures/ocr/<name>.txt and one fixtures/carts/<name>.json each.
SCREENSHOTS = {
    "laptop-checkout": "checkout",
    "laptop-renewed-checkout": "checkout",
    "earbuds-checkout": "checkout",
    "mug-checkout": "checkout",
    "laptop-confirmation": "order_confirmation",
    "feed-not-checkout": "not_checkout",
    "blurry-unreadable": "unreadable",
}

SCHEMAS = {p.name: load(p) for p in CONTRACTS_DIR.glob("*.schema.json")}
REGISTRY = Registry().with_resources(
    (name, DRAFT202012.create_resource(schema)) for name, schema in SCHEMAS.items()
)


def validator(ref: str) -> Draft202012Validator:
    return Draft202012Validator({"$ref": ref}, registry=REGISTRY, format_checker=Draft202012Validator.FORMAT_CHECKER)


CART_VALIDATOR = validator("check.response.schema.json#/$defs/cart")
COVERAGE_REQUEST_VALIDATOR = validator("coverage.request.schema.json")
SCREEN_TYPES = set(SCHEMAS["check.response.schema.json"]["$defs"]["result"]["properties"]["screenType"]["enum"])
DECISION = SCHEMAS["check.response.schema.json"]["$defs"]["decision"]["properties"]
KINDS, REASONS = set(DECISION["kind"]["enum"]), set(DECISION["reason"]["enum"])
PRESENTATIONS, PATHS = set(DECISION["presentation"]["enum"]), set(DECISION["paymentPath"]["enum"])
COVERAGE = SCHEMAS["coverage.response.schema.json"]["properties"]
VERDICTS, BENEFITS, ROUTES = (set(COVERAGE[key]["enum"]) for key in ("verdict", "benefit", "route"))
COUNTED_PROTECTIONS = ["purchase_protection", "extended_warranty"]  # §7.2 rule 3

AC, FU, RISE, APPLE, DISC = (
    "wf-active-cash", "chase-freedom-unlimited", "chase-freedom-rise", "apple-card", "discover-it-student-cash-back",
)

# §15.4 wallets table, verbatim.
SPEC_WALLETS = {
    "demo-3card": [(APPLE, "5678"), (AC, "4321"), (FU, "1234")],
    "apple-ac": [(APPLE, "5678"), (AC, "4321")],
    "no-protection": [(APPLE, "5678"), (DISC, "4321")],
    "rise-2card": [(APPLE, "5678"), (RISE, "1234")],
    "fu-default": [(FU, "1234"), (AC, "4321"), (APPLE, "5678")],
    "discover-fu": [(DISC, "4321"), (FU, "1234")],
    "rise-ac": [(RISE, "1234"), (AC, "4321")],
    "ac-apple": [(AC, "4321"), (APPLE, "5678")],
}

# §15.4 scenarios table: id -> (wallet, kind, reason, card the table names or None).
SPEC_SCENARIOS = {
    1: ("demo-3card", "switch", "protection", FU),
    2: ("demo-3card", "switch", "cash", AC),
    3: ("demo-3card", "switch", "protection", FU),
    4: ("demo-3card", "keep", "below_threshold", None),
    5: ("fu-default", "switch", "protection", FU),
    6: ("no-protection", "keep", "default_best", None),
    7: ("apple-ac", "switch", "cash", AC),
    8: ("demo-3card", "keep", "method", None),
    9: ("demo-3card", "keep", "below_threshold", None),
    10: ("demo-3card", "switch", "protection", FU),
    11: ("demo-3card", "keep", "below_threshold", None),
    12: ("demo-3card", "keep", "below_threshold", None),
    13: ("demo-3card", "no_checkout", "not_checkout", None),
    14: ("demo-3card", "no_checkout", "unreadable", None),
    15: ("demo-3card", "no_checkout", "already_paid", None),
    16: ("discover-fu", "switch", "protection", FU),
    17: ("rise-2card", "switch", "protection", RISE),
    18: ("demo-3card", "keep", "items_unreadable", None),
    19: ("demo-3card", "keep", "method", None),
    20: ("demo-3card", "keep", "below_threshold", None),
    21: ("rise-ac", "keep", "already_protected", None),
    22: ("fu-default", "switch", "protection", FU),
    23: ("fu-default", "keep", "already_protected", None),
    24: ("ac-apple", "switch", "cash", AC),
    25: ("fu-default", "keep", "already_protected", None),
    26: ("rise-ac", "keep", "already_protected", None),
    27: ("fu-default", "switch", "cash", AC),
    28: ("discover-fu", "keep", "below_threshold", None),
}

# Numbers the §15.4 table states: id -> (expected field, value).
SPEC_SCENARIO_NUMBERS = {
    1: ("cashDeltaVsCashBest", -7.49),  # "−$7.49 vs AC"
    2: ("cashDeltaVsDefault", 10.99),  # "+$10.99 vs Apple Card"
    3: ("cashDeltaVsCashBest", -1.24),  # "−$1.24 vs AC"
    7: ("cashDeltaVsDefault", 14.99),  # "+$14.99"
    9: ("cashDeltaVsCashBest", -1.80),  # "($1.80)": the cash-best gain the default keeps instead
    10: ("cashDeltaVsCashBest", -0.60),  # "−$0.60"
    21: ("cashDeltaVsCashBest", -6.00),  # "AC +$6.00 would otherwise switch"
    5: ("cashDeltaVsCashBest", -7.49),  # "−$7.49 vs AC"
    25: ("cashDeltaVsCashBest", -6.00),  # "AC +$6.00 would otherwise switch"
    26: ("cashDeltaVsCashBest", -7.50),  # "AC +$7.50 would otherwise switch"
    27: ("cashDeltaVsDefault", 6.00),  # "+$6.00"
    28: ("cashDeltaVsCashBest", -1.25),  # "FU +$1.25, partial"
}

# §15.4 scenarios table, "Cart / path" column: id -> (total, item category, item condition, merchant the
# table names or None). Each row is one item, quantity 1. A laptop with no price is the $1,499 laptop
# of the screenshot list. Where the row gives no category it is the obvious one: laptop computers,
# headphones audio, shoes apparel, Walgreens pharmacy.
SPEC_CARTS = {
    1: (1499.00, "computers", "new", None),
    2: (1099.00, "computers", "renewed", None),
    3: (249.00, "audio", "new", None),
    4: (18.00, "home", "new", None),
    5: (1499.00, "computers", "new", None),
    6: (1499.00, "computers", "new", None),
    7: (1499.00, "computers", "new", None),
    8: (180.00, "apparel", "new", "nike"),
    9: (180.00, "apparel", "new", "nike"),
    10: (120.00, "audio", "new", None),
    11: (90.00, "audio", "new", None),
    12: (100.00, "gift_card", "new", None),
    16: (1499.00, "computers", "new", None),
    17: (249.00, "audio", "new", None),
    18: (1499.00, "computers", "new", None),
    19: (40.00, "pharmacy", "new", "walgreens"),
    20: (38.00, "home", "new", "amazon"),
    21: (1200.00, "computers", "new", None),
    22: (1499.00, "computers", "new", None),
    23: (1499.00, "computers", "new", None),
    24: (1099.00, "computers", "renewed", None),
    25: (1200.00, "apparel", "new", "stride-athletics"),
    26: (1500.00, "home", "new", "target"),
    27: (1200.00, "grocery", "new", None),
    28: (249.00, "dining", "new", None),
}
APPLE_PAY_VISIBLE = {8, 19, 22}  # the only rows that say "Apple Pay visible"
SAVED_CARD = {1, 5, 20, 21, 23, 24, 25, 26, 27}  # rows that say "saved card" or name a selected card
CARD_FORM_ONLY = {9, 28}  # "card form only"

# §15.4 screenshot list: name -> (total, condition of its one item).
SPEC_SCREENSHOT_CARTS = {
    "laptop-checkout": (1499.00, "new"),
    "laptop-renewed-checkout": (1099.00, "renewed"),
    "earbuds-checkout": (249.00, "new"),
    "mug-checkout": (18.00, "new"),
    "laptop-confirmation": (1499.00, "new"),  # the order for the $1,499 laptop
}

# §15.4 coverage table: id -> (verdict, benefit or None if the table doesn't say, route or None, payout cap).
SPEC_CASES = {
    1: ("may_be_eligible", "extended_warranty", "card_extended_warranty", 1499.00),
    2: ("not_covered", "none", None, None),
    3: ("may_be_eligible", "purchase_protection", None, 500.00),
    4: ("may_be_eligible", "purchase_protection", None, 249.00),
    5: ("need_more_info", None, None, None),
    6: ("not_covered", "none", None, None),
    7: ("not_covered", None, "manufacturer", None),
    8: ("not_covered", None, None, None),
    9: ("not_covered", None, None, None),
    10: ("not_covered", None, None, None),
    11: ("not_covered", None, None, None),
    12: ("may_be_eligible", None, None, 1000.00),
    13: ("may_be_eligible", "purchase_protection", None, 500.00),
    14: ("not_covered", "none", None, None),
}

SCENARIO_KEYS = {"id", "title", "wallet", "paymentPath", "screenshot", "cart", "expected", "workings"}
SCENARIO_EXPECTED_KEYS = {
    "kind", "reason", "presentation", "recommendedCardId", "cashBestCardId", "cashByCard",
    "cashDeltaVsCashBest", "cashDeltaVsDefault", "protectionsGained", "eligibilityNotes",
}
CASE_KEYS = {"id", "title", "purchase", "incident", "asOf", "expected", "workings"}
CASE_EXPECTED_KEYS = {"verdict", "benefit", "route", "payoutCapUsd", "citesSection", "checklistIncludes"}


def without_screen_type(cart: dict) -> dict:
    return {key: value for key, value in cart.items() if key != "screenType"}


def cart_errors(cart: dict) -> list[str]:
    errors = [e.message for e in CART_VALIDATOR.iter_errors(without_screen_type(cart))]
    if cart.get("screenType") not in SCREEN_TYPES:
        errors.append(f"screenType {cart.get('screenType')!r}")
    return errors


def cents(value: float) -> int:
    return round(value * 100)


CENT = Decimal("0.01")


def usd(value: float) -> Decimal:
    return Decimal(str(value))


def rate_pct(card: dict, merchant_id: str | None, category: str | None, apple_pay: bool) -> Decimal:
    """§7.2 rule 1: merchant rule > category rule > base, among the rules the payment path allows.
    `category` is the known merchant's category; a rule that needs activation is never counted.

    A rule with neither merchants nor a category (Apple Card's 2% via Apple Pay) is the base rate for
    its payment method, so it beats baseRatePct.
    """
    method = "apple_pay" if apple_pay else "card"
    rules = [r for r in card["earn"]["rules"]
             if {"any", method} & set(r["paymentMethods"]) and not r["needsActivation"]]
    levels = (
        [r for r in rules if merchant_id is not None and merchant_id in (r["merchantIds"] or [])],
        [r for r in rules if r["merchantIds"] is None and r["category"] is not None and r["category"] == category],
        [r for r in rules if r["merchantIds"] is None and r["category"] is None],
    )
    for level in levels:
        if level:
            return max(usd(r["ratePct"]) for r in level)
    return usd(card["earn"]["baseRatePct"])


def cash_by_card(cart: dict, wallet: list[str], category: str | None) -> dict[str, Decimal]:
    """Cash per card on the cart total, rounded to cents half-up (§7.2 rule 1)."""
    merchant_id = cart["merchant"]["merchantId"]
    apple_pay = "apple_pay" in cart["paymentOptionsVisible"]
    total = usd(cart["totalUsd"])
    rates = {card_id: rate_pct(CARDS[card_id], merchant_id, category, apple_pay) for card_id in wallet}
    return {card_id: (total * rate / 100).quantize(CENT, ROUND_HALF_UP) for card_id, rate in rates.items()}


# ---------------------------------------------------------------- wallets


def test_eight_wallets_match_the_spec_table():
    assert {wid: [(c["cardId"], c["last4"]) for c in w["cards"]] for wid, w in WALLETS.items()} == SPEC_WALLETS


def test_wallet_cards_exist_in_cards_json():
    for wallet in WALLETS.values():
        assert {card["cardId"] for card in wallet["cards"]} <= CARD_IDS, wallet["id"]
        assert len({card["cardId"] for card in wallet["cards"]}) == len(wallet["cards"]), wallet["id"]


# ---------------------------------------------------------------- scenarios


def test_28_scenarios_in_order():
    assert [s["id"] for s in SCENARIOS] == list(range(1, 29))


def baseline(scenario: dict) -> str:
    """§7.2 baseline: the selected saved card when exactly one wallet card has its network, else the default."""
    wallet = [card["cardId"] for card in WALLETS[scenario["wallet"]]["cards"]]
    selected = scenario["cart"]["selectedPayment"]
    matches = [card_id for card_id in wallet if CARDS[card_id]["network"] == selected["network"]]
    if selected["kind"] == "saved_card" and len(matches) == 1:
        return matches[0]
    return wallet[0]


@pytest.mark.parametrize("scenario", SCENARIOS, ids=lambda s: f"s{s['id']}")
def test_scenario_shape(scenario):
    assert set(scenario) == SCENARIO_KEYS
    expected = scenario["expected"]
    assert set(expected) == SCENARIO_EXPECTED_KEYS
    assert scenario["wallet"] in WALLETS
    assert scenario["paymentPath"] in PATHS
    assert scenario["title"] and scenario["workings"]
    assert expected["kind"] in KINDS and expected["reason"] in REASONS
    assert expected["presentation"] in PRESENTATIONS
    assert set(expected["protectionsGained"]) <= set(COUNTED_PROTECTIONS)
    assert all(isinstance(note, str) and note for note in expected["eligibilityNotes"])


@pytest.mark.parametrize("scenario", SCENARIOS, ids=lambda s: f"s{s['id']}")
def test_scenario_cart_is_a_contract_cart(scenario):
    cart = scenario["cart"]
    assert cart_errors(cart) == []
    Cart.model_validate(without_screen_type(cart))
    assert cart["merchant"]["merchantId"] in MERCHANT_IDS | {None}
    assert {item["category"] for item in cart["items"]} <= CATEGORY_IDS


@pytest.mark.parametrize("scenario", SCENARIOS, ids=lambda s: f"s{s['id']}")
def test_scenario_matches_spec_table(scenario):
    wallet, kind, reason, named_card = SPEC_SCENARIOS[scenario["id"]]
    expected = scenario["expected"]
    assert (scenario["wallet"], expected["kind"], expected["reason"]) == (wallet, kind, reason)
    if kind == "switch":
        assert expected["recommendedCardId"] == named_card
    elif kind == "keep":
        assert expected["recommendedCardId"] == baseline(scenario)
    else:
        assert expected["recommendedCardId"] is None
    if scenario["id"] in SPEC_SCENARIO_NUMBERS:
        field, value = SPEC_SCENARIO_NUMBERS[scenario["id"]]
        assert cents(expected[field]) == cents(value)


@pytest.mark.parametrize("scenario", SCENARIOS, ids=lambda s: f"s{s['id']}")
def test_scenario_expectation_is_consistent(scenario):
    """Internal consistency of the hand computation (not the engine): cards, deltas, presentation."""
    expected = scenario["expected"]
    wallet_cards = [card["cardId"] for card in WALLETS[scenario["wallet"]]["cards"]]
    snippet = expected["kind"] == "switch" or expected["reason"] == "already_protected"
    assert expected["presentation"] == ("snippet" if snippet else "island")
    if expected["kind"] == "no_checkout":
        assert expected["cashByCard"] is None and expected["cashBestCardId"] is None
        assert expected["cashDeltaVsCashBest"] is None and expected["cashDeltaVsDefault"] is None
        assert scenario["cart"]["screenType"] != "checkout"
        return
    assert scenario["cart"]["screenType"] == "checkout"
    by_card = expected["cashByCard"]
    assert list(by_card) == wallet_cards
    assert all(cents(value) / 100 == value for value in by_card.values()), "cash is rounded to cents"
    best = expected["cashBestCardId"]
    assert by_card[best] == max(by_card.values())
    rec = expected["recommendedCardId"]
    assert rec in wallet_cards
    assert cents(expected["cashDeltaVsCashBest"]) == cents(by_card[rec]) - cents(by_card[best])
    assert cents(expected["cashDeltaVsDefault"]) == cents(by_card[rec]) - cents(by_card[wallet_cards[0]])
    if expected["kind"] == "keep":
        assert expected["protectionsGained"] == []


@pytest.mark.parametrize("scenario", [s for s in SCENARIOS if s["id"] in SPEC_CARTS], ids=lambda s: f"s{s['id']}")
def test_scenario_cart_matches_spec_table(scenario):
    sid, cart = scenario["id"], scenario["cart"]
    total, category, condition, merchant_id = SPEC_CARTS[sid]
    [item] = cart["items"]
    assert (cents(cart["totalUsd"]), item["quantity"]) == (cents(total), 1)
    assert (item["category"], item["condition"]) == (category, condition)
    assert (item["isGiftCard"], item["isServicePlan"]) == (category == "gift_card", False)
    if merchant_id is not None:
        assert cart["merchant"]["merchantId"] == merchant_id
    visible = cart["paymentOptionsVisible"]
    assert ("apple_pay" in visible) == (sid in APPLE_PAY_VISIBLE)
    if sid in SAVED_CARD:
        assert scenario["paymentPath"] == "saved_card"
    if sid in CARD_FORM_ONLY:
        assert visible == ["card_form"]


@pytest.mark.parametrize("scenario", [s for s in SCENARIOS if s["cart"]["screenType"] == "checkout"],
                         ids=lambda s: f"s{s['id']}")
def test_scenario_payment_path_follows_the_buttons(scenario):
    """§7.2 rule 1: the path is apple_pay when an Apple Pay button is visible, else a visible card path."""
    visible = scenario["cart"]["paymentOptionsVisible"]
    if "apple_pay" in visible:
        assert scenario["paymentPath"] == "apple_pay"
    else:
        assert scenario["paymentPath"] in set(visible) & {"saved_card", "card_form"}


@pytest.mark.parametrize("scenario", [s for s in SCENARIOS if s["expected"]["cashByCard"] is not None],
                         ids=lambda s: f"s{s['id']}")
def test_scenario_cash_follows_cards_json(scenario):
    """Recomputes cashByCard and cashBestCardId from data/cards.json rates (§7.2 rule 1), without the engine."""
    cart, expected = scenario["cart"], scenario["expected"]
    wallet = [card["cardId"] for card in WALLETS[scenario["wallet"]]["cards"]]
    merchant_id = cart["merchant"]["merchantId"]
    # §7.2 rule 1 (v2.5): a category rule counts only at a known merchant, against its catalog category.
    by_merchant = cash_by_card(cart, wallet, MERCHANTS[merchant_id]["category"] if merchant_id else None)
    assert {card_id: usd(value) for card_id, value in expected["cashByCard"].items()} == by_merchant
    best = max(by_merchant.values())
    # Ties go to the baseline, then the default (the first wallet card), then wallet order.
    order = [baseline(scenario), *wallet]
    assert expected["cashBestCardId"] == next(card_id for card_id in order if by_merchant[card_id] == best)


def test_scenario_specifics():
    by_id = {s["id"]: s for s in SCENARIOS}
    assert by_id[2]["expected"]["eligibilityNotes"] == ["Renewed: no card cover counted"]
    assert [by_id[i]["cart"]["screenType"] for i in (13, 14, 15)] == ["not_checkout", "unreadable", "order_confirmation"]
    unreadable = by_id[18]["cart"]
    assert unreadable["totalUsd"] is not None and unreadable["confidence"]["total"] >= 0.8
    assert unreadable["items"] == [] or unreadable["confidence"]["items"] < 0.8
    for sid in (8, 19, 22):  # "Apple Pay visible"
        assert "apple_pay" in by_id[sid]["cart"]["paymentOptionsVisible"]
        assert by_id[sid]["paymentPath"] == "apple_pay"
    for sid in (1, 3, 5, 10, 16, 17, 22):
        assert by_id[sid]["expected"]["protectionsGained"] == COUNTED_PROTECTIONS


@pytest.mark.parametrize("scenario", [s for s in SCENARIOS if s["screenshot"]], ids=lambda s: f"s{s['id']}")
def test_scenario_cart_matches_its_screenshot_cart(scenario):
    assert scenario["screenshot"] in SCREENSHOTS
    assert scenario["cart"] == load(FIXTURES / "carts" / f"{scenario['screenshot']}.json")


# ---------------------------------------------------------------- every cart (scenarios + screenshots)

ALL_CARTS = [(f"s{s['id']}", s["cart"]) for s in SCENARIOS] + [
    (name, load(FIXTURES / "carts" / f"{name}.json")) for name in sorted(SCREENSHOTS)
]


@pytest.mark.parametrize("name, cart", ALL_CARTS, ids=[name for name, _ in ALL_CARTS])
def test_cart_items_add_up_to_the_total(name, cart):
    """No fixture cart has tax or shipping, so the items sum to the total (§15.7 step 9 checks Σ items vs total)."""
    if cart["items"] and cart["totalUsd"] is not None:
        assert sum(usd(item["priceUsd"]) * item["quantity"] for item in cart["items"]) == usd(cart["totalUsd"])


@pytest.mark.parametrize("name, cart", ALL_CARTS, ids=[name for name, _ in ALL_CARTS])
def test_cart_merchant_agrees_with_cards_json(name, cart):
    merchant_id = cart["merchant"]["merchantId"]
    if merchant_id is None:
        assert cart["merchant"]["name"] is None
        return
    merchant = MERCHANTS[merchant_id]
    assert cart["merchant"]["name"] in merchant["names"]
    if "apple_pay" in cart["paymentOptionsVisible"]:
        assert merchant["acceptsApplePay"]["value"] is not False, f"{merchant_id} has no Apple Pay in data/cards.json"


# ---------------------------------------------------------------- screenshots: OCR text + carts


@pytest.mark.parametrize("name", sorted(SPEC_SCREENSHOT_CARTS))
def test_screenshot_cart_matches_spec_list(name):
    cart = load(FIXTURES / "carts" / f"{name}.json")
    text = (FIXTURES / "ocr" / f"{name}.txt").read_text(encoding="utf-8")
    total, condition = SPEC_SCREENSHOT_CARTS[name]
    [item] = cart["items"]
    assert (cents(cart["totalUsd"]), item["quantity"], item["condition"]) == (cents(total), 1, condition)
    if name == "laptop-checkout":  # "Aero 14 Laptop, new, $1,499.00, saved Mastercard ••5678"
        assert item["name"].startswith("Aero 14 Laptop")
        assert cart["selectedPayment"] == {"kind": "saved_card", "network": "mastercard"}
    if name == "laptop-renewed-checkout":
        assert "Renewed · no warranty" in text
    if name == "laptop-confirmation":
        assert "Order #NB-100234" in text


def test_every_screenshot_has_ocr_text_and_a_cart():
    assert {p.stem for p in (FIXTURES / "ocr").glob("*.txt")} == set(SCREENSHOTS)
    assert {p.stem for p in (FIXTURES / "carts").glob("*.json")} == set(SCREENSHOTS)


@pytest.mark.parametrize("name", sorted(SCREENSHOTS))
def test_screenshot_cart_is_a_contract_cart(name):
    cart = load(FIXTURES / "carts" / f"{name}.json")
    assert cart_errors(cart) == []
    Cart.model_validate(without_screen_type(cart))
    assert cart["screenType"] == SCREENSHOTS[name]
    assert cart["merchant"]["merchantId"] in MERCHANT_IDS | {None}
    assert {item["category"] for item in cart["items"]} <= CATEGORY_IDS


@pytest.mark.parametrize("name", sorted(n for n, t in SCREENSHOTS.items() if t in ("checkout", "order_confirmation")))
def test_ocr_text_holds_the_cart_total(name):
    cart = load(FIXTURES / "carts" / f"{name}.json")
    text = (FIXTURES / "ocr" / f"{name}.txt").read_text(encoding="utf-8")
    assert f"Total  ${cart['totalUsd']:,.2f}" in text
    assert "Northbay Electronics" in text or "NORTHBAY Electronics" in text


@pytest.mark.parametrize("name", ["feed-not-checkout", "blurry-unreadable"])
def test_non_checkout_ocr_has_no_readable_total(name):
    text = (FIXTURES / "ocr" / f"{name}.txt").read_text(encoding="utf-8")
    assert "$" not in text
    assert load(FIXTURES / "carts" / f"{name}.json")["totalUsd"] is None


# ---------------------------------------------------------------- coverage cases


def test_14_coverage_cases_in_order():
    assert [c["id"] for c in CASES] == list(range(1, 15))


def coverage_request(case: dict) -> dict:
    return {"purchase": case["purchase"], "incident": case["incident"], "asOf": case["asOf"]}


@pytest.mark.parametrize("case", CASES, ids=lambda c: f"c{c['id']}")
def test_coverage_case_shape(case):
    assert set(case) == CASE_KEYS
    assert set(case["expected"]) == CASE_EXPECTED_KEYS
    assert [e.message for e in COVERAGE_REQUEST_VALIDATOR.iter_errors(coverage_request(case))] == []
    CoverageRequest.model_validate(coverage_request(case))
    purchase, incident, expected = case["purchase"], case["incident"], case["expected"]
    assert purchase["cardId"] in CARD_IDS and purchase["category"] in CATEGORY_IDS
    assert purchase["purchaseDate"] == "2026-10-17"
    assert incident["causeSource"] == "user_confirmed"
    assert dt.date.fromisoformat(case["asOf"]) == dt.date.fromisoformat(incident["date"]) + dt.timedelta(days=1)
    assert expected["verdict"] in VERDICTS and expected["benefit"] in BENEFITS and expected["route"] in ROUTES
    if expected["verdict"] != "may_be_eligible":
        assert expected["payoutCapUsd"] is None
    else:
        on_card = purchase["amountOnCardUsd"] if purchase["paidWith"] == "card_partial" else purchase["priceUsd"]
        assert 0 < expected["payoutCapUsd"] <= on_card


@pytest.mark.parametrize("case", CASES, ids=lambda c: f"c{c['id']}")
def test_coverage_case_matches_spec_table(case):
    verdict, benefit, route, cap = SPEC_CASES[case["id"]]
    expected = case["expected"]
    assert expected["verdict"] == verdict
    assert benefit is None or expected["benefit"] == benefit
    assert route is None or expected["route"] == route
    assert expected["payoutCapUsd"] == cap


@pytest.mark.parametrize("case", CASES, ids=lambda c: f"c{c['id']}")
def test_coverage_case_cites_a_section_in_cards_json(case):
    """§13 and §15.7 step 12b: every verdict cites a section and a version date."""
    section = case["expected"]["citesSection"]
    card = CARDS[case["purchase"]["cardId"]]
    counted = [p["source"] for p in card["protections"] if p["type"] in COUNTED_PROTECTIONS]
    # A card with neither benefit cites the dated card source that shows the absence.
    citable = counted or [s for s in card["sources"] if s["versionDate"] is not None]
    cited = [s for s in citable if s["section"] == section]
    assert section is not None and cited, f"{section!r} is not a citable section of {card['id']}"
    assert all(s["versionDate"] is not None for s in cited)


def test_coverage_specifics():
    by_id = {c["id"]: c for c in CASES}
    assert by_id[8]["purchase"]["manufacturerWarrantyMonths"] == 0
    assert by_id[8]["purchase"]["condition"] == "renewed"
    assert by_id[14]["purchase"]["manufacturerWarrantyMonths"] == 0  # groceries have no maker's warranty
    assert by_id[14]["purchase"]["category"] == "grocery"
    assert all(c["purchase"]["manufacturerWarrantyMonths"] == 12 for i, c in by_id.items() if i not in (8, 14))
    assert by_id[12]["purchase"]["paidWith"] == "card_partial"
    assert by_id[12]["purchase"]["amountOnCardUsd"] == 1000.00
    assert all(c["purchase"]["paidWith"] == "card_full" for i, c in by_id.items() if i != 12)
    assert "police report" in by_id[4]["expected"]["checklistIncludes"]
    assert {by_id[i]["purchase"]["cardId"] for i in (6, 10)} == {APPLE, AC}
