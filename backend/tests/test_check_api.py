"""POST /v1/check end to end (SPEC.md §15.5, §15.7 step 4): S1 copy, errors, privacy, rate limit, p50."""

import asyncio
import json
import logging
import random
import statistics
import time
import uuid
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator
from referencing import Registry
from referencing.jsonschema import DRAFT202012

from app import middleware, parsing
from app.main import app

REPO = Path(__file__).resolve().parents[2]
CONTRACTS = REPO / "contracts"
FIXTURES = REPO / "fixtures"
REQUEST_ID = "5f0c0000-aaaa-4bbb-8ccc-ddddeeeeffff"
WALLETS = {w["id"]: w for w in json.loads((FIXTURES / "wallets.json").read_text(encoding="utf-8"))["wallets"]}

SCHEMAS = {p.name: json.loads(p.read_text(encoding="utf-8")) for p in CONTRACTS.glob("*.schema.json")}
REGISTRY = Registry().with_resources((name, DRAFT202012.create_resource(s)) for name, s in SCHEMAS.items())
RESPONSE_SCHEMA = Draft202012Validator({"$ref": "check.response.schema.json"}, registry=REGISTRY,
                                       format_checker=Draft202012Validator.FORMAT_CHECKER)

# Built at runtime so this file passes its own repo scan (tests/test_privacy.py: no 12+ digit runs).
TEST_CARD = "4" + "1" * 15  # the processors' published Visa test number
TWELVE_DIGITS = "1234567890" + "12"

client = TestClient(app)


@pytest.fixture(autouse=True)
def rules_parser_and_fresh_limiter(monkeypatch):
    monkeypatch.setenv("PARSER_MODE", "rules")
    middleware.LIMITER.reset()
    yield
    middleware.LIMITER.reset()


def ocr(name: str) -> str:
    return (FIXTURES / "ocr" / f"{name}.txt").read_text(encoding="utf-8")


def check_body(ocr_text: str | None = None, wallet: str = "demo-3card", request_id: str = REQUEST_ID) -> dict:
    return {
        "requestId": request_id,
        "client": {"app": "paywise-ios", "version": "0.1.0"},
        "clientDate": "2026-10-17",
        "screen": {"ocrText": ocr("laptop-checkout") if ocr_text is None else ocr_text,
                   "redactions": ["card_number", "address", "email", "phone"], "ocrConfidence": 0.93},
        "wallet": {"cards": [{"cardId": c["cardId"], "isDefault": i == 0}
                             for i, c in enumerate(WALLETS[wallet]["cards"])]},
        "prefs": {"paysInFull": None},
    }


def post(body, **kwargs):
    if isinstance(body, (dict, list)):
        return client.post("/v1/check", json=body, **kwargs)
    return client.post("/v1/check", content=body, headers={"content-type": "application/json"}, **kwargs)


def schema_errors(data) -> list[str]:
    return [e.message for e in RESPONSE_SCHEMA.iter_errors(data)]


# --- S1 ------------------------------------------------------------------------------------------


