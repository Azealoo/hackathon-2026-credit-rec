"""data/cards.json against data/cards.schema.json and SPEC.md §15.3, and app/catalog.py (§15.7 step 2)."""

import datetime as dt
import json
from decimal import Decimal
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator

from app import catalog
from app.catalog import CatalogError, load_catalog

DATA = Path(__file__).resolve().parents[2] / "data"
WALLETS = Path(__file__).resolve().parents[2] / "fixtures" / "wallets.json"

# SPEC.md §8.1, §8.3 and §15.3.
V1_CARD_IDS = {
    "apple-card", "wf-active-cash", "chase-freedom-unlimited", "chase-freedom-rise", "discover-it-student-cash-back",
}
V1_MERCHANT_IDS = {
    "northbay-electronics", "stride-athletics", "nike", "amazon", "target",
    "best-buy", "walgreens", "doordash", "apple", "walmart",
}
RELEVANT_CATEGORIES = {
    "electronics", "computers", "phones", "audio", "cameras", "appliances", "tools", "bikes", "instruments",
}
OTHER_CATEGORIES = {
    "apparel", "home", "dining", "grocery", "pharmacy", "gift_card", "services", "travel", "general",
}


def load(name: str):
    return json.loads((DATA / name).read_text(encoding="utf-8"))


CATALOG = load("cards.json")


def test_cards_json_matches_schema():
    schema = load("cards.schema.json")
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema, format_checker=Draft202012Validator.FORMAT_CHECKER)
    assert [f"{list(e.absolute_path)}: {e.message}" for e in validator.iter_errors(CATALOG)] == []


def test_ids_are_unique():
    for key in ("cards", "merchants", "itemCategories"):
        ids = [entry["id"] for entry in CATALOG[key]]
        assert len(ids) == len(set(ids)), key
    rule_ids = [rule["id"] for card in CATALOG["cards"] for rule in card["earn"]["rules"]]
    assert len(rule_ids) == len(set(rule_ids))


def test_v1_content():
    assert {card["id"] for card in CATALOG["cards"]} == V1_CARD_IDS
    assert V1_MERCHANT_IDS <= {merchant["id"] for merchant in CATALOG["merchants"]}
    flags = {c["id"]: (c["warrantyRelevant"], c["theftDamageRelevant"]) for c in CATALOG["itemCategories"]}
    assert flags == {c: (True, True) for c in RELEVANT_CATEGORIES} | {c: (False, False) for c in OTHER_CATEGORIES}


def test_references_resolve():
    merchant_ids = {merchant["id"] for merchant in CATALOG["merchants"]}
    category_ids = {category["id"] for category in CATALOG["itemCategories"]}
    for merchant in CATALOG["merchants"]:
        assert merchant["category"] in category_ids, merchant["id"]
    for card in CATALOG["cards"]:
        for rule in card["earn"]["rules"]:
            assert rule["category"] is None or rule["category"] in category_ids, rule["id"]
            assert set(rule["merchantIds"] or []) <= merchant_ids, rule["id"]
        for protection in card["protections"]:
            assert set(protection["eligibility"]["excludedCategories"]) <= category_ids, card["id"]


# --- app/catalog.py (SPEC.md §15.7 step 2) ----------------------------------------------------

CHASE_CARDS = ("chase-freedom-unlimited", "chase-freedom-rise")
# Demo cards: every card in fixtures/wallets.json, the 7 demo wallets (§15.2, §15.4).
DEMO_CARDS = {
    card["cardId"] for wallet in json.loads(WALLETS.read_text(encoding="utf-8"))["wallets"] for card in wallet["cards"]
}
NO_PP_EW_CARDS = ("apple-card", "wf-active-cash", "discover-it-student-cash-back")
COUNTED_TYPES = ("purchase_protection", "extended_warranty")  # §7.2 rule 3

# docs/design.md §6: first stop of each card's gradient.
ART_COLORS = {
    "chase-freedom-unlimited": "#3f7ff0", "apple-card": "#fbfbfc", "wf-active-cash": "#ef6a5b",
    "chase-freedom-rise": "#35b6a8", "discover-it-student-cash-back": "#f6a54a",
}


def test_catalog_module_loads_the_file():
    assert catalog.card_ids() == [card["id"] for card in CATALOG["cards"]]
    assert catalog.CATALOG.catalog_version == dt.date.fromisoformat(CATALOG["catalogVersion"])
    assert {m.id for m in catalog.CATALOG.merchants} == {m["id"] for m in CATALOG["merchants"]}


def test_app_startup_loads_the_catalog():
    import app.main

    assert app.main.catalog.CATALOG is catalog.CATALOG


