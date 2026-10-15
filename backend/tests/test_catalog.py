"""data/cards.json against data/cards.schema.json and SPEC.md §15.3. Step 2 adds catalog.py tests here."""

import json
from pathlib import Path

from jsonschema import Draft202012Validator

DATA = Path(__file__).resolve().parents[2] / "data"

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
