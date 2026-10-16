"""PrivacyGuard's card-number rule with wider separators (app/middleware.py; SPEC.md §10, §15.5).

Defense in depth behind the phone's Redactor: a card number whose digit groups are split by up to
5 spaces, tabs, hyphens, en/em dashes or periods ("4111  1111  1111  1111" as ReadingOrder joins OCR
columns, "4111 - 1111 - 1111 - 1111") is rejected with 400 privacy_rejected on every route, while
prices ("$1,499.00") and order numbers ("112-3456789-1234567") still pass.

Every card number here is built at runtime from the processors' published Visa test number, so this
file passes its own repo scan (tests/test_privacy.py: no 12+ digit literals).
"""

import copy
import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import middleware
from app.main import app

REPO = Path(__file__).resolve().parents[2]
CHECK_EXAMPLE = json.loads((REPO / "contracts" / "check.request.example.json").read_text(encoding="utf-8"))
COVERAGE_CASES = json.loads((REPO / "fixtures" / "coverage_cases.json").read_text(encoding="utf-8"))["cases"]

TEST_CARD = "4" + "1" * 15  # the processors' published Visa test number, Luhn-valid
GROUPS = [TEST_CARD[i:i + 4] for i in range(0, 16, 4)]


def with_check_digit(prefix: str) -> str:
    """prefix + the Luhn check digit (a valid-looking test number without typing one)."""
    return next(prefix + d for d in "0123456789" if middleware.luhn_ok(prefix + d))


AMEX_SHAPED = with_check_digit("3" + "4" * 13)  # 15 digits, written 4-6-5
AMEX_GROUPS = [AMEX_SHAPED[:4], AMEX_SHAPED[4:10], AMEX_SHAPED[10:]]
NOT_LUHN = TEST_CARD[:-1] + "2"

client = TestClient(app)


@pytest.fixture(autouse=True)
def rules_mode_and_fresh_limiter(monkeypatch):
    monkeypatch.setenv("PARSER_MODE", "rules")
    monkeypatch.setenv("COVERAGE_MODE", "rules")
    middleware.LIMITER.reset()
    yield
    middleware.LIMITER.reset()


def check_body(ocr_text: str) -> dict:
    body = copy.deepcopy(CHECK_EXAMPLE)
    body["screen"]["ocrText"] = ocr_text
    return body


def coverage_body(description: str) -> dict:
    case = copy.deepcopy(next(c for c in COVERAGE_CASES if c["id"] == 13))
    case["incident"]["description"] = description
    return {"purchase": case["purchase"], "incident": case["incident"], "asOf": case["asOf"]}


SEPARATED = [
    pytest.param("  ", id="two-spaces"),
    pytest.param(" - ", id="space-hyphen-space"),
    pytest.param("\t", id="tab"),
    pytest.param("\t\t", id="two-tabs"),
    pytest.param(".", id="period"),
    pytest.param(" . ", id="space-period-space"),
    pytest.param("–", id="en-dash"),
    pytest.param(" – ", id="spaced-en-dash"),
    pytest.param("—", id="em-dash"),
    pytest.param("  —  ", id="five-around-em-dash"),
    pytest.param(" " * 5, id="five-spaces"),
    pytest.param(" ", id="no-break-space"),
    pytest.param("‑", id="non-breaking-hyphen"),
]


@pytest.mark.parametrize("sep", SEPARATED)
def test_separated_card_numbers_are_card_like(sep):
    text = "Pay with Visa " + sep.join(GROUPS) + "\nTotal $1,499.00"
    assert not middleware.has_long_run(text)  # only the card-shape rule can catch it
    assert middleware.has_card_number(text)
    assert not middleware.body_is_private(json.dumps({"screen": {"ocrText": text}}).encode())


@pytest.mark.parametrize("sep", SEPARATED)
def test_separated_card_numbers_are_rejected_by_check(sep):
    formatted = sep.join(GROUPS)
    response = client.post("/v1/check", json=check_body(f"Northbay Electronics\nCard {formatted}\nTotal $18.00"))
    assert response.status_code == 400
    data = response.json()
    assert data["error"]["code"] == "privacy_rejected"
    assert data["requestId"] == CHECK_EXAMPLE["requestId"]
    assert GROUPS[1] + GROUPS[2] not in response.text and formatted not in response.text


@pytest.mark.parametrize("sep", ["  ", " - ", "–", "\t"])
def test_separated_card_numbers_are_rejected_by_coverage(sep):
    formatted = sep.join(GROUPS)
    for fmt in ("json", "html"):
        response = client.post(f"/v1/coverage?format={fmt}", json=coverage_body(f"Stolen with my card {formatted}"))
        assert response.status_code == 400, fmt
        assert response.json()["error"]["code"] == "privacy_rejected"
        assert formatted not in response.text


def test_a_4_6_5_number_with_wide_separators_is_card_like():
    assert middleware.luhn_ok(AMEX_SHAPED)
    for sep in ("  ", " - ", "—"):
        assert middleware.has_card_number("Amex " + sep.join(AMEX_GROUPS))


def test_escaped_dashes_and_tabs_are_decoded_before_the_check():
    """JSON escapes (\\u2013, \\t) don't hide the separators: the decoded strings are checked too."""
    for sep in ("–", "\t", " — "):
        raw = json.dumps(check_body("Card " + sep.join(GROUPS)), ensure_ascii=True).encode()
        assert b"\\u20" in raw or b"\\t" in raw
        assert not middleware.body_is_private(raw)
        response = client.post("/v1/check", content=raw, headers={"content-type": "application/json"})
        assert response.json()["error"]["code"] == "privacy_rejected"


def test_six_separators_end_the_run():
    """The bound: more than 5 separator characters between two groups splits them into two runs."""
    assert not middleware.has_card_number((" " * 6).join(GROUPS))
    assert not middleware.has_card_number(" - - - ".join(GROUPS))  # 7 characters


@pytest.mark.parametrize(
    "text",
    [
        pytest.param("Total $1,499.00 $1,499.00 $1,499.00 $1,499.00", id="prices"),
        pytest.param("Subtotal  $1,499.00\nTax  $0.00\nTotal  $1,499.00", id="price-rows"),
        pytest.param("1499.00  1499.00  1499.00  1499.00", id="prices-without-commas"),
        pytest.param("1499.00 - 1499.00 - 1499.00 - 1499.00", id="hyphenated-prices"),
        pytest.param("Order #112-3456789-1234567", id="order-number"),
        pytest.param("Order # 112 - 3456789 - 1234567", id="spaced-order-number"),
        pytest.param("Order\t112–3456789–1234567", id="en-dash-order-number"),
        pytest.param("Delivery 2026-10-17 – 2026-10-20 · (555) 010-0000", id="dates-and-phone"),
        pytest.param("Visa [CARD]  Exp 12/29  ZIP 98000", id="redacted-card"),
        pytest.param("Card " + "  ".join([NOT_LUHN[i:i + 4] for i in range(0, 16, 4)]), id="card-shaped-not-luhn"),
    ],
)
def test_ordinary_numbers_still_pass(text):
    assert not middleware.has_card_like_run(text)
    assert middleware.body_is_private(json.dumps(check_body(text)).encode())
    assert client.post("/v1/check", json=check_body(text)).status_code == 200


def test_ordinary_numbers_pass_coverage():
    response = client.post("/v1/coverage", json=coverage_body("Stolen from my bag. Order 112 - 3456789 - 1234567, $1,499.00"))
    assert response.status_code == 200