def test_short_names():
    assert {card_id: catalog.card(card_id).short_name for card_id in catalog.card_ids()} == {
        "apple-card": "Apple Card",
        "wf-active-cash": "Active Cash",
        "chase-freedom-unlimited": "Freedom",
        "chase-freedom-rise": "Freedom Rise",
        "discover-it-student-cash-back": "Discover",
    }


def test_every_protection_has_limits_source_and_verification():
    protections = [(card, p) for card in catalog.CATALOG.cards for p in card.protections]
    assert protections
    for card, p in protections:
        where = f"{card.id} {p.type}"
        assert p.limits.applies_to in ("item", "claim"), where
        amount = p.limits.per_item_usd if p.limits.applies_to == "item" else p.limits.per_claim_usd
        assert amount is not None and amount > 0, where
        assert p.source.document and p.source.section and p.source.url and p.source.quote, where
        assert p.source.version_date is not None, where
        assert p.verification.checked_by and p.verification.checked_on, where


def test_demo_card_protections_are_verified():
    """§15.7 step 2: every protection on a demo card is `verified`, cell phone protection included
    (§8.2 display rule; G5 checks Active Cash too)."""
    assert DEMO_CARDS == V1_CARD_IDS
    protections = [(card.id, p) for card in catalog.CATALOG.cards if card.id in DEMO_CARDS for p in card.protections]
    assert {card_id for card_id, _ in protections} == {*CHASE_CARDS, "wf-active-cash"}
    for card_id, p in protections:
        assert p.verification.status == "verified", f"{card_id} {p.type}"


def test_chase_protection_terms():
    for card_id in CHASE_CARDS:
        card = catalog.card(card_id)
        pp, ew = card.protection("purchase_protection"), card.protection("extended_warranty")
        assert pp is not None and ew is not None, card_id
        assert pp.limits.per_item_usd == 500 and pp.limits.applies_to == "item", card_id
        assert pp.window_days == 120 and pp.window_days_by_state == {"NY": 90}, card_id
        months = (ew.extends_by_months, ew.max_original_warranty_months, ew.max_total_from_purchase_months)
        assert months == (12, 36, 48), card_id
        assert ew.limits.per_item_usd == 10000, card_id
        for p in (pp, ew):
            assert (p.notice.notify_within_days, p.notice.submit_docs_within_days) == (90, 120), card_id
            assert p.eligibility.conditions_allowed == ("new",), card_id
            assert p.eligibility.payment_requirement == "some_portion", card_id
            assert p.source.version_date == dt.date(2024, 10, 1), card_id
        assert set(pp.covers) == {"theft", "accidental_damage", "involuntary_parting"}
        assert ew.covers == ("failure",)


def test_freedom_rise_uses_freedom_unlimited_terms():
    """Same guide (BGC11366): docs/benefits-verification.md §7 says keep them identical."""
    rise, fu = catalog.card("chase-freedom-rise"), catalog.card("chase-freedom-unlimited")
    assert rise.protections == fu.protections
    assert rise.earn.base_rate_pct == Decimal("1.5") and rise.earn.rules == ()


def test_cards_without_purchase_protection_or_extended_warranty():
    for card_id in NO_PP_EW_CARDS:
        card = catalog.card(card_id)
        assert all(card.protection(t) is None for t in COUNTED_TYPES), card_id
    assert catalog.card("apple-card").protections == ()
    assert catalog.card("discover-it-student-cash-back").protections == ()
    assert [p.type for p in catalog.card("wf-active-cash").protections] == ["cell_phone_protection"]


def test_earn_rates():
    """docs/benefits-verification.md §3; numbers are Decimal for the engine."""
    rates = {card.id: card.earn.base_rate_pct for card in catalog.CATALOG.cards}
    assert rates == {
        "apple-card": Decimal("1"), "wf-active-cash": Decimal("2"), "chase-freedom-unlimited": Decimal("1.5"),
        "chase-freedom-rise": Decimal("1.5"), "discover-it-student-cash-back": Decimal("1"),
    }
    assert all(isinstance(rate, Decimal) for rate in rates.values())
    rules = {r.id: r for r in catalog.card("apple-card").earn.rules}
    apple = rules["apple-card-apple"]
    assert apple.merchant_ids == ("apple",) and apple.payment_methods == ("any",)
    assert rules["apple-card-bonus-merchants"].merchant_ids == ("nike", "walgreens")
    assert rules["apple-card-bonus-merchants"].payment_methods == ("apple_pay",)
    assert rules["apple-card-apple-pay"].rate_pct == 2 and rules["apple-card-apple-pay"].merchant_ids is None
    fu = {r.category: r.rate_pct for r in catalog.card("chase-freedom-unlimited").earn.rules}
    assert fu == {"dining": 3, "pharmacy": 3}
    assert all(r.status == "verified" for card in catalog.CATALOG.cards for r in card.earn.rules)


