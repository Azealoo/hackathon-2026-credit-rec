"""Advice correctness fixes from the Oct 17, 2026 product review (SPEC v2.4 §7.2, §5.5).

One block per review item. Each test reproduced its issue on 6960a66 before the fix.
"""

import datetime as dt
import json
from decimal import Decimal
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import catalog, copy, engine, middleware, parser_rules
from app.catalog import CARDS_FILE, SCHEMA_FILE, CatalogError, load_catalog
from app.main import app
from app.models import Cart, WalletCard

REPO = Path(__file__).resolve().parents[2]
FIXTURES = REPO / "fixtures"
DAY = dt.date(2026, 10, 17)
AC, FU, RISE, APPLE, DISC = (
    "wf-active-cash", "chase-freedom-unlimited", "chase-freedom-rise", "apple-card", "discover-it-student-cash-back",
)
NORTHBAY = ("Northbay Electronics", "northbay-electronics")
LAPTOP = ("Aero 14 Laptop, 14-inch", 1499.0, "computers", "new")
RENEWED_LAPTOP = ("Aero 14 Laptop, 14-inch", 1099.0, "computers", "renewed")

client = TestClient(app)


def wallet(*card_ids: str) -> list[WalletCard]:
    return [WalletCard(card_id=card_id, is_default=i == 0) for i, card_id in enumerate(card_ids)]


def cart(items, merchant=NORTHBAY, options=("saved_card",), network="unknown") -> Cart:
    """A checkout cart. `network` is the selected saved card's network ("unknown" = the screen doesn't say)."""
    item_list = [{"name": n, "priceUsd": p, "quantity": 1, "category": c, "condition": cond, "seller": "merchant",
                  "isGiftCard": c == "gift_card", "isServicePlan": c == "services"} for n, p, c, cond in items]
    kind = "saved_card" if "saved_card" in options else "card_form" if "card_form" in options else "unknown"
    return Cart.model_validate({
        "merchant": {"name": merchant[0], "merchantId": merchant[1]}, "items": item_list,
        "totalUsd": sum(i["priceUsd"] for i in item_list), "currency": "USD", "paymentOptionsVisible": list(options),
        "selectedPayment": {"kind": kind, "network": network if kind == "saved_card" else "unknown"},
        "upsells": {"protectionPlanUsd": None}, "bnplVisible": False,
        "confidence": {"merchant": 0.97, "total": 0.98, "items": 0.92}})


def decide(c: Cart, w: list[WalletCard]) -> engine.EngineResult:
    return engine.decide("checkout", c, w, DAY)


# --- 1. Keep answers ignore the card selected on screen ----------------------------------------


@pytest.fixture
def rules_parser(monkeypatch):
    monkeypatch.setenv("PARSER_MODE", "rules")
    middleware.LIMITER.reset()
    yield
    middleware.LIMITER.reset()


def check(ocr_name: str, wallet_id: str) -> dict:
    wallets = {w["id"]: w for w in json.loads((FIXTURES / "wallets.json").read_text(encoding="utf-8"))["wallets"]}
    body = {
        "requestId": "5f0c0000-aaaa-4bbb-8ccc-ddddeeeeffff",
        "client": {"app": "paywise-ios", "version": "0.1.0"},
        "clientDate": "2026-10-17",
        "screen": {"ocrText": (FIXTURES / "ocr" / f"{ocr_name}.txt").read_text(encoding="utf-8"),
                   "redactions": ["card_number", "address", "email", "phone"], "ocrConfidence": 0.93},
        "wallet": {"cards": [{"cardId": c["cardId"], "isDefault": i == 0}
                             for i, c in enumerate(wallets[wallet_id]["cards"])]},
        "prefs": {"paysInFull": None},
    }
    response = client.post("/v1/check", json=body)
    assert response.status_code == 200, response.text
    return response.json()