def test_s1_laptop_returns_the_exact_copy():
    response = post(check_body())
    assert response.status_code == 200
    data = response.json()
    assert schema_errors(data) == []
    assert data["requestId"] == REQUEST_ID
    assert data["screenType"] == "checkout"
    decision = data["decision"]
    assert (decision["kind"], decision["reason"], decision["presentation"]) == ("switch", "protection", "snippet")
    assert decision["recommendedCardId"] == "chase-freedom-unlimited"
    assert decision["defaultCardId"] == "apple-card"
    assert decision["cashBestCardId"] == "wf-active-cash"
    assert decision["paymentPath"] == "saved_card"
    assert decision["instruction"] == "change_saved_card"
    assert decision["cash"] == {"byCard": {"apple-card": 14.99, "wf-active-cash": 29.98, "chase-freedom-unlimited": 22.49},
                                "deltaVsCashBest": -7.49, "deltaVsDefault": 7.5}
    assert [p["type"] for p in decision["protectionsGained"]] == ["purchase_protection", "extended_warranty"]
    assert decision["protectionsGained"][0]["limit"] == {"amountUsd": 500, "appliesTo": "item"}
    assert decision["protectionsGained"][0]["windowDays"] == 120
    assert decision["protectionsGained"][1]["extendsByMonths"] == 12
    assert decision["protectionsLost"] == [] and decision["eligibilityNotes"] == []
    assert decision["confidence"] == "high"
    assert decision["copy"] == {
        "line1": "Use Freedom ••{last4:chase-freedom-unlimited}",
        "line2": "Adds a warranty year + $500 theft cover",
        "line3": "$7.49 less cash back than Active Cash",
        "instruction": "Change card to Visa ••{last4:chase-freedom-unlimited}, then place order",
        "primaryButton": "Paying with Freedom",
    }
    draft = data["purchaseDraft"]
    assert draft["cardId"] == "chase-freedom-unlimited" and draft["purchaseDate"] == "2026-10-17"
    assert draft["item"] == "Aero 14 Laptop, 14-inch" and draft["merchant"] == "Northbay Electronics"
    assert draft["coverage"] == [
        {"type": "purchase_protection", "until": "2027-02-14", "limitUsd": 500},
        {"type": "extended_warranty", "until": "2028-10-17", "assumesManufacturerWarrantyMonths": 12},
    ]
    assert data["sources"] and all(s["versionDate"] for s in data["sources"])
    assert {s["section"].split(",")[0] for s in data["sources"]} == {"Purchase Protection", "Extended Warranty Protection"}
    expected_cart = json.loads((FIXTURES / "carts" / "laptop-checkout.json").read_text(encoding="utf-8"))
    expected_cart.pop("screenType")
    assert data["cart"] == expected_cart
    assert set(data["timingMs"]) == {"parse", "engine"}


@pytest.mark.parametrize(
    "name, kind, reason, card",
    [
        ("laptop-checkout", "switch", "protection", "chase-freedom-unlimited"),
        ("laptop-renewed-checkout", "switch", "cash", "wf-active-cash"),
        ("earbuds-checkout", "switch", "protection", "chase-freedom-unlimited"),
        ("mug-checkout", "keep", "below_threshold", "apple-card"),
        ("laptop-confirmation", "no_checkout", "already_paid", None),
        ("feed-not-checkout", "no_checkout", "not_checkout", None),
        ("blurry-unreadable", "no_checkout", "unreadable", None),
    ],
)
def test_every_ocr_fixture(name, kind, reason, card):
    data = post(check_body(ocr(name))).json()
    assert schema_errors(data) == []
    assert (data["decision"]["kind"], data["decision"]["reason"]) == (kind, reason)
    assert data["decision"]["recommendedCardId"] == card
    if reason in ("not_checkout", "unreadable"):
        assert data["cart"] is None and data["purchaseDraft"] is None


def test_s1_k_freedom_default_keeps_with_a_snippet():
    data = post(check_body(wallet="fu-default")).json()
    assert schema_errors(data) == []
    assert (data["decision"]["kind"], data["decision"]["reason"]) == ("keep", "already_protected")
    assert data["decision"]["presentation"] == "snippet"
    assert data["decision"]["copy"]["primaryButton"] == "Paying with Freedom"
    assert data["purchaseDraft"]["cardId"] == "chase-freedom-unlimited"


def test_copy_lines_fit_section_6_2():
    """Lines 2–3 ≤44 and the instruction ≤48 characters with the last 4 filled in (§6.2)."""
    from app.copy import filled_length

    for name in ("laptop-checkout", "laptop-renewed-checkout", "earbuds-checkout", "mug-checkout",
                 "laptop-confirmation", "feed-not-checkout"):
        for wallet in WALLETS:
            copy = post(check_body(ocr(name), wallet=wallet)).json()["decision"]["copy"]
            for key, limit in (("line2", 44), ("line3", 44), ("instruction", 48)):
                if copy.get(key):
                    assert filled_length(copy[key]) <= limit, (name, wallet, key, copy[key])


# --- Errors ----------------------------------------------------------------------------------------


