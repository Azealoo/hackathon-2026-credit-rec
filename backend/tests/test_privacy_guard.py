"""PrivacyGuard's card-number rule with wider separators (app/middleware.py; SPEC.md §10, §15.5).

Defense in depth behind the phone's Redactor: a card number whose digit groups are split by up to
5 spaces, tabs, hyphens, en/em dashes or periods ("4111  1111  1111  1111" as ReadingOrder joins OCR
columns, "4111 - 1111 - 1111 - 1111") is rejected with 400 privacy_rejected on every route, while
prices ("$1,499.00") and order numbers ("112-3456789-1234567") still pass.

Every card number here is built at runtime from the processors' published Visa test number, so this
file passes its own repo scan (tests/test_privacy.py: no 12+ digit literals).
"""

import asyncio
import copy
import json
import time
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


# BSEC-1: a card number split across OCR rows, or by a Unicode space, as the phone's Redactor counts it
# (crossLineDigitRun: "4111 1111\n1111 1111").
CROSS_LINE = [
    pytest.param(f"{GROUPS[0]} {GROUPS[1]}\n{GROUPS[2]} {GROUPS[3]}", id="two-rows"),
    pytest.param("\n".join(GROUPS), id="newline"),
    pytest.param("\r\n".join(GROUPS), id="crlf"),
    pytest.param("\r".join(GROUPS), id="cr"),
    pytest.param("\x0b".join(GROUPS), id="vertical-tab"),
    pytest.param("\x0c".join(GROUPS), id="form-feed"),
    pytest.param("\u2002".join(GROUPS), id="en-space"),
    pytest.param("\u2009".join(GROUPS), id="thin-space"),
    pytest.param("\u200b".join(GROUPS), id="zero-width-space"),
    pytest.param("\u3000".join(GROUPS), id="ideographic-space"),
    pytest.param("\u2028".join(GROUPS), id="line-separator"),
]


@pytest.mark.parametrize("formatted", CROSS_LINE)
def test_card_numbers_across_rows_or_unicode_spaces_are_rejected_by_check(formatted):
    assert middleware.has_card_number(formatted)
    response = client.post("/v1/check", json=check_body(f"Northbay Electronics\nCard number {formatted}\nTotal $18.00"))
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "privacy_rejected"
    assert formatted not in response.text


@pytest.mark.parametrize("formatted", CROSS_LINE[:3])
def test_card_numbers_across_rows_are_rejected_by_coverage(formatted):
    for fmt in ("json", "html"):
        response = client.post(f"/v1/coverage?format={fmt}", json=coverage_body(f"Stolen with my card\n{formatted}"))
        assert response.status_code == 400, fmt
        assert response.json()["error"]["code"] == "privacy_rejected"


def test_ocr_rows_of_ordinary_numbers_still_pass():
    text = ("Northbay Electronics\nCheckout\nAero 14 Laptop, 14-inch  $1,499.00\nNew\nQty 1\nOrder 2026\n1017\n"
            "Subtotal  $1,499.00\nTax  $0.00\nTotal  $1,499.00\nPlace order")
    assert not middleware.has_card_like_run(text)
    assert client.post("/v1/check", json=check_body(text)).status_code == 200


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


# --- Body limits (BSEC-5, BSEC-6) ---------------------------------------------------------------


@pytest.mark.parametrize("path", ["/v1/check", "/v1/coverage", "/v1/store/pay", "/health"])
def test_a_body_over_32_kib_is_refused_unread(path):
    response = client.post(path, content=b'{"x": "' + b"1 " * (16 * 1024 + 8) + b'"}',
                           headers={"content-type": "application/json"})
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "bad_request"
    assert middleware.MAX_BODY_BYTES == 32 * 1024


def test_a_full_size_check_body_still_fits():
    """6,000 characters of OCR text (parser_llm's cap) is far under the limit."""
    text = ("Northbay Electronics\nCheckout\nAero 14 Laptop, 14-inch  $1,499.00\nTotal  $1,499.00\nPlace order\n"
            + "Free returns within 30 days on most items. " * 140)[:6000]
    assert len(json.dumps(check_body(text)).encode()) < middleware.MAX_BODY_BYTES
    assert client.post("/v1/check", json=check_body(text)).status_code == 200


