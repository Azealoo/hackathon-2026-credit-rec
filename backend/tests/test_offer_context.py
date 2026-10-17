"""/v1/check offerContext (offers design D1): the request carries no offer data, and the response's offerContext is
public, the same for every user, and consistent with the decision the phone may adjust."""

import json
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import middleware
from app.main import app

REPO = Path(__file__).resolve().parents[2]
FIXTURES = REPO / "fixtures"
WALLETS = {w["id"]: w for w in json.loads((FIXTURES / "wallets.json").read_text(encoding="utf-8"))["wallets"]}
client = TestClient(app)


@pytest.fixture(autouse=True)
def rules_parser_and_fresh_limiter(monkeypatch):
    monkeypatch.setenv("PARSER_MODE", "rules")
    middleware.LIMITER.reset()
    yield
    middleware.LIMITER.reset()


def body(checkout: str, wallet: str = "demo-3card", request_id: str = "5f0c0000-aaaa-4bbb-8ccc-ddddeeeeffff") -> dict:
    return {
        "requestId": request_id,
        "client": {"app": "paywise-ios", "version": "0.1.0"},
        "clientDate": "2026-10-17",
        "screen": {"ocrText": (FIXTURES / "ocr" / f"{checkout}.txt").read_text(encoding="utf-8"),
                   "redactions": [], "ocrConfidence": 0.93},
        "wallet": {"cards": [{"cardId": c["cardId"], "isDefault": i == 0} for i, c in enumerate(WALLETS[wallet]["cards"])]},
        "prefs": {"paysInFull": None},
    }


def check(checkout: str, wallet: str = "demo-3card", **kwargs) -> dict:
    response = client.post("/v1/check", json=body(checkout, wallet, **kwargs))
    assert response.status_code == 200, response.text
    return response.json()


def cents(value: Decimal) -> Decimal:
    return value.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


@pytest.mark.parametrize("extra", [
    {"offers": [{"offerId": "discover-5pct-2026q4", "activated": True}]},
    {"offerState": {"discover-5pct-2026q4": {"answer": "yes"}}},
    {"cardFacts": {"chase-freedom-rise": {"openedOn": "2026-07"}}},
], ids=["offers", "offerState", "cardFacts"])
def test_the_request_rejects_offer_data(extra):
    response = client.post("/v1/check", json=body("mug-checkout") | extra)
    assert response.status_code == 400 and response.json()["error"]["code"] == "bad_request"


def test_a_wallet_card_rejects_offer_data():
    sent = body("mug-checkout")
    sent["wallet"]["cards"][0]["activatedOfferIds"] = ["discover-5pct-2026q4"]
    response = client.post("/v1/check", json=sent)
    assert response.status_code == 400 and response.json()["error"]["code"] == "bad_request"


def test_protection_decisions_are_not_the_phones_to_change():
    data = check("laptop-checkout")
    assert (data["decision"]["kind"], data["decision"]["reason"]) == ("switch", "protection")
    context = data["offerContext"]
    assert context["deviceMayOverride"] is False
    assert context["allowedCashPicks"] == [data["decision"]["defaultCardId"]]
    assert context["purchaseDraftByCard"] == {}


def test_a_cash_decision_lists_every_card_that_keeps_the_defaults_cover():
    data = check("mug-checkout")
    decision, context = data["decision"], data["offerContext"]
    assert (decision["kind"], decision["reason"]) == ("keep", "below_threshold")
    assert context["deviceMayOverride"] is True
    wallet = [c["cardId"] for c in WALLETS["demo-3card"]["cards"]]
    assert context["allowedCashPicks"] == wallet
    assert set(context["purchaseDraftByCard"]) == set(wallet)
    assert all(draft["cardId"] == card_id for card_id, draft in context["purchaseDraftByCard"].items())
    assert context["thresholdUsd"] == 5 and context["method"] == "card"


@pytest.mark.parametrize("checkout", ["laptop-checkout", "laptop-renewed-checkout", "earbuds-checkout", "mug-checkout"])
def test_public_rates_reproduce_the_cash(checkout):
    """The phone's consistency check: cents(amount x public rate) is the server's cash for every card."""
    data = check(checkout)
    context, by_card = data["offerContext"], data["decision"]["cash"]["byCard"]
    amount = Decimal(str(context["amountUsd"]))
    assert amount == Decimal(str(data["cart"]["totalUsd"]))
    for card_id, rate in context["publicRates"].items():
        assert cents(amount * Decimal(str(rate["ratePct"])) / 100) == Decimal(str(by_card[card_id])), card_id
    assert set(context["publicRates"]) == set(by_card)


def test_the_context_is_the_same_for_every_user():
    first = check("mug-checkout", request_id="5f0c0000-aaaa-4bbb-8ccc-aaaaaaaaaaa1")["offerContext"]
    second = check("mug-checkout", request_id="5f0c0000-aaaa-4bbb-8ccc-aaaaaaaaaaa2")["offerContext"]
    assert first == second


def test_no_checkout_has_no_context():
    data = check("feed-not-checkout")
    assert data["decision"]["kind"] == "no_checkout" and data["offerContext"] is None


def test_unreadable_items_keep_the_server_decision():
    data = check("blurry-unreadable")
    if data["decision"]["kind"] == "no_checkout":
        assert data["offerContext"] is None
    else:
        assert data["decision"]["reason"] == "items_unreadable"
        assert data["offerContext"]["deviceMayOverride"] is False