def test_unknown_wallet_card_is_bad_request():
    body = check_body()
    body["wallet"]["cards"][1]["cardId"] = "not-a-card"
    response = post(body)
    assert response.status_code == 400
    data = response.json()
    assert schema_errors(data) == []
    assert data["error"]["code"] == "bad_request" and data["requestId"] == REQUEST_ID
    assert data["decision"] == {"kind": "error", "reason": "error", "presentation": "island",
                                "copy": data["decision"]["copy"]}
    assert data["decision"]["copy"]["line1"] == "Couldn't check this time"


@pytest.mark.parametrize(
    "mutate",
    [
        pytest.param(lambda b: b["wallet"]["cards"][1].update(isDefault=True), id="two-defaults"),
        pytest.param(lambda b: b["wallet"]["cards"][1].update(last4="4321"), id="last4-sent"),
        pytest.param(lambda b: b.pop("clientDate"), id="missing-field"),
        pytest.param(lambda b: b.update(requestId="not-a-uuid"), id="bad-request-id"),
        pytest.param(lambda b: b["wallet"]["cards"].append({"cardId": "apple-card", "isDefault": False}),
                     id="card-twice"),
    ],
)
def test_invalid_requests_are_bad_request(mutate):
    body = check_body()
    mutate(body)
    response = post(body)
    assert response.status_code == 400
    assert schema_errors(response.json()) == []
    assert response.json()["error"]["code"] == "bad_request"


def test_unreadable_json_is_bad_request_with_null_request_id():
    response = post(b"{not json")
    assert response.status_code == 400
    assert response.json()["requestId"] is None
    assert schema_errors(response.json()) == []


def test_validation_errors_do_not_echo_the_ocr_text():
    body = check_body()
    body["screen"]["ocrConfidence"] = 7  # invalid, alongside the OCR text
    response = post(body)
    assert response.status_code == 400
    assert "Aero 14" not in response.text


# --- Privacy ---------------------------------------------------------------------------------------


@pytest.mark.parametrize(
    "ocr_text",
    [
        pytest.param(ocr("laptop-checkout") + f"\nCard number {TEST_CARD}", id="test-card-number"),
        pytest.param(f"Total $1,499.00\nRef {TWELVE_DIGITS}", id="any-12-digit-run"),
        pytest.param("Card number " + " ".join([TEST_CARD[i:i + 4] for i in range(0, 16, 4)]), id="spaced-card"),
        pytest.param("Card number " + "-".join([TEST_CARD[i:i + 4] for i in range(0, 16, 4)]), id="hyphenated-card"),
    ],
)
def test_long_digit_runs_are_privacy_rejected(ocr_text):
    response = post(check_body(ocr_text))
    assert response.status_code == 400
    data = response.json()
    assert schema_errors(data) == []
    assert data["error"]["code"] == "privacy_rejected"
    assert data["requestId"] == REQUEST_ID
    assert TEST_CARD not in response.text and TWELVE_DIGITS not in response.text


def test_escaped_digits_are_privacy_rejected():
    raw = json.dumps(check_body()).replace('"ocrText": "', '"ocrText": "' + "".join(f"\\u00{ord(c):x}" for c in TEST_CARD))
    assert TEST_CARD not in raw
    response = post(raw.encode())
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "privacy_rejected"


def test_digits_as_a_json_number_are_privacy_rejected():
    body = check_body()
    body["prefs"]["extra"] = int(TEST_CARD)
    assert post(body).json()["error"]["code"] == "privacy_rejected"


def test_privacy_guard_covers_every_route():
    response = client.post("/v1/coverage", json={"note": TEST_CARD})
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "privacy_rejected"


@pytest.mark.parametrize(
    "ocr_text",
    [
        pytest.param("Order #112-3456789-1234567\nTotal $18.00", id="order-number-with-hyphens"),
        pytest.param("Call (555) 010-0000 · 2026-10-17\nTotal $18.00", id="phone-and-date"),
        pytest.param("Total $1,499.00 $1,499.00 $1,499.00 $1,499.00", id="prices"),
    ],
)
def test_ordinary_numbers_pass_the_privacy_guard(ocr_text):
    assert post(check_body(ocr_text)).status_code == 200