def test_card_art_follows_design_doc():
    for card in catalog.CATALOG.cards:
        assert card.art.asset_name == f"card-{card.id}"
        assert card.art.color == ART_COLORS[card.id]


def test_every_card_cites_a_source():
    for card in catalog.CATALOG.cards:
        assert card.sources, card.id
        assert all(s.document and s.url and s.checked_on for s in card.sources), card.id


def test_merchants():
    expected = {
        "northbay-electronics": ("electronics", False, True),
        "stride-athletics": ("apparel", None, True),
        "nike": ("apparel", True, False),
        "amazon": ("general", False, False),
        "target": ("general", None, False),
        "best-buy": ("electronics", None, False),
        "walgreens": ("pharmacy", True, False),
        "doordash": ("dining", None, False),
        "apple": ("electronics", True, False),
        "walmart": ("general", None, False),
    }
    for merchant_id, (category, apple_pay, is_demo) in expected.items():
        m = catalog.merchant(merchant_id)
        assert (m.category, m.accepts_apple_pay.value, m.is_demo) == (category, apple_pay, is_demo), merchant_id
    # Display rule (§8.2): unknown values carry a non-verified status.
    for m in catalog.CATALOG.merchants:
        if m.accepts_apple_pay.value is None:
            assert m.accepts_apple_pay.status != "verified", m.id


@pytest.mark.parametrize(
    "query, merchant_id",
    [
        ("Northbay Electronics", "northbay-electronics"),
        ("NORTHBAY  electronics", "northbay-electronics"),
        ("amazon.com", "amazon"),
        ("AMAZON", "amazon"),
        ("https://www.Nike.com/cart", "nike"),
        ("smile.amazon.com", "amazon"),
        ("Best Buy", "best-buy"),
        ("walgreens.com", "walgreens"),
        ("Unknown Shop", None),
        ("http://[broken", None),
        ("", None),
    ],
)
def test_find_merchant(query, merchant_id):
    found = catalog.find_merchant(query)
    assert (found.id if found else None) == merchant_id


def test_lookups_by_name_and_domain_are_separate():
    assert catalog.merchant_by_name("nike.com") is None
    assert catalog.merchant_by_domain("Nike") is None
    assert catalog.merchant_by_domain("WWW.BESTBUY.COM").id == "best-buy"


def test_item_category_flags():
    for category_id in RELEVANT_CATEGORIES:
        assert catalog.warranty_relevant(category_id) and catalog.theft_damage_relevant(category_id)
    for category_id in OTHER_CATEGORIES:
        assert not catalog.warranty_relevant(category_id) and not catalog.theft_damage_relevant(category_id)


def test_unknown_ids_raise_key_error():
    for lookup in (catalog.card, catalog.merchant, catalog.item_category):
        with pytest.raises(KeyError):
            lookup("no-such-id")


def write_catalog(tmp_path: Path, change) -> Path:
    data = json.loads(json.dumps(CATALOG))
    change(data)
    path = tmp_path / "cards.json"
    path.write_text(json.dumps(data), encoding="utf-8")
    return path


@pytest.mark.parametrize(
    "change, message",
    [
        pytest.param(lambda d: d["cards"][0].pop("shortName"), "shortName", id="schema-missing-field"),
        pytest.param(lambda d: d["cards"][2]["protections"][0]["source"].update(document=None),
                     "document", id="schema-verified-without-document"),
        pytest.param(lambda d: d["merchants"][0].update(category="toys"), "unknown category", id="dangling-category"),
        pytest.param(lambda d: d["cards"][0]["earn"]["rules"][0].update(merchantIds=["etsy"]),
                     "unknown merchant", id="dangling-merchant"),
        pytest.param(lambda d: d["cards"].append(d["cards"][0]), "duplicate card", id="duplicate-card"),
        pytest.param(lambda d: d["merchants"][1]["names"].append("NIKE"), "duplicate merchant name",
                     id="ambiguous-merchant-name"),
        pytest.param(lambda d: d["cards"][2]["protections"].append(d["cards"][2]["protections"][0]),
                     "more than one protection", id="duplicate-protection-type"),
    ],
)
def test_bad_catalog_fails_fast(tmp_path, change, message):
    with pytest.raises(CatalogError, match=message):
        load_catalog(write_catalog(tmp_path, change), DATA / "cards.schema.json")


def test_missing_catalog_fails_fast(tmp_path):
    with pytest.raises(CatalogError):
        load_catalog(tmp_path / "missing.json", DATA / "cards.schema.json")