def test_freedom_default_with_apple_cards_mastercard_on_screen_is_told_to_change_card(rules_parser):
    """The review's probe: fu-default + laptop-checkout.txt (Mastercard selected, which is Apple Card here)."""
    data = check("laptop-checkout", "fu-default")
    d = data["decision"]
    assert (d["kind"], d["reason"], d["recommendedCardId"], d["defaultCardId"]) == ("switch", "protection", FU, FU)
    assert d["instruction"] == "change_saved_card"
    assert d["copy"]["line1"] == "Use Freedom ••{last4:chase-freedom-unlimited}"
    assert d["copy"]["instruction"] == "Change card to Visa ••{last4:chase-freedom-unlimited}, then place order"
    # The draft is the Switch's: saved only when the user taps [Paying with Freedom].
    assert data["purchaseDraft"]["cardId"] == FU and d["copy"]["primaryButton"] == "Paying with Freedom"


@pytest.mark.parametrize(
    "network, baseline_is_default",
    [("mastercard", False),  # only Apple Card is a Mastercard
     ("visa", True),         # Freedom or Active Cash: can't tell, so the default
     ("discover", True),     # no wallet card is a Discover card
     ("unknown", True)],
)
def test_baseline_is_the_selected_card_only_when_its_network_names_one_wallet_card(network, baseline_is_default):
    d = decide(cart((LAPTOP,), network=network), wallet(FU, AC, APPLE)).decision
    if baseline_is_default:
        assert (d.kind, d.reason, d.recommended_card_id) == ("keep", "already_protected", FU)
    else:
        assert (d.kind, d.reason, d.recommended_card_id) == ("switch", "protection", FU)


def test_cash_best_tie_goes_to_the_selected_card():
    """Apple Pay path: Apple Card (selected) and Active Cash both earn 2%; the tie names the card on screen."""
    ap = cart((LAPTOP,), merchant=("Best Buy", "best-buy"), options=("apple_pay", "saved_card"), network="mastercard")
    d = decide(ap, wallet(FU, AC, APPLE)).decision
    assert (d.kind, d.reason, d.recommended_card_id, d.cash_best_card_id) == ("switch", "protection", FU, APPLE)
    assert d.copy_.line3 == "$7.49 less cash back than Apple Card"
    assert d.instruction == "apple_pay_swipe"


def selected(text: str):
    return parser_rules.parse(text).cart.selected_payment


CHECKOUT = "Gadget Hut\nCheckout\nWireless Mouse  $40.00\nTotal  $40.00\n{payment}\nPlace order"


def test_parser_reads_the_card_line_marked_selected():
    payment = "Pay with\nVisa [CARD]\nMastercard [CARD]  Selected"
    assert selected(CHECKOUT.format(payment=payment)).model_dump() == {"kind": "saved_card", "network": "mastercard"}
    payment = "Pay with\n✓ Discover [CARD]\nVisa [CARD]"
    assert selected(CHECKOUT.format(payment=payment)).network == "discover"
    payment = "Pay with\nVisa [CARD]  Default\nMastercard [CARD]"  # nothing else marked: the default card
    assert selected(CHECKOUT.format(payment=payment)).network == "visa"
    payment = "Pay with\nVisa [CARD]  Default\n✓ Mastercard [CARD]"  # a check beats "Default"
    assert selected(CHECKOUT.format(payment=payment)).network == "mastercard"


def test_parser_leaves_the_network_unknown_when_card_lines_disagree_and_none_is_marked():
    payment = "Pay with\nVisa [CARD]\nMastercard [CARD]"
    assert selected(CHECKOUT.format(payment=payment)).model_dump() == {"kind": "saved_card", "network": "unknown"}
    payment = "Pay with\nVisa [CARD]\nVisa [CARD]"  # two Visas: the network is still known
    assert selected(CHECKOUT.format(payment=payment)).network == "visa"


# --- 9. Cash-only Keeps ignore the selected card -----------------------------------------------


def test_active_cash_default_with_apple_card_on_screen_switches_back_to_active_cash():
    d = decide(cart((RENEWED_LAPTOP,), network="mastercard"), wallet(AC, APPLE)).decision
    assert (d.kind, d.reason, d.recommended_card_id, d.instruction) == ("switch", "cash", AC, "change_saved_card")
    assert d.copy_.line2 == "$10.99 more cash back than Apple Card"
    assert d.cash.delta_vs_default == 0.0


