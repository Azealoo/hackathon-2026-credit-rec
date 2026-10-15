"""The card catalog: data/cards.json, validated against data/cards.schema.json (SPEC.md §15.3).

Importing this module loads and checks the file, so a bad catalog stops the backend at startup
(fail fast). Card data lives only in data/cards.json; engine and coverage code read it from here.

Numbers are Decimal (the JSON is parsed with parse_float=Decimal), so the engine can do money
math without float rounding (§7.2 rule 1).
"""

import datetime as dt
import json
import unicodedata
from decimal import Decimal
from pathlib import Path
from typing import Literal
from urllib.parse import urlsplit

from jsonschema import Draft202012Validator
from pydantic import BaseModel, ConfigDict, Field, PrivateAttr, ValidationError, model_validator
from pydantic.alias_generators import to_camel

DATA_DIR = Path(__file__).resolve().parents[2] / "data"
CARDS_FILE = DATA_DIR / "cards.json"
SCHEMA_FILE = DATA_DIR / "cards.schema.json"

Status = Literal["verified", "partial", "unverified"]
PaymentMethod = Literal["apple_pay", "card", "any"]
ProtectionType = Literal["purchase_protection", "extended_warranty", "cell_phone_protection"]


class CatalogError(RuntimeError):
    """data/cards.json is missing, doesn't match its schema, or has a dangling reference."""


class _Model(BaseModel):
    model_config = ConfigDict(
        alias_generator=to_camel, validate_by_name=True, validate_by_alias=True, extra="forbid", frozen=True
    )


class NetworkTier(_Model):
    value: str | None
    status: Status


class Art(_Model):
    asset_name: str
    color: str


class EarnRule(_Model):
    id: str
    category: str | None
    merchant_ids: tuple[str, ...] | None
    payment_methods: tuple[PaymentMethod, ...]
    rate_pct: Decimal
    cap: None
    needs_activation: bool
    status: Status


class Earn(_Model):
    base_rate_pct: Decimal
    base_rate_status: Status
    rules: tuple[EarnRule, ...]


class Limits(_Model):
    per_item_usd: Decimal | None
    per_claim_usd: Decimal | None
    per_account_usd: Decimal | None
    applies_to: Literal["item", "claim"] | None


class Eligibility(_Model):
    conditions_allowed: tuple[str, ...] | None
    payment_requirement: Literal["some_portion", "full"] | None
    excluded_categories: tuple[str, ...]


class Notice(_Model):
    notify_within_days: int | None
    submit_docs_within_days: int | None


class Claim(_Model):
    administrator: str | None
    url: str | None
    phone: str | None


class Source(_Model):
    document: str | None
    section: str | None
    version_date: dt.date | None
    url: str | None
    quote: str | None


class CardSource(Source):
    checked_on: dt.date


class Verification(_Model):
    status: Status
    checked_by: str | None
    checked_on: dt.date | None
    note: str | None


class Protection(_Model):
    type: ProtectionType
    summary: str
    covers: tuple[str, ...]
    excludes: tuple[str, ...]
    window_days: int | None = None
    window_days_by_state: dict[str, int] = Field(default_factory=dict)
    extends_by_months: int | None = None
    max_original_warranty_months: int | None = None
    max_total_from_purchase_months: int | None = None
    limits: Limits
    eligibility: Eligibility
    notice: Notice
    claim: Claim
    source: Source
    verification: Verification


class Card(_Model):
    id: str
    issuer: str | None
    product: str
    display_name: str
    short_name: str
    network: Literal["visa", "mastercard", "discover", "amex"]
    network_tier: NetworkTier
    annual_fee_usd: Decimal | None
    reward_currency: Literal["cash_back", "points"]
    point_value_cents: Decimal | None
    foreign_transaction_fee_pct: Decimal | None
    art: Art
    earn: Earn
    protections: tuple[Protection, ...]
    sources: tuple[CardSource, ...]
    notes: tuple[str, ...] = ()

    def protection(self, type_: ProtectionType) -> Protection | None:
        """This card's protection of one type, or None if it has none."""
        return next((p for p in self.protections if p.type == type_), None)


class AcceptsApplePay(_Model):
    value: bool | None
    status: Status


class Merchant(_Model):
    id: str
    names: tuple[str, ...]
    domains: tuple[str, ...]
    category: str
    accepts_apple_pay: AcceptsApplePay
    is_demo: bool
    notes: tuple[str, ...] = ()


class ItemCategory(_Model):
    id: str
    warranty_relevant: bool
    theft_damage_relevant: bool


def _norm_name(name: str) -> str:
    return " ".join(unicodedata.normalize("NFKC", name).casefold().split())


def _norm_domain(domain_or_url: str) -> str:
    text = domain_or_url.strip().casefold()
    try:
        host = urlsplit(text if "//" in text else f"//{text}").hostname or ""
    except ValueError:  # e.g. "http://[bad"
        return ""
    return host.removeprefix("www.").rstrip(".")