def test_a_body_on_a_get_is_refused_without_a_scan(monkeypatch):
    scanned = []
    monkeypatch.setattr(middleware, "body_is_private", lambda body: scanned.append(body) or True)
    response = client.request("GET", "/health", content=b'{"x": "1 1 1"}')
    assert response.status_code == 400 and response.json()["error"]["code"] == "bad_request"
    assert scanned == []
    assert client.get("/health").json()["ok"] is True


@pytest.mark.parametrize("depth", [900, 3000, 15000])
@pytest.mark.parametrize("path", ["/v1/check", "/v1/coverage?format=json", "/v1/coverage?format=html", "/v1/store/pay"])
def test_deeply_nested_json_is_a_bad_request_not_a_server_error(path, depth):
    """BSEC-6: nesting the decoder (15,000) or the privacy scan (3,000) can't follow is a 400 in the error shape."""
    lenient = TestClient(app, raise_server_exceptions=False)
    response = lenient.post(path, content=b"[" * depth + b"]" * depth, headers={"content-type": "application/json"})
    assert response.status_code == 400
    assert response.headers["content-type"].startswith("application/json")
    assert response.json()["error"]["code"] == "bad_request"


# --- Scan cost (review 2026-10-17: one in-limit client stalled the event loop) -------------------


def _full_size(unit: str, cap: int = middleware.MAX_BODY_BYTES) -> list[bytes]:
    """`unit` repeated to just under `cap`, as a raw body and as one JSON string."""
    raw = (unit * cap).encode()[: cap - 16]
    as_json = json.dumps({"x": unit * ((cap - 32) // len(unit.encode("unicode_escape")))}).encode()[: cap - 16]
    return [raw, as_json if as_json.endswith(b'"}') else json.dumps({"x": unit * 64}).encode()]


# Digit runs with as many groups (and so card-shaped windows) per byte as the separators allow.
WORST_CASES = [
    pytest.param(body, id=f"{name}-{kind}")
    for name, unit in [("1-space", "1 "), ("1-period", "1."), ("1-space-hyphen", "1 - "), ("1-six-spaces", "1     "),
                       ("4-digit-groups", "1111 "), ("4-digit-hyphen", "1111-"), ("4-6-groups", "1111 222222 "),
                       ("en-dash", "1–")]
    for kind, body in zip(("raw", "json"), _full_size(unit))
]


@pytest.mark.parametrize("body", WORST_CASES)
def test_worst_case_scan_time_is_bounded(body):
    """A 32 KiB body of digit groups took 75-250 ms to scan (every window of up to 19 digits); a card number spans
    3 to 5 groups, so the scan now looks at no more than 3 windows a group (under 10 ms on a laptop)."""
    assert len(body) <= middleware.MAX_BODY_BYTES
    best = min(_timed(middleware.body_is_private, body) for _ in range(3))
    assert best < 0.040, f"{best * 1000:.1f} ms"


def _timed(fn, *args) -> float:
    started = time.perf_counter()
    fn(*args)
    return time.perf_counter() - started


def test_the_scan_runs_off_the_event_loop(monkeypatch):
    """While one body is being scanned, other requests on the single worker still get the loop."""
    monkeypatch.setattr(middleware, "body_is_private", lambda body: time.sleep(0.3) or True)

    async def app_ok(scope, receive, send):
        await receive()
        await send({"type": "http.response.start", "status": 200, "headers": []})
        await send({"type": "http.response.body", "body": b"{}"})

    async def scenario() -> float:
        guard = middleware.PrivacyGuard(app_ok)
        scope = {"type": "http", "method": "POST", "path": "/v1/check", "headers": [(b"content-type", b"application/json")]}

        async def receive():
            return {"type": "http.request", "body": b'{"x": 1}', "more_body": False}

        async def send(message):
            pass

        done, longest = asyncio.Event(), 0.0

        async def ticker():
            nonlocal longest
            last = time.perf_counter()
            while not done.is_set():
                await asyncio.sleep(0.01)
                now = time.perf_counter()
                longest, last = max(longest, now - last), now

        async def request():
            await asyncio.sleep(0.03)  # the ticker is running first
            await guard(scope, receive, send)
            done.set()

        await asyncio.gather(request(), ticker())
        return longest

    assert asyncio.run(scenario()) < 0.15


@pytest.mark.parametrize(
    "path, cap",
    [("/v1/store/pay", 2 * 1024), ("/v1/coverage", 16 * 1024), ("/health", 1024), ("/nope", 1024)],
)
def test_each_route_caps_its_body_before_the_scan(monkeypatch, path, cap):
    """The pay body is a few dozen bytes and only /v1/check carries OCR text: the smaller caps are checked as the body
    arrives, so a body that could never be valid there is refused unscanned."""
    scanned = []
    monkeypatch.setattr(middleware, "body_is_private", lambda body: scanned.append(body) or True)
    assert middleware.body_cap(path) == cap
    response = client.post(path, content=b'{"x": "' + b"a" * cap + b'"}', headers={"content-type": "application/json"})
    assert response.status_code == 400 and response.json()["error"]["code"] == "bad_request"
    assert scanned == []
    assert middleware.body_cap("/v1/check") == middleware.MAX_BODY_BYTES


# --- Content type (review 2026-10-17: cross-site text/plain POSTs) ---------------------------------

STORE_PAY = {"orderId": "NB-100234", "savedCardId": "demo-visa-1234", "amountUsd": 18.0}


def _bodies() -> dict[str, dict]:
    return {"/v1/check": check_body("Northbay Electronics\nTotal $18.00"), "/v1/coverage": coverage_body("Stolen"),
            "/v1/store/pay": STORE_PAY}


@pytest.mark.parametrize("path", ["/v1/check", "/v1/coverage", "/v1/store/pay"])
@pytest.mark.parametrize("content_type", ["text/plain", "text/plain;charset=UTF-8", "application/x-www-form-urlencoded",
                                          "multipart/form-data; boundary=x", None])
def test_api_posts_must_be_json(monkeypatch, path, content_type):
    """A form or fetch() from another site can send text/plain without a CORS preflight; the API takes JSON only."""
    monkeypatch.setenv("PAY_MODE", "mock")
    scanned = []
    monkeypatch.setattr(middleware, "body_is_private", lambda body: scanned.append(body) or True)
    headers = {"content-type": content_type} if content_type else {}
    response = client.post(path, content=json.dumps(_bodies()[path]).encode(), headers=headers)
    assert response.status_code == 415
    assert response.json()["error"]["code"] == "bad_request"
    assert scanned == []


@pytest.mark.parametrize("path", ["/v1/check", "/v1/coverage", "/v1/store/pay"])
@pytest.mark.parametrize("content_type", ["application/json", "application/json; charset=utf-8", "Application/JSON"])
def test_json_posts_still_work(monkeypatch, path, content_type):
    monkeypatch.setenv("PAY_MODE", "mock")
    response = client.post(path, content=json.dumps(_bodies()[path]).encode(), headers={"content-type": content_type})
    assert response.status_code == 200


def test_the_store_and_the_phone_send_json():
    """The demo store (same origin, /store/) and the phone already send application/json, so nothing breaks."""
    store = (REPO / "demo-store" / "store.js").read_text(encoding="utf-8")
    assert 'const PAY_URL = "/v1/store/pay";' in store  # same origin: no CORS
    assert 'headers: { "Content-Type": "application/json" }' in store
    for swift in ("ios/Paywise/Check/PaywiseAPI.swift", "ios/Paywise/Claim/CoverageAPI.swift"):
        assert 'request.setValue("application/json", forHTTPHeaderField: "Content-Type")' in (
            REPO / swift).read_text(encoding="utf-8")
