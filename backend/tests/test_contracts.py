"""contracts/ (SPEC.md §15.5): every example validates, every §15.5 enum is in a schema,
and app/models.py agrees with the schemas."""

import json
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator
from pydantic import TypeAdapter, ValidationError
from referencing import Registry
from referencing.jsonschema import DRAFT202012

from app.models import CONTRACTS

REPO = Path(__file__).resolve().parents[2]
CONTRACTS_DIR = REPO / "contracts"
CARDS_FILE = REPO / "data" / "cards.json"

# §15.2: one schema + example for each of these.
CONTRACT_NAMES = {
    "check.request", "check.response", "coverage.request", "coverage.response",
    "store-pay.request", "store-pay.response", "live-activity-content-state",
    "check-record", "purchase",
}

# Every enum in §15.5, as (JSON field name, values). item.category ("ids from itemCategories")
# is checked against data/cards.json in test_example_ids_exist_in_cards_json instead.
SPEC_ENUMS = [
    ("screenType", {"checkout", "order_confirmation", "not_checkout", "unreadable"}),
    ("kind", {"switch", "keep", "no_checkout", "error"}),
    ("reason", {"protection", "cash", "method", "default_best", "below_threshold", "items_unreadable",
                "already_protected", "already_paid", "not_checkout", "unreadable", "error"}),
    ("presentation", {"snippet", "island"}),
    ("paymentPath", {"apple_pay", "saved_card", "card_form", "unknown"}),
    ("instruction", {"change_saved_card", "enter_card", "apple_pay_swipe", "use_apple_pay", "none"}),
    ("confidence", {"high", "medium", "low"}),
    ("condition", {"new", "renewed", "used", "unknown"}),
    ("seller", {"merchant", "third_party", "unknown"}),
    ("paymentOptionsVisible", {"apple_pay", "saved_card", "card_form", "bnpl", "paypal", "other"}),
    ("kind", {"saved_card", "card_form", "apple_pay", "unknown"}),  # selectedPayment.kind
    ("network", {"visa", "mastercard", "discover", "amex", "unknown"}),
    ("type", {"purchase_protection", "extended_warranty", "cell_phone_protection"}),
    ("appliesTo", {"item", "claim"}),
    ("verification", {"verified", "partial", "unverified"}),
    ("code", {"parse_failed", "timeout", "bad_request", "privacy_rejected", "server_error"}),
    ("view", {"result", "saved", "sent"}),
    ("status", {"planned", "confirmed"}),  # Purchase.status
    ("phase", {"checking", "keep", "no_checkout", "error", "switch_fallback"}),
    ("glyph", {"paywise", "check", "warning", "card"}),
    ("manufacturerWarrantySource", {"user", "assumed"}),
    ("paidWith", {"card_full", "card_partial", "bnpl", "unknown"}),
    ("cause", {"failure", "accidental_damage", "theft", "loss", "cosmetic", "unknown"}),
    ("causeSource", {"user_confirmed", "llm"}),
    ("verdict", {"may_be_eligible", "not_covered", "need_more_info"}),
    ("benefit", {"purchase_protection", "extended_warranty", "none"}),
    ("route", {"card_extended_warranty", "card_purchase_protection", "manufacturer", "none"}),
    ("type", {"notify_by", "file_by", "unknown"}),  # deadline.type
    ("status", {"approved", "declined", "error"}),  # store pay
    ("processor", {"visa_acceptance_sandbox", "mock"}),
]


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


SCHEMAS = {p.name.removesuffix(".schema.json"): load(p) for p in sorted(CONTRACTS_DIR.glob("*.schema.json"))}
# Schemas reference each other by relative file name, e.g. "common.schema.json#/$defs/cardId".
REGISTRY = Registry().with_resources(
    (f"{name}.schema.json", DRAFT202012.create_resource(schema)) for name, schema in SCHEMAS.items()
)
EXAMPLES = sorted(
    (name, path) for name in CONTRACT_NAMES for path in CONTRACTS_DIR.glob(f"{name}.example*.json")
)


def validator(name: str) -> Draft202012Validator:
    return Draft202012Validator(
        {"$ref": f"{name}.schema.json"},
        registry=REGISTRY,
        format_checker=Draft202012Validator.FORMAT_CHECKER,
    )