def test_a_request_id_with_a_12_digit_run_is_privacy_rejected(caplog):
    """§15.5 literally: ANY body with a 12+ digit run, the requestId included (the phone redraws such IDs).
    The reply and the log never carry the run."""
    request_id = f"{TWELVE_DIGITS[:8]}-1234-4123-8123-{TWELVE_DIGITS}"
    with caplog.at_level(logging.DEBUG):
        response = post(check_body(request_id=request_id))
    assert response.status_code == 400
    data = response.json()
    assert schema_errors(data) == []
    assert data["error"]["code"] == "privacy_rejected"
    assert data["requestId"] is None
    assert TWELVE_DIGITS not in response.text
    assert TWELVE_DIGITS not in "\n".join(r.getMessage() for r in caplog.records)


def test_an_escaped_12_digit_run_in_the_request_id_is_privacy_rejected():
    request_id = f"{TWELVE_DIGITS[:8]}-1234-4123-8123-{TWELVE_DIGITS}"
    escaped = request_id[:24] + "".join(f"\\u00{ord(c):x}" for c in TWELVE_DIGITS)
    raw = json.dumps(check_body(request_id=request_id)).replace(request_id, escaped)
    assert TWELVE_DIGITS not in raw
    response = post(raw.encode())
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "privacy_rejected"


def test_a_request_id_with_an_11_digit_run_passes():
    request_id = f"{TWELVE_DIGITS[:8]}-1234-4123-8123-a{TWELVE_DIGITS[:11]}"
    response = post(check_body(request_id=request_id))
    assert response.status_code == 200
    assert response.json()["requestId"] == request_id


def card_shaped_uuid() -> str:
    """A valid UUID whose groups read as a Luhn-valid 4-4-4-1 card window (13 digits, no 12-digit run)."""
    for check in "0123456789":
        candidate = "abcdefab-" + "-".join(["4" + "1" * 3, "4" + "1" * 3, "8" + "1" * 3]) + "-" + check + "abcdefabcde"
        if middleware.luhn_ok("".join(ch for ch in candidate[9:24] if ch.isdigit()) + check):
            return candidate
    raise AssertionError("no Luhn-valid candidate")


def test_the_card_shape_rule_skips_only_the_top_level_request_id():
    request_id = card_shaped_uuid()
    assert middleware.has_card_number(request_id) and not middleware.has_long_run(request_id)
    assert post(check_body(request_id=request_id)).status_code == 200
    nested = check_body()
    nested["prefs"]["requestId"] = request_id  # same text anywhere else is still checked
    assert post(nested).json()["error"]["code"] == "privacy_rejected"
    assert post(check_body(ocr("laptop-checkout") + "\nRef " + request_id)).json()["error"]["code"] == "privacy_rejected"


def test_a_card_like_request_id_is_shortened_in_the_log(caplog):
    request_id = card_shaped_uuid()
    with caplog.at_level(logging.DEBUG):
        response = post(check_body(request_id=request_id))
    assert response.status_code == 200 and response.json()["requestId"] == request_id
    logged = "\n".join(r.getMessage() for r in caplog.records)
    assert f"check {request_id[:8]}… parser=rules" in logged
    assert request_id[9:] not in logged


def test_phone_request_ids_pass_and_long_runs_never_do():
    """The phone's RequestID.make: v4 UUIDs, drawn again while they hold a 12+ digit run (CheckFlow.swift)."""
    rng = random.Random(20261017)
    kept = redrawn = 0
    for _ in range(20_000):
        request_id = str(uuid.UUID(int=rng.getrandbits(128), version=4))
        body = json.dumps({"requestId": request_id, "screen": {"ocrText": "Total $18.00"}}).encode()
        if middleware.has_long_run(request_id):
            redrawn += 1
            assert not middleware.body_is_private(body), "a 12+ digit run must always be rejected"
        else:
            kept += 1
            assert middleware.body_is_private(body), "a phone-made requestId must pass"
    assert redrawn > 0 and kept > 19_000


