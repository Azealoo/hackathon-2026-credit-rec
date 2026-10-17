"""data/cards.json schemaVersion 2: offers, programs, events and category aliases (reports/Paywise offers schema.md,
decisions D1-D4). The server never evaluates offers; these tests keep the public data honest for the phone."""

import copy
import datetime as dt
import json
from decimal import Decimal
from pathlib import Path
from urllib.parse import urlsplit

import pytest

from app import catalog
from app.catalog import CatalogError, load_catalog

DATA = Path(__file__).resolve().parents[2] / "data"
RAW = json.loads((DATA / "cards.json").read_text(encoding="utf-8"))
CAT = catalog.CATALOG


def all_sources():
    for card in CAT.cards:
        yield card.id, card.sources
        for rule in card.earn.rules:
            yield rule.id, rule.sources
    for item in (*CAT.offers, *CAT.programs, *CAT.events):
        yield item.id, item.sources


def test_every_citation_is_a_primary_https_page_not_an_archive():
    for owner, sources in all_sources():
        for source in sources:
            parts = urlsplit(source.url)
            assert parts.scheme == "https", (owner, source.url)
            assert parts.hostname not in ("web.archive.org", "archive.org", "archive.ph"), (owner, source.url)


def test_offers_programs_and_events_cite_something():
    for item in (*CAT.offers, *CAT.programs, *CAT.events):
        assert item.sources, item.id


def test_device_offers_can_ask_or_follow_an_event():
    events = {e.id: e for e in CAT.events}
    for offer in CAT.offers:
        if offer.evaluation != "device":
            continue
        assert offer.requires, offer.id
        user_kinds = {r.kind for r in offer.requires} - {"event"}
        assert offer.confirm_question if user_kinds else True, offer.id
        for r in offer.requires:
            if r.kind == "event":
                assert offer.id in events[r.event_id].effects.enables_offer_ids, offer.id


def test_events_only_enable_offers_gated_on_them():
    offers = {o.id: o for o in CAT.offers}
    for event in CAT.events:
        for offer_id in event.effects.enables_offer_ids:
            assert any(r.kind == "event" and r.event_id == event.id for r in offers[offer_id].requires), offer_id


def test_discover_q4_5_percent():
    offer = next(o for o in CAT.offers if o.id == "discover-5pct-2026q4")
    assert offer.evaluation == "device" and offer.card_ids == ("discover-it-student-cash-back",)
    assert offer.match.categories == ("dining", "entertainment", "utilities") and offer.match.category_basis == "rule"
    assert set(offer.match.exclude_merchant_ids) == {"doordash", "uber-eats"}  # issuer coding unclear: excluded
    assert (offer.reward.kind, offer.reward.rate_pct, offer.reward.basis) == ("rate", Decimal("5"), "total")
    assert (offer.limits.spend_cap_usd, offer.limits.cap_period) == (Decimal("1500"), "calendar_quarter")
    assert (offer.window.starts_on, offer.window.ends_on) == (dt.date(2026, 10, 1), dt.date(2026, 12, 31))
    assert [r.kind for r in offer.requires] == ["activation"] and offer.requires[0].retroactive is False
    assert offer.when_unknown == "exclude"
    assert offer.confirm_question == "Activated your Q4 5%?"


def test_rise_dining_is_an_account_age_offer():
    offer = next(o for o in CAT.offers if o.id == "rise-dining-3pct-new-account")
    kinds = {r.kind: r for r in offer.requires}
    assert set(kinds) == {"acquisition_offer", "account_age"} and kinds["account_age"].months == 6
    assert kinds["acquisition_offer"].opened_from == dt.date(2026, 6, 13)
    assert (offer.limits.spend_cap_usd, offer.limits.cap_period) == (Decimal("6000"), "account_window")
    assert offer.status == "partial"


def test_booking_com_is_only_a_hint():
    offer = next(o for o in CAT.offers if o.id == "apple-card-booking-3pct")
    assert offer.evaluation == "hint" and offer.requires[0].kind == "link_or_portal"
    apple_rules = {m for r in CAT.card("apple-card").earn.rules for m in r.merchant_ids or ()}
    assert "booking-com" not in apple_rules


def test_capital_one_offers_never_switch_the_card():
    program = next(p for p in CAT.programs if p.id == "capital-one-offers")
    assert program.card_matters == "in_store_and_in_app_only"
    assert program.available_after_event_id == "discover-to-capital-one-2026"


def test_unknown_apple_pay_treatment_is_card_only():
    for rule_id in ("cfu-lyft", "rise-lyft", "cfu-chase-travel"):
        rule = next(r for c in CAT.cards for r in c.earn.rules if r.id == rule_id)
        assert rule.payment_methods == ("card",), rule_id


def test_foreign_transaction_fees():
    fees = {c.id: c.foreign_transaction_fee_pct for c in CAT.cards}
    assert fees["wf-active-cash"] == fees["chase-freedom-unlimited"] == fees["chase-freedom-rise"] == Decimal("3")
    assert fees["apple-card"] == Decimal("0")


def test_earn_rules_stay_unconditional():
    for card in CAT.cards:
        for rule in card.earn.rules:
            assert rule.cap is None and rule.needs_activation is False, rule.id


def test_category_aliases_resolve():
    aliases = {a.phrase: a.category for a in CAT.category_aliases}
    assert aliases["grocery stores"] == "grocery" and aliases["restaurants"] == "dining"
    assert aliases["gas stations"] == "gas"


@pytest.mark.parametrize("break_it, message", [
    (lambda d: d["offers"][0]["match"]["excludeMerchantIds"].append("nowhere"), "unknown merchant 'nowhere'"),
    (lambda d: d["offers"][0]["cardIds"].append("no-such-card"), "unknown card 'no-such-card'"),
    (lambda d: d["events"][0]["effects"]["enablesOfferIds"].append("no-such-offer"), "unknown offer 'no-such-offer'"),
    (lambda d: d["offers"][1]["requires"].__setitem__(0, {"kind": "event", "eventId": "no-such-event"}),
     "unknown event 'no-such-event'"),
    (lambda d: d["categoryAliases"].append({"phrase": "malls", "category": "shopping"}), "unknown category 'shopping'"),
], ids=["merchant", "card", "offer", "event", "alias"])
def test_loader_rejects_dangling_offer_references(tmp_path, break_it, message):
    data = copy.deepcopy(RAW)
    break_it(data)
    bad = tmp_path / "cards.json"
    bad.write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(CatalogError, match=message):
        load_catalog(bad, DATA / "cards.schema.json")


@pytest.mark.parametrize("break_it", [
    lambda d: d["offers"][0].__setitem__("requires", []),  # a device offer needs something only the user knows
    lambda d: d["offers"][0]["reward"].__setitem__("kind", "membership"),  # memberships are hints
    lambda d: d["offers"][0].__setitem__("confirmQuestion", None),  # activation needs a question
    lambda d: d["offers"][0]["limits"].__setitem__("capPeriod", None),  # a cap needs a period
    lambda d: d["offers"][4].__setitem__("evaluation", "device"),  # a link-only offer can't be seen at checkout
    lambda d: d["cards"][0]["earn"]["rules"][0].__setitem__("cap", 100),  # earn rules stay uncapped
], ids=["no-requires", "membership-device", "no-question", "cap-no-period", "link-device", "capped-rule"])
def test_schema_rejects_broken_offers(tmp_path, break_it):
    data = copy.deepcopy(RAW)
    break_it(data)
    bad = tmp_path / "cards.json"
    bad.write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(CatalogError, match="doesn't match"):
        load_catalog(bad, DATA / "cards.schema.json")