class Catalog(_Model):
    schema_version: Literal[1]
    catalog_version: dt.date
    cards: tuple[Card, ...]
    merchants: tuple[Merchant, ...]
    item_categories: tuple[ItemCategory, ...]

    _cards: dict[str, Card] = PrivateAttr()
    _merchants: dict[str, Merchant] = PrivateAttr()
    _categories: dict[str, ItemCategory] = PrivateAttr()
    _by_name: dict[str, Merchant] = PrivateAttr()
    _by_domain: dict[str, Merchant] = PrivateAttr()

    @model_validator(mode="after")
    def _index_and_check_references(self) -> "Catalog":
        self._cards = _unique("card", self.cards, lambda c: c.id)
        self._merchants = _unique("merchant", self.merchants, lambda m: m.id)
        self._categories = _unique("item category", self.item_categories, lambda c: c.id)
        names = [(_norm_name(n), m) for m in self.merchants for n in m.names]
        domains = [(_norm_domain(d), m) for m in self.merchants for d in m.domains]
        self._by_name = _unique("merchant name", names, lambda pair: pair[0], value=lambda pair: pair[1])
        self._by_domain = _unique("merchant domain", domains, lambda pair: pair[0], value=lambda pair: pair[1])
        _unique("earn rule", [r for c in self.cards for r in c.earn.rules], lambda r: r.id)

        problems = [f"merchant {m.id}: unknown category {m.category!r}" for m in self.merchants
                    if m.category not in self._categories]
        for card in self.cards:
            for rule in card.earn.rules:
                if rule.category is not None and rule.category not in self._categories:
                    problems.append(f"{rule.id}: unknown category {rule.category!r}")
                problems += [f"{rule.id}: unknown merchant {m!r}" for m in rule.merchant_ids or ()
                             if m not in self._merchants]
            types = [p.type for p in card.protections]
            if len(types) != len(set(types)):
                problems.append(f"{card.id}: more than one protection of the same type")
            for p in card.protections:
                problems += [f"{card.id} {p.type}: unknown excluded category {c!r}"
                             for c in p.eligibility.excluded_categories if c not in self._categories]
        if problems:
            raise ValueError("; ".join(problems))
        return self

    # --- Accessors ---------------------------------------------------------------------------

    def card_ids(self) -> list[str]:
        """Card ids in file order."""
        return list(self._cards)

    def card(self, card_id: str) -> Card:
        """The card with this id; KeyError if there is none."""
        try:
            return self._cards[card_id]
        except KeyError:
            raise KeyError(f"unknown card id {card_id!r}") from None

    def merchant(self, merchant_id: str) -> Merchant:
        """The merchant with this id; KeyError if there is none."""
        try:
            return self._merchants[merchant_id]
        except KeyError:
            raise KeyError(f"unknown merchant id {merchant_id!r}") from None

    def merchant_by_name(self, name: str) -> Merchant | None:
        """Exact name match, ignoring case and extra whitespace ("NORTHBAY  electronics" works)."""
        return self._by_name.get(_norm_name(name))

    def merchant_by_domain(self, domain_or_url: str) -> Merchant | None:
        """Match a domain or URL ("https://www.Nike.com/cart") to a merchant, including subdomains."""
        host = _norm_domain(domain_or_url)
        while host:
            if host in self._by_domain:
                return self._by_domain[host]
            host = host.partition(".")[2]
        return None

    def find_merchant(self, name_or_domain: str) -> Merchant | None:
        """merchant_by_name, then merchant_by_domain."""
        return self.merchant_by_name(name_or_domain) or self.merchant_by_domain(name_or_domain)

    def item_category(self, category_id: str) -> ItemCategory:
        """The item category with this id; KeyError if there is none."""
        try:
            return self._categories[category_id]
        except KeyError:
            raise KeyError(f"unknown item category {category_id!r}") from None

    def warranty_relevant(self, category_id: str) -> bool:
        return self.item_category(category_id).warranty_relevant

    def theft_damage_relevant(self, category_id: str) -> bool:
        return self.item_category(category_id).theft_damage_relevant


def _unique(kind, items, key, value=lambda item: item) -> dict:
    index: dict = {}
    for item in items:
        k = key(item)
        if k in index:
            raise ValueError(f"duplicate {kind} {k!r}")
        index[k] = value(item)
    return index


def load_catalog(cards_file: Path = CARDS_FILE, schema_file: Path = SCHEMA_FILE) -> Catalog:
    """Read, schema-check and parse the catalog. Raises CatalogError with every problem found."""
    try:
        raw = json.loads(cards_file.read_text(encoding="utf-8"), parse_float=Decimal)
        schema = json.loads(schema_file.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise CatalogError(f"can't read the catalog: {exc}") from exc

    validator = Draft202012Validator(schema, format_checker=Draft202012Validator.FORMAT_CHECKER)
    errors = sorted(validator.iter_errors(raw), key=lambda e: list(e.absolute_path))
    if errors:
        details = "; ".join(f"{'/'.join(map(str, e.absolute_path)) or '<root>'}: {e.message}" for e in errors[:20])
        raise CatalogError(f"{cards_file.name} doesn't match {schema_file.name} ({len(errors)} errors): {details}")

    raw.pop("$schema", None)
    try:
        return Catalog.model_validate(raw)
    except ValidationError as exc:
        raise CatalogError(f"{cards_file.name} is invalid: {exc}") from exc


CATALOG = load_catalog()

# Module-level shortcuts for the default catalog.
card_ids = CATALOG.card_ids
card = CATALOG.card
merchant = CATALOG.merchant
merchant_by_name = CATALOG.merchant_by_name
merchant_by_domain = CATALOG.merchant_by_domain
find_merchant = CATALOG.find_merchant
item_category = CATALOG.item_category
warranty_relevant = CATALOG.warranty_relevant
theft_damage_relevant = CATALOG.theft_damage_relevant