def test_no_request_body_in_the_logs(caplog):
    marker = "Zephyrine Quokka Laptop"
    text = ocr("laptop-checkout").replace("Aero 14 Laptop", marker)
    with caplog.at_level(logging.DEBUG):
        assert post(check_body(text)).status_code == 200
        post(check_body(text + f"\n{TEST_CARD}"))
        body = check_body(text)
        body["screen"]["ocrConfidence"] = 7
        post(body)
    logged = "\n".join(r.getMessage() for r in caplog.records)
    assert "parser=rules" in logged  # the metadata line is there
    assert marker not in logged and TEST_CARD not in logged


# --- Rate limit -------------------------------------------------------------------------------------


def test_rate_limit_answers_429(monkeypatch):
    monkeypatch.setattr(middleware.LIMITER, "per_minute", 3)
    headers = {"x-forwarded-for": "203.0.113.9"}  # TEST-NET-3 documentation address
    codes = [post(check_body(), headers=headers).status_code for _ in range(4)]
    assert codes == [200, 200, 200, 429]
    response = post(check_body(), headers=headers)
    assert response.headers["retry-after"] == "60"
    assert response.json()["decision"]["copy"]["line2"] == "Too many checks \u00b7 wait a minute"
    assert schema_errors(response.json()) == []
    # Another client has its own window.
    assert post(check_body(), headers={"x-forwarded-for": "198.51.100.4"}).status_code == 200


def test_sliding_window_frees_up_after_a_minute():
    limiter = middleware.SlidingWindowLimiter(per_minute=2)
    assert limiter.allow("a", now=0.0) and limiter.allow("a", now=1.0)
    assert not limiter.allow("a", now=59.0)
    assert limiter.allow("a", now=60.5)


# --- Parser modes ------------------------------------------------------------------------------------


def test_llm_failure_falls_back_to_the_rules_parser(monkeypatch):
    from app import parser_llm

    async def broken(_text):
        raise RuntimeError("provider down")

    monkeypatch.setenv("PARSER_MODE", "llm")
    monkeypatch.setattr(parser_llm, "parse", broken)
    parsed, parser = asyncio.run(parsing.parse_screen(ocr("laptop-checkout")))
    assert parser == "rules_fallback" and parsed.cart.total_usd == 1499.0
    data = post(check_body()).json()
    assert data["decision"]["copy"]["line2"] == "Adds a warranty year + $500 theft cover"


def test_slow_llm_falls_back_to_the_rules_parser(monkeypatch):
    from app import parser_llm

    async def slow(_text):
        await asyncio.sleep(5)

    monkeypatch.setenv("PARSER_MODE", "llm")
    monkeypatch.setattr(parser_llm, "parse", slow)
    monkeypatch.setattr(parsing, "LLM_DEADLINE_S", 0.05)
    started = time.perf_counter()
    parsed, parser = asyncio.run(parsing.parse_screen(ocr("mug-checkout")))
    assert parser == "rules_fallback" and time.perf_counter() - started < 1
    assert parsed.cart.items[0].category == "home"


def test_llm_answer_is_used_when_it_succeeds(monkeypatch):
    from app import parser_llm, parser_rules

    async def fine(text):
        return parser_rules.parse(text)

    monkeypatch.setenv("PARSER_MODE", "llm")
    monkeypatch.setattr(parser_llm, "parse", fine)
    assert asyncio.run(parsing.parse_screen(ocr("earbuds-checkout")))[1] == "llm"


def test_unknown_parser_mode_means_rules(monkeypatch):
    monkeypatch.setenv("PARSER_MODE", "regex")
    assert parsing.parser_mode() == "rules"


# --- Latency -----------------------------------------------------------------------------------------


def test_check_p50_under_50_ms(monkeypatch, capsys):
    monkeypatch.setattr(middleware.LIMITER, "per_minute", 0)
    body = check_body()
    post(body)  # warm up
    times = []
    for _ in range(200):
        started = time.perf_counter()
        response = post(body)
        times.append((time.perf_counter() - started) * 1000)
        assert response.status_code == 200
    p50 = statistics.median(times)
    p90 = statistics.quantiles(times, n=10)[-1]
    with capsys.disabled():
        print(f"\nCHECK_P50_MS={p50:.2f} CHECK_P90_MS={p90:.2f}")
    assert p50 < 50