def test_small_gain_keeps_the_card_on_screen():
    mug = cart((("Ceramic Coffee Mug, 12 oz", 18.0, "home", "new"),), network="mastercard")
    d = decide(mug, wallet(AC, APPLE)).decision
    assert (d.kind, d.reason, d.recommended_card_id) == ("keep", "below_threshold", APPLE)
    assert d.copy_.line1 == "✓ Keep Apple Card ••{last4:apple-card}"


# --- 2. Cash switches silently drop purchase protection ----------------------------------------


@pytest.mark.parametrize(
    "items, card_ids",
    [((("Wool Jacket", 1200.0, "apparel", "new"),), (FU, AC, APPLE)),
     ((("Gold Necklace", 2000.0, "general", "new"),), (FU, AC, APPLE)),
     ((("Three-Seat Sofa", 1500.0, "home", "new"),), (RISE, AC)),
     (tuple(("Cotton Tee", 99.0, "apparel", "new") for _ in range(12)), (FU, AC))],  # every item under $100
    ids=["jacket", "necklace", "sofa", "twelve-tees"],
)
def test_cash_switch_never_drops_cover_the_baseline_has(items, card_ids):
    result = decide(cart(items, network="visa"), wallet(*card_ids))
    d = result.decision
    assert (d.kind, d.reason, d.recommended_card_id) == ("keep", "already_protected", card_ids[0])
    assert d.presentation == "snippet"
    assert d.copy_.line2 == "Adds $500 theft & damage cover"
    assert [c.type for c in result.purchase_draft.coverage] == ["purchase_protection"]


def test_keep_draft_saves_the_item_its_copy_is_about():
    """A pricier jacket that only purchase protection covers doesn't displace the earbuds the copy names."""
    two = cart((("Wool Jacket", 1200.0, "apparel", "new"), ("Wireless Earbuds", 249.0, "audio", "new")), network="visa")
    result = decide(two, wallet(FU, AC, APPLE))
    assert (result.decision.kind, result.decision.reason) == ("keep", "already_protected")
    assert result.decision.copy_.line2 == "Adds a warranty year + $500 theft cover"
    assert result.purchase_draft.item == "Wireless Earbuds"
    assert [c.type for c in result.purchase_draft.coverage] == ["purchase_protection", "extended_warranty"]


def test_excluded_category_still_switches_for_cash():
    groceries = cart((("Weekly Groceries", 1200.0, "grocery", "new"),), merchant=(None, None), network="visa")
    d = decide(groceries, wallet(FU, AC, APPLE)).decision
    assert (d.kind, d.reason, d.recommended_card_id) == ("switch", "cash", AC)
    assert d.protections_lost == []


CARTS = [cart((LAPTOP,)), cart((RENEWED_LAPTOP,)), cart((("Wool Jacket", 1200.0, "apparel", "new"),)),
         cart((("Ceramic Coffee Mug, 12 oz", 18.0, "home", "new"), ("Wireless Earbuds", 249.0, "audio", "new"))),
         cart((("Weekly Groceries", 1200.0, "grocery", "new"),), merchant=(None, None))]
WALLETS = [(APPLE, AC, FU), (FU, AC, APPLE), (RISE, AC), (AC, FU), (DISC, FU), (AC, RISE, APPLE)]


@pytest.mark.parametrize("card_ids", WALLETS)
@pytest.mark.parametrize("c", CARTS)
def test_no_answer_drops_cover(c, card_ids):
    d = decide(c, wallet(*card_ids)).decision
    assert d.protections_lost == []


# --- 3. Discover's Q4 2026 dining shown as a verified 1% ---------------------------------------
# SPEC v2.3 (offers, D1-D4) holds Discover's activated Q4 5% as a device offer the phone applies; the server
# states the public 1%, hedges a rate it can only guess, and lets the phone move cash decisions.

DOORDASH = ("DoorDash", "doordash")
RESTAURANT = ("Luigi's Trattoria", None)  # not in the catalog
DINNER = (("Dinner for Four", 249.0, "dining", "new"),)