def enum_fields(schema: dict, registry: Registry, base_uri: str) -> set[tuple[str, frozenset[str]]]:
    """(property name, values) for every string enum with 2+ values reachable from a schema."""
    found = set()

    def walk(node, resolver, name):
        if not isinstance(node, dict):
            return
        if "$ref" in node:
            resolved = resolver.lookup(node["$ref"])
            walk(resolved.contents, resolved.resolver, name)
        values = [v for v in node.get("enum", []) if v is not None]
        if name and len(values) > 1 and all(isinstance(v, str) for v in values):
            found.add((name, frozenset(values)))
        for key, sub in node.get("properties", {}).items():
            walk(sub, resolver, key)
        for key in ("items", "additionalProperties"):
            walk(node.get(key), resolver, name)
        for key in ("anyOf", "oneOf", "allOf"):
            for sub in node.get(key, []):
                walk(sub, resolver, name)

    walk(schema, registry.resolver(base_uri=base_uri), None)
    return found


def contract_enums(name: str) -> set[tuple[str, frozenset[str]]]:
    return enum_fields(SCHEMAS[name], REGISTRY, f"{name}.schema.json")


def model_enums(name: str) -> set[tuple[str, frozenset[str]]]:
    schema = TypeAdapter(CONTRACTS[name]).json_schema()
    registry = Registry().with_resource("urn:model", DRAFT202012.create_resource(schema))
    return enum_fields(schema, registry, "urn:model")


def test_every_contract_has_a_schema_example_and_model():
    assert set(SCHEMAS) - {"common"} == CONTRACT_NAMES
    assert set(CONTRACTS) == CONTRACT_NAMES
    assert {name for name, _ in EXAMPLES} == CONTRACT_NAMES


@pytest.mark.parametrize("name", sorted(SCHEMAS))
def test_schema_is_valid_json_schema(name):
    Draft202012Validator.check_schema(SCHEMAS[name])


@pytest.mark.parametrize("name, path", EXAMPLES, ids=[p.name for _, p in EXAMPLES])
def test_example_validates_against_schema(name, path):
    errors = [e.message for e in validator(name).iter_errors(load(path))]
    assert errors == []


@pytest.mark.parametrize("name, path", EXAMPLES, ids=[p.name for _, p in EXAMPLES])
def test_example_round_trips_through_model(name, path):
    adapter = TypeAdapter(CONTRACTS[name])
    data = load(path)
    parsed = adapter.validate_python(data)
    assert adapter.dump_python(parsed, mode="json", by_alias=True, exclude_unset=True) == data


@pytest.mark.parametrize("field, values", SPEC_ENUMS, ids=[f"{f}={sorted(v)[0]}" for f, v in SPEC_ENUMS])
def test_spec_enum_appears_in_a_schema(field, values):
    everywhere = set().union(*(contract_enums(name) for name in CONTRACT_NAMES))
    assert (field, frozenset(values)) in everywhere


@pytest.mark.parametrize("name", sorted(CONTRACT_NAMES))
def test_model_enums_match_schema(name):
    assert model_enums(name) == contract_enums(name)


# Keys holding a card id from data/cards.json. (store-pay's savedCardId is a demo-store card, not one of these.)
CATALOG_CARD_KEYS = {"cardId", "recommendedCardId", "defaultCardId", "cashBestCardId"}


def test_example_ids_exist_in_cards_json():
    cards = load(CARDS_FILE)
    card_ids = {c["id"] for c in cards["cards"]}
    merchant_ids = {m["id"] for m in cards["merchants"]}
    category_ids = {c["id"] for c in cards["itemCategories"]}
    used = {"card": set(), "merchant": set(), "category": set()}

    def walk(node):
        if isinstance(node, list):
            for value in node:
                walk(value)
        elif isinstance(node, dict):
            for key, value in node.items():
                if key in CATALOG_CARD_KEYS:
                    used["card"].add(value)
                elif key == "byCard":
                    used["card"].update(value)
                elif key == "merchantId":
                    used["merchant"].add(value)
                elif key == "category":
                    used["category"].add(value)
                walk(value)

    for _, path in EXAMPLES:
        walk(load(path))
    used = {kind: ids - {None} for kind, ids in used.items()}
    assert used["card"] and used["merchant"] and used["category"]
    assert used["card"] <= card_ids
    assert used["merchant"] <= merchant_ids
    assert used["category"] <= category_ids


def check_request_with(**wallet_card_changes) -> dict:
    data = load(CONTRACTS_DIR / "check.request.example.json")
    data["wallet"]["cards"][1].update(wallet_card_changes)
    return data


@pytest.mark.parametrize(
    "bad",
    [
        pytest.param(check_request_with(last4="4321"), id="last4-in-wallet"),
        pytest.param(check_request_with(isDefault=True), id="two-defaults"),
    ],
)
def test_check_request_rejects(bad):
    assert not validator("check.request").is_valid(bad)
    with pytest.raises(ValidationError):
        TypeAdapter(CONTRACTS["check.request"]).validate_python(bad)