def test_discover_q4_dining_is_an_offer_the_phone_applies():
    offer = next(o for o in catalog.CATALOG.offers if o.id == "discover-5pct-2026q4")
    assert (offer.card_ids, offer.evaluation, offer.reward.rate_pct) == ((DISC,), "device", 5)
    assert "dining" in offer.match.categories and "doordash" in offer.match.exclude_merchant_ids
    assert [r.kind for r in offer.requires] == ["activation"]
    assert not any(r.needs_activation for card in catalog.CATALOG.cards for r in card.earn.rules)
    assert engine.earn_rate(catalog.card(DISC), "doordash", "dining", "card", DAY) == engine.Rate(
        Decimal("1"), "verified")


def test_discover_default_at_an_unknown_restaurant_hedges_and_lets_the_phone_decide():
    result = decide(cart(DINNER, merchant=RESTAURANT, options=("card_form",)), wallet(DISC, FU))
    d = result.decision
    assert (d.kind, d.reason, d.recommended_card_id, d.confidence) == ("keep", "below_threshold", DISC, "medium")
    assert d.copy_.line2 == "Switching likely gains under $5 here"
    context = result.offer_context
    assert (context.rule_category, context.device_may_override) == ("dining", True)  # Discover's offer can match
    assert context.allowed_cash_picks == [DISC, FU]
    assert context.public_rates[FU].status == "partial"


def test_default_best_with_a_guessed_rate_says_likely():
    d = decide(cart(DINNER, merchant=RESTAURANT), wallet(FU, DISC)).decision
    assert (d.kind, d.reason, d.confidence) == ("keep", "default_best", "medium")
    assert d.copy_.line2 == "Likely best of your 2 cards here"


def test_doordash_is_outside_discovers_q4_offer_so_the_cash_switch_states_its_figure():
    d = decide(cart(DINNER, merchant=DOORDASH, options=("apple_pay", "card_form")), wallet(DISC, FU)).decision
    assert (d.kind, d.reason, d.recommended_card_id, d.confidence) == ("switch", "cash", FU, "high")
    assert d.copy_.line2 == "$4.98 more cash back than Discover"


def test_an_earn_rule_never_needs_activation(tmp_path):
    raw = json.loads(CARDS_FILE.read_text(encoding="utf-8"))
    next(c for c in raw["cards"] if c["id"] == FU)["earn"]["rules"][0]["needsActivation"] = True
    cards = tmp_path / "cards.json"
    cards.write_text(json.dumps(raw), encoding="utf-8")
    with pytest.raises(CatalogError):
        load_catalog(cards, SCHEMA_FILE)


@pytest.mark.parametrize("size", [1, 2, 5])
def test_hedged_keep_lines_fit_44_characters(size):
    card = catalog.card(FU)
    assert copy.filled_length(copy.keep_default_best(card, size, verified=False).line2) <= copy.LINE_MAX
    assert copy.filled_length(copy.keep_below_threshold(card, Decimal("5"), verified=False).line2) <= copy.LINE_MAX


# --- 7. Freedom's 3% dining / drugstore applied at unknown stores -------------------------------


def test_category_rule_counts_only_at_a_known_merchant():
    freedom = catalog.card(FU)
    assert engine.earn_rate(freedom, "walgreens", "pharmacy", "card") == engine.Rate(
        Decimal("3"), "verified", "cfu-drugstores")
    assert engine.earn_rate(freedom, None, None, "card", guess_category="pharmacy") == engine.Rate(
        Decimal("1.5"), "partial")
    assert engine.earn_rate(freedom, None, None, "card", guess_category="computers") == engine.Rate(
        Decimal("1.5"), "verified")


def test_skincare_at_an_unknown_store_does_not_switch_to_freedom():
    skincare = cart((("Skincare Set", 600.0, "pharmacy", "new"),), merchant=("Glow Beauty", None))
    d = decide(skincare, wallet(AC, FU)).decision
    assert (d.kind, d.reason, d.recommended_card_id) == ("keep", "default_best", AC)
    assert d.copy_.line2 == "Likely best of your 2 cards here"
    assert d.cash.by_card[FU] == 9.0


# --- 8. "Renewed, no warranty" for every refurbished item ---------------------------------------


def test_renewed_note_claims_nothing_the_screen_may_not_say():
    d = decide(cart((RENEWED_LAPTOP,)), wallet(APPLE, AC, FU)).decision
    assert (d.kind, d.reason) == ("switch", "cash")
    assert d.eligibility_notes == ["Renewed: no card cover counted"]
    assert d.copy_.line3 == "Renewed: no card cover counted"


# --- 6. A standalone brand line read as the store -----------------------------------------------


@pytest.mark.parametrize(
    "text, store",
    [("Gadget Hut\nCheckout\nMacBook Air 13-inch  $1,099.00\nApple\nNew\nTotal  $1,099.00\n"
      "Pay with Visa [CARD]\nPlace order", "Gadget Hut"),
     ("Shoe Barn\nYour bag\nRunning Shoes  $180.00\nNike\nQty 1\nTotal  $180.00\nPay with Visa [CARD]\nPlace order",
      "Shoe Barn")],
)
def test_brand_line_under_an_item_is_not_the_store(text, store):
    merchant = parser_rules.parse(text).cart.merchant
    assert (merchant.name, merchant.merchant_id) == (store, None)


def test_store_name_above_the_items_is_still_read():
    text = "Nike\nCheckout\nRunning Shoes  $180.00\nTotal  $180.00\nPay with Visa [CARD]\nPlace order"
    assert parser_rules.parse(text).cart.merchant.merchant_id == "nike"


# --- 4, 5. "Can I claim?" -----------------------------------------------------------------------


def claim(category: str, cause: str, incident: str, item: str = "Weekly Groceries", maker_months: int = 0) -> dict:
    day = dt.date.fromisoformat(incident)
    return {
        "purchase": {"cardId": FU, "merchant": "Harbor Market", "item": item, "category": category,
                     "condition": "new", "priceUsd": 300.0, "purchaseDate": "2026-10-17", "status": "confirmed",
                     "manufacturerWarrantyMonths": maker_months, "manufacturerWarrantySource": "user",
                     "paidWith": "card_full", "amountOnCardUsd": None},
        "incident": {"date": incident, "description": "It happened.", "cause": cause, "causeSource": "user_confirmed"},
        "asOf": (day + dt.timedelta(days=1)).isoformat(),
    }


def coverage_verdict(body: dict) -> dict:
    response = client.post("/v1/coverage", json=body)
    assert response.status_code == 200, response.text
    return response.json()


@pytest.mark.parametrize(
    "category, cause, incident, maker_months",
    [("grocery", "theft", "2026-10-27", 0), ("dining", "accidental_damage", "2026-10-27", 0),
     ("gift_card", "theft", "2026-10-27", 0), ("travel", "loss", "2026-10-27", 0),
     ("pharmacy", "cosmetic", "2026-10-27", 0), ("services", "theft", "2026-10-27", 0),
     ("pharmacy", "failure", "2027-12-17", 12)],
)
def test_claim_on_a_category_chase_excludes_is_not_covered(category, cause, incident, maker_months):
    data = coverage_verdict(claim(category, cause, incident, maker_months=maker_months))
    assert (data["verdict"], data["benefit"]) == ("not_covered", "none")
    assert "doesn't cover" in data["why"]


def test_jacket_theft_may_be_covered():
    data = coverage_verdict(claim("apparel", "theft", "2026-11-16", item="Wool Jacket"))
    assert (data["verdict"], data["benefit"]) == ("may_be_eligible", "purchase_protection")


def test_purchase_protection_verdicts_say_it_is_secondary():
    secondary = "It's secondary: it pays after any other insurance you have."
    theft = coverage_verdict(claim("apparel", "theft", "2026-11-16", item="Wool Jacket"))
    assert theft["why"].endswith(secondary)
    lost = coverage_verdict(claim("apparel", "loss", "2026-11-16", item="Wool Jacket"))
    assert (lost["verdict"], lost["benefit"]) == ("need_more_info", "purchase_protection")
    assert lost["why"].endswith(secondary)
    warranty = coverage_verdict(claim("electronics", "failure", "2027-12-17", item="Aero 14 Laptop", maker_months=12))
    assert warranty["benefit"] == "extended_warranty" and "secondary" not in warranty["why"]


def test_basis_comes_from_cards_json():
    for card in catalog.CATALOG.cards:
        for protection in card.protections:
            expected = "secondary" if card.id in (FU, RISE) and protection.type == "purchase_protection" else None
            assert protection.basis == expected, (card.id, protection.type)
