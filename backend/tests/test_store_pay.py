"""POST /v1/store/pay, app/visa_acceptance.py and the /store/ static mount (SPEC v2.1 §9.2, §9.3,
§11.2, §15.5, §15.7 step 13; docs/visa-sandbox.md §4). All offline: the sandbox is an
httpx.MockTransport, and every credential and card value here is fake."""

import asyncio
import base64
import hashlib
import hmac
import json
import logging
import re
import shutil
import subprocess
from decimal import Decimal
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator

from app import routes_store, visa_acceptance
from app.main import app
from app.models import StorePayRequest

REPO = Path(__file__).resolve().parents[2]
RESPONSE_SCHEMA = json.loads((REPO / "contracts" / "store-pay.response.schema.json").read_text(encoding="utf-8"))

# Fake sandbox credentials and a fake card "number". None is real; none has a long digit run.
MERCHANT_ID = "paywise_test_merchant"
KEY_ID = "test-key-id-0001"
SECRET_RAW = b"paywise-test-secret-not-a-real-key"
SECRET_B64 = base64.b64encode(SECRET_RAW).decode("ascii")
CARD_NUMBER = "FAKECARDNUMBER"
TXN = "TESTTXN0001AB"
FIXED_DATE = "Thu, 15 Oct 2026 18:00:00 GMT"


def visa_env(card_map: object | None = None, **extra: str) -> dict[str, str]:
    if card_map is None:
        card_map = {"demo-visa-1234": {"number": CARD_NUMBER, "expMonth": "12", "expYear": "2031", "cvv": "123"}}
    env = {
        "PAY_MODE": "visa_acceptance",
        "VISA_ACCEPTANCE_MERCHANT_ID": MERCHANT_ID,
        "VISA_ACCEPTANCE_KEY_ID": KEY_ID,
        "VISA_ACCEPTANCE_SECRET_KEY": SECRET_B64,
        "DEMO_TEST_CARD_MAP": card_map if isinstance(card_map, str) else json.dumps(card_map),
    }
    env.update(extra)
    return env


def order(card: str = "demo-visa-1234", amount: float = 1499.00) -> StorePayRequest:
    return StorePayRequest(order_id="NB-100234", saved_card_id=card, amount_usd=amount)


def run(coro):
    return asyncio.run(coro)


def verify_signed_request(request: httpx.Request) -> dict:
    """What the sandbox checks, computed here without app code. Returns the parsed body."""
    body = request.content
    expected_digest = "SHA-256=" + base64.b64encode(hashlib.sha256(body).digest()).decode()
    assert request.headers["Digest"] == expected_digest
    assert request.headers["Host"] == "apitest.cybersource.com"
    assert request.headers["v-c-merchant-id"] == MERCHANT_ID
    assert request.headers["Content-Type"] == "application/json"
    assert request.url == "https://apitest.cybersource.com/pts/v2/payments"
    assert request.method == "POST"
    signed = (
        "host: apitest.cybersource.com\n"
        f"date: {request.headers['Date']}\n"
        "(request-target): post /pts/v2/payments\n"
        f"digest: {expected_digest}\n"
        f"v-c-merchant-id: {MERCHANT_ID}"
    )
    mac = base64.b64encode(hmac.new(SECRET_RAW, signed.encode(), hashlib.sha256).digest()).decode()
    assert request.headers["Signature"] == (
        f'keyid="{KEY_ID}", algorithm="HmacSHA256", '
        f'headers="host date (request-target) digest v-c-merchant-id", signature="{mac}"'
    )
    return json.loads(body)


def sandbox(status_code: int, payload: object, seen: list | None = None) -> httpx.MockTransport:
    def handler(request: httpx.Request) -> httpx.Response:
        body = verify_signed_request(request)
        if seen is not None:
            seen.append(body)
        if isinstance(payload, (bytes, str)):
            return httpx.Response(status_code, content=payload)
        return httpx.Response(status_code, json=payload)

    return httpx.MockTransport(handler)


@pytest.fixture
def client():
    return TestClient(app)


@pytest.fixture
def transport(monkeypatch):
    def use(value: httpx.AsyncBaseTransport) -> None:
        monkeypatch.setattr(visa_acceptance, "TRANSPORT", value)

    return use


# --- HTTP Signature, built exactly per docs/visa-sandbox.md §4 ----------------------------------


def test_digest_known_answer():
    # SHA-256 of the empty string, base64: a published constant.
    assert visa_acceptance.digest(b"") == "SHA-256=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="


def test_http_date_is_rfc7231_gmt():
    import datetime as dt

    when = dt.datetime(2026, 10, 15, 18, 0, 0, tzinfo=dt.UTC)
    assert visa_acceptance.http_date(when) == FIXED_DATE
    assert re.fullmatch(r"[A-Z][a-z]{2}, \d{2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}:\d{2} GMT", visa_acceptance.http_date())


@pytest.mark.parametrize("target", ["(request-target)", "request-target"])
def test_signed_headers_match_the_doc(target):
    body = b'{"clientReferenceInformation":{"code":"NB-100234"}}'
    credentials = visa_acceptance.load_credentials(visa_env())
    headers = visa_acceptance.signed_headers(
        credentials=credentials, body=body, date=FIXED_DATE, request_target=target
    )

    expected_digest = "SHA-256=" + base64.b64encode(hashlib.sha256(body).digest()).decode()
    expected_string = (
        "host: apitest.cybersource.com\n"
        "date: Thu, 15 Oct 2026 18:00:00 GMT\n"
        f"{target}: post /pts/v2/payments\n"
        f"digest: {expected_digest}\n"
        "v-c-merchant-id: paywise_test_merchant"
    )
    expected_signature = base64.b64encode(
        hmac.new(SECRET_RAW, expected_string.encode("utf-8"), hashlib.sha256).digest()
    ).decode()
    assert visa_acceptance.signing_string(
        host="apitest.cybersource.com", date=FIXED_DATE, method="post", path="/pts/v2/payments",
        digest_value=expected_digest, merchant_id=MERCHANT_ID, request_target=target,
    ) == expected_string
    assert headers == {
        "v-c-merchant-id": "paywise_test_merchant",
        "Host": "apitest.cybersource.com",
        "Date": "Thu, 15 Oct 2026 18:00:00 GMT",
        "Digest": expected_digest,
        "Content-Type": "application/json",
        "Signature": (
            'keyid="test-key-id-0001", algorithm="HmacSHA256", '
            f'headers="host date {target} digest v-c-merchant-id", signature="{expected_signature}"'
        ),
    }


def test_secret_is_base64_decoded_before_signing():
    body = b"{}"
    credentials = visa_acceptance.load_credentials(visa_env())
    headers = visa_acceptance.signed_headers(credentials=credentials, body=body, date=FIXED_DATE)
    signature = re.search(r'signature="([^"]+)"', headers["Signature"]).group(1)
    to_sign = visa_acceptance.signing_string(
        host="apitest.cybersource.com", date=FIXED_DATE, method="post", path="/pts/v2/payments",
        digest_value=visa_acceptance.digest(body), merchant_id=MERCHANT_ID,
    ).encode()
    with_raw = base64.b64encode(hmac.new(SECRET_RAW, to_sign, hashlib.sha256).digest()).decode()
    with_b64_text = base64.b64encode(hmac.new(SECRET_B64.encode(), to_sign, hashlib.sha256).digest()).decode()
    assert signature == with_raw != with_b64_text


def test_payment_body_per_the_doc():
    card = visa_acceptance.load_test_card(visa_env(), "demo-visa-1234")
    body = visa_acceptance.payment_body("NB-100234", Decimal("1499.00"), card)
    assert body == {
        "clientReferenceInformation": {"code": "NB-100234"},
        "processingInformation": {"capture": False},
        "paymentInformation": {"card": {
            "number": CARD_NUMBER, "expirationMonth": "12", "expirationYear": "2031", "securityCode": "123",
        }},
        "orderInformation": {
            "amountDetails": {"totalAmount": "1499.00", "currency": "USD"},
            "billTo": {
                "firstName": "Alex", "lastName": "Doe", "address1": "123 Example St", "locality": "Seattle",
                "administrativeArea": "WA", "postalCode": "98000", "country": "US",
                "email": "alex@example.com", "phoneNumber": "5550100000",
            },
        },
    }
    # The bytes sent are the bytes digested: compact JSON, nothing reordered later.
    assert json.loads(visa_acceptance.encode_body(body)) == body


@pytest.mark.parametrize("amount, text", [(1499.0, "1499.00"), (18, "18.00"), (249.9, "249.90"), (0.005, "0.01")])
def test_amount_is_a_two_decimal_string(amount, text):
    cents = visa_acceptance.amount_cents(amount)
    assert f"{cents:.2f}" == text
    assert visa_acceptance.payment_body("NB-1", cents, None)["orderInformation"]["amountDetails"]["totalAmount"] == text


@pytest.mark.parametrize("amount", [0, -1, 0.004, float("inf"), float("nan")])
def test_amount_not_above_zero(amount):
    assert visa_acceptance.amount_cents(amount) is None


# --- DEMO_TEST_CARD_MAP shapes -----------------------------------------------------------------


@pytest.mark.parametrize(
    "entry, expected",
    [
        ("FAKE CARD-NUMBER", ("FAKECARDNUMBER", "12", "2031", None)),
        ({"number": "FAKECARDNUMBER"}, ("FAKECARDNUMBER", "12", "2031", None)),
        ({"number": "FAKECARDNUMBER", "expMonth": "3", "expYear": "2030", "cvv": "999"},
         ("FAKECARDNUMBER", "03", "2030", "999")),
        ({"cardNumber": "FAKECARDNUMBER", "expirationMonth": 11, "expirationYear": 2032, "securityCode": "321"},
         ("FAKECARDNUMBER", "11", "2032", "321")),
    ],
)
def test_card_map_shapes(entry, expected):
    card = visa_acceptance.load_test_card(visa_env({"demo-visa-1234": entry}), "demo-visa-1234")
    assert (card.number, card.exp_month, card.exp_year, card.cvv) == expected
    assert CARD_NUMBER not in repr(card)


def test_no_cvv_means_no_security_code():
    card = visa_acceptance.load_test_card(visa_env({"demo-visa-1234": CARD_NUMBER}), "demo-visa-1234")
    assert "securityCode" not in visa_acceptance.payment_body("NB-1", Decimal("1.00"), card)["paymentInformation"]["card"]


@pytest.mark.parametrize(
    "raw",
    ["", "changeme", "{not json " + CARD_NUMBER, json.dumps([CARD_NUMBER]),
     json.dumps({"demo-visa-4321": CARD_NUMBER}), json.dumps({"demo-visa-1234": {"expMonth": "12"}})],
)
def test_bad_card_map_is_a_config_error_without_values(raw):
    with pytest.raises(visa_acceptance.ConfigError) as excinfo:
        visa_acceptance.load_test_card(visa_env(raw), "demo-visa-1234")
    assert CARD_NUMBER not in str(excinfo.value)
    # No chained JSONDecodeError either: its message would quote the map.
    assert excinfo.value.__cause__ is None
    assert excinfo.value.__context__ is None or excinfo.value.__suppress_context__


@pytest.mark.parametrize("missing", ["VISA_ACCEPTANCE_MERCHANT_ID", "VISA_ACCEPTANCE_KEY_ID", "VISA_ACCEPTANCE_SECRET_KEY"])
def test_missing_credentials(missing):
    env = visa_env()
    env[missing] = "changeme"
    with pytest.raises(visa_acceptance.ConfigError, match=missing):
        visa_acceptance.load_credentials(env)


def test_secret_must_be_base64():
    with pytest.raises(visa_acceptance.ConfigError, match="not base64"):
        visa_acceptance.load_credentials(visa_env(VISA_ACCEPTANCE_SECRET_KEY="not base64!"))
    assert "paywise" not in repr(visa_acceptance.load_credentials(visa_env()))


# --- Status mapping (docs/visa-sandbox.md §4) ---------------------------------------------------


@pytest.mark.parametrize(
    "http_status, payload, status, txn",
    [
        (201, {"id": TXN, "status": "AUTHORIZED"}, "approved", TXN),
        (201, {"id": TXN, "status": "DECLINED", "errorInformation": {"reason": "PROCESSOR_DECLINED"}}, "declined", TXN),
        (201, {"id": TXN, "status": "AUTHORIZED_PENDING_REVIEW"}, "declined", TXN),
        (201, {"id": TXN, "status": "AUTHORIZED_RISK_DECLINED"}, "declined", TXN),
        (201, {"id": TXN, "status": "PARTIAL_AUTHORIZED"}, "declined", TXN),
        (201, {"id": TXN, "status": "SOMETHING_NEW"}, "error", TXN),
        (201, {"id": TXN}, "error", TXN),
        (400, {"id": TXN, "status": "INVALID_REQUEST", "reason": "MISSING_FIELD",
               "details": [{"field": "paymentInformation.card.number", "reason": "MISSING_FIELD"}]}, "error", TXN),
        (401, {"response": {"rmsg": "Authentication Failed"}}, "error", None),
        (502, {"status": "SERVER_ERROR", "reason": "SYSTEM_ERROR"}, "error", None),
        (201, b"<html>not json</html>", "error", None),
        (201, {"id": "bad id with spaces", "status": "AUTHORIZED"}, "approved", None),
    ],
)
def test_status_mapping(transport, http_status, payload, status, txn):
    seen = []
    transport(sandbox(http_status, payload, seen))
    outcome = run(visa_acceptance.visa_pay(order(), visa_env()))
    assert outcome.response.status == status
    assert outcome.response.processor == "visa_acceptance_sandbox"
    assert outcome.response.transaction_id == txn
    assert outcome.response.card_label == "Visa ••1234"
    assert outcome.http_status == http_status
    assert len(seen) == 1 and seen[0]["paymentInformation"]["card"]["number"] == CARD_NUMBER


def test_error_reasons_and_fields_are_reported(transport):
    transport(sandbox(400, {"status": "INVALID_REQUEST", "reason": "MISSING_FIELD",
                            "details": [{"field": "paymentInformation.card.number", "reason": "MISSING_FIELD"}]}))
    outcome = run(visa_acceptance.visa_pay(order(), visa_env()))
    assert (outcome.processor_status, outcome.reason, outcome.fields) == (
        "INVALID_REQUEST", "MISSING_FIELD", ("paymentInformation.card.number",)
    )
    transport(sandbox(401, {"response": {"rmsg": "Authentication Failed"}}))
    assert run(visa_acceptance.visa_pay(order(), visa_env())).reason == "Authentication Failed"


@pytest.mark.parametrize(
    "exc, reason",
    [(httpx.ReadTimeout("slow"), "timeout"), (httpx.ConnectTimeout("slow"), "timeout"),
     (httpx.ConnectError("down"), "unreachable")],
)
def test_network_failures_are_errors(transport, exc, reason):
    def handler(request):
        raise exc

    transport(httpx.MockTransport(handler))
    outcome = run(visa_acceptance.visa_pay(order(), visa_env()))
    assert (outcome.response.status, outcome.response.transaction_id, outcome.reason) == ("error", None, reason)


def test_total_deadline(transport, monkeypatch):
    async def slow(request):
        await asyncio.sleep(2)
        return httpx.Response(201, json={"id": TXN, "status": "AUTHORIZED"})

    monkeypatch.setattr(visa_acceptance, "TIMEOUT_S", 0.05)
    transport(httpx.MockTransport(slow))
    outcome = run(visa_acceptance.visa_pay(order(), visa_env()))
    assert (outcome.response.status, outcome.reason) == ("error", "timeout")


def test_timeout_is_ten_seconds():
    assert visa_acceptance.TIMEOUT_S == 10.0


@pytest.mark.parametrize(
    "env, reason",
    [(visa_env(""), "card_not_configured"), (visa_env({"demo-visa-4321": CARD_NUMBER}), "card_not_configured"),
     (visa_env(VISA_ACCEPTANCE_KEY_ID=""), "credentials_not_configured")],
)
def test_unconfigured_visa_mode_makes_no_call(transport, env, reason):
    def handler(request):
        raise AssertionError("no request may be sent")

    transport(httpx.MockTransport(handler))
    outcome = run(visa_acceptance.visa_pay(order(), env))
    assert (outcome.response.status, outcome.response.processor, outcome.reason) == (
        "error", "visa_acceptance_sandbox", reason
    )


def test_nothing_secret_is_logged(transport, caplog):
    caplog.set_level(logging.DEBUG)
    seen = []
    transport(sandbox(201, {"id": TXN, "status": "AUTHORIZED"}, seen))
    run(visa_acceptance.visa_pay(order(), visa_env()))
    transport(sandbox(400, {"status": "INVALID_REQUEST", "reason": "MISSING_FIELD"}))
    run(visa_acceptance.visa_pay(order(), visa_env()))
    run(visa_acceptance.visa_pay(order(), visa_env("{bad json " + CARD_NUMBER)))
    logged = caplog.text
    assert "approved" in logged and "MISSING_FIELD" in logged  # the outcome is logged …
    for secret in [CARD_NUMBER, SECRET_B64, SECRET_RAW.decode(), "signature=", "billTo", "alex@example.com", TXN]:
        assert secret not in logged  # … the card, secret, signature, body and full txn ID are not


def test_probe_auth_sends_no_card(transport):
    seen = []
    transport(sandbox(400, {"status": "INVALID_REQUEST", "reason": "MISSING_FIELD"}, seen))
    outcome = run(visa_acceptance.probe_auth(visa_env("")))
    assert outcome.http_status == 400 and outcome.reason == "MISSING_FIELD"
    assert "paymentInformation" not in seen[0]
    assert seen[0]["processingInformation"] == {"capture": False}


# --- Mock mode and PAY_MODE ---------------------------------------------------------------------


@pytest.mark.parametrize(
    "value, mode",
    [(None, "mock"), ("", "mock"), ("changeme", "mock"), ("mock", "mock"), ("visa", "mock"),
     ("visa_acceptance", "visa_acceptance"), (" Visa_Acceptance ", "visa_acceptance")],
)
def test_pay_mode(value, mode):
    assert visa_acceptance.pay_mode({} if value is None else {"PAY_MODE": value}) == mode


@pytest.mark.parametrize("card, label", [("demo-visa-1234", "Visa ••1234"), ("demo-visa-4321", "Visa ••4321"),
                                         ("demo-mastercard-5678", "Mastercard ••5678")])
def test_mock_mode(card, label):
    outcome = run(visa_acceptance.pay(order(card), {"PAY_MODE": "mock"}))
    assert outcome.response.status == "approved"
    assert outcome.response.processor == "mock"
    assert re.fullmatch(r"MOCK-[A-Z0-9]{8}", outcome.response.transaction_id)
    assert outcome.response.card_label == label
    assert outcome.http_status is None


def test_saved_cards_match_the_store():
    js = (REPO / "demo-store" / "store.js").read_text(encoding="utf-8")
    store_cards = dict(re.findall(r'\{ id: "(demo-[a-z]+-\d{4})", label: "([^"]+)" \}', js))
    assert set(store_cards) == set(visa_acceptance.SAVED_CARD_IDS)
    for card_id, label in store_cards.items():
        assert visa_acceptance.card_label(card_id) == label
    assert visa_acceptance.card_label("demo-visa-9999") is None


# --- POST /v1/store/pay -------------------------------------------------------------------------


def test_route_mock(client, monkeypatch):
    monkeypatch.setenv("PAY_MODE", "mock")
    response = client.post("/v1/store/pay", json={"orderId": "NB-100234", "savedCardId": "demo-visa-1234", "amountUsd": 1499.00})
    assert response.status_code == 200
    body = response.json()
    Draft202012Validator(RESPONSE_SCHEMA).validate(body)
    assert body["status"] == "approved" and body["processor"] == "mock" and body["cardLabel"] == "Visa ••1234"


def test_route_mock_is_the_default(client, monkeypatch):
    monkeypatch.delenv("PAY_MODE", raising=False)
    response = client.post("/v1/store/pay", json={"orderId": "NB-100234", "savedCardId": "demo-mastercard-5678", "amountUsd": 18})
    assert response.status_code == 200 and response.json()["processor"] == "mock"


def test_route_visa_acceptance(client, monkeypatch, transport):
    for key, value in visa_env().items():
        monkeypatch.setenv(key, value)
    seen = []
    transport(sandbox(201, {"id": TXN, "status": "AUTHORIZED"}, seen))
    response = client.post("/v1/store/pay", json={"orderId": "NB-100234", "savedCardId": "demo-visa-1234", "amountUsd": 1499})
    assert response.status_code == 200
    assert response.json() == {"status": "approved", "processor": "visa_acceptance_sandbox",
                               "transactionId": TXN, "cardLabel": "Visa ••1234"}
    assert seen[0]["clientReferenceInformation"] == {"code": "NB-100234"}
    assert seen[0]["orderInformation"]["amountDetails"] == {"totalAmount": "1499.00", "currency": "USD"}


def test_route_processor_error_is_still_the_contract(client, monkeypatch, transport):
    for key, value in visa_env().items():
        monkeypatch.setenv(key, value)
    transport(sandbox(401, {"response": {"rmsg": "Authentication Failed"}}))
    response = client.post("/v1/store/pay", json={"orderId": "NB-100234", "savedCardId": "demo-visa-1234", "amountUsd": 1499})
    assert response.status_code == 200
    Draft202012Validator(RESPONSE_SCHEMA).validate(response.json())
    assert response.json()["status"] == "error"


@pytest.mark.parametrize(
    "body",
    [
        {"orderId": "NB-100234", "savedCardId": "demo-visa-9999", "amountUsd": 1499.00},  # unknown card
        {"orderId": "NB-100234", "savedCardId": "demo-amex-1234", "amountUsd": 1499.00},  # unknown card
        {"orderId": "NB-100234", "savedCardId": "visa-1234", "amountUsd": 1499.00},  # not the contract's pattern
        {"orderId": "NB-100234", "savedCardId": "demo-visa-1234", "amountUsd": 0},
        {"orderId": "NB-100234", "savedCardId": "demo-visa-1234", "amountUsd": -5},
        {"orderId": "NB-100234", "savedCardId": "demo-visa-1234", "amountUsd": 0.004},  # $0.00 in cents
        {"orderId": "NB-100234", "savedCardId": "demo-visa-1234", "amountUsd": "1499.00"},
        {"orderId": "", "savedCardId": "demo-visa-1234", "amountUsd": 1499.00},
        {"savedCardId": "demo-visa-1234", "amountUsd": 1499.00},
        {"orderId": "NB-100234", "savedCardId": "demo-visa-1234", "amountUsd": 1499.00, "extra": True},
        [],
    ],
)
def test_route_rejects_bad_requests(client, body):
    response = client.post("/v1/store/pay", json=body)
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "bad_request"


def test_route_rejects_non_json_and_huge_bodies(client):
    assert client.post("/v1/store/pay", content=b"not json").status_code == 400
    infinite = b'{"orderId": "NB-100234", "savedCardId": "demo-visa-1234", "amountUsd": Infinity}'
    assert client.post("/v1/store/pay", content=infinite).status_code == 400
    assert client.post("/v1/store/pay", content=b"{" + b" " * 5000 + b"}").status_code == 400


@pytest.mark.parametrize("order_id", ["4" + "0" * 15, "0000 0000 0000 0000", "NB-\\u0034" + "0" * 12])
def test_route_privacy_rejected_by_the_middleware(client, monkeypatch, order_id):
    """The route has no digit check of its own: app.main's PrivacyGuard owns this 400 for
    /v1/store/pay (literal 12+ digit runs, Luhn-valid separated runs, escaped digits), and the
    route never runs. If the guard ever stops covering this path, this fails."""

    async def must_not_pay(*_args, **_kwargs):
        raise AssertionError("the route ran on a body with a card-number-like run")

    monkeypatch.setattr(visa_acceptance, "pay", must_not_pay)
    content = '{"orderId": "' + order_id + '", "savedCardId": "demo-visa-1234", "amountUsd": 1}'  # raw: keeps 4
    response = client.post("/v1/store/pay", content=content.encode("ascii"),
                           headers={"content-type": "application/json"})
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "privacy_rejected"
    assert order_id.replace("\\u0034", "4") not in response.text and order_id not in response.text


def test_route_error_never_echoes_the_body(client):
    marker = "NB-ECHO-CHECK"
    response = client.post("/v1/store/pay", json={"orderId": marker, "savedCardId": "demo-visa-1234", "amountUsd": -1})
    assert response.status_code == 400 and marker not in response.text


# --- /store/ static mount (docs/hosting.md Part 2) ------------------------------------------------


def test_store_dir_is_the_repo_folder():
    assert routes_store.STORE_DIR == REPO / "demo-store"


def test_store_checkout_loads(client):
    response = client.get("/store/checkout.html?item=laptop")
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/html")
    assert 'data-page="checkout"' in response.text
    assert "Content-Security-Policy" in response.text


@pytest.mark.parametrize(
    "path, marker, content_type",
    [("/store/", 'data-page="shop"', "text/html"), ("/store/index.html", 'data-page="shop"', "text/html"),
     ("/store/confirm.html", 'data-page="confirm"', "text/html"),
     ("/store/store.js", "PAY_URL", "javascript"), ("/store/store.css", "{", "text/css")],
)
def test_store_files(client, path, marker, content_type):
    response = client.get(path)
    assert response.status_code == 200
    assert content_type in response.headers["content-type"]
    assert marker in response.text


@pytest.mark.parametrize("path", ["/store/nope.html", "/store/../SPEC.md", "/store/%2e%2e/SPEC.md",
                                  "/store/..%2fSPEC.md", "/store/%2e%2e/backend/app/main.py"])
def test_store_serves_only_the_folder(client, path):
    response = client.get(path)
    assert response.status_code == 404
    assert "Paywise — Product Spec" not in response.text


def test_store_does_not_shadow_the_api(client):
    assert client.get("/health").json() == {"ok": True}
    assert client.get("/v1/store/pay").status_code == 405


# --- demo-store/store.js pay-mode default (§15.7 step 13) --------------------------------------

NODE_HARNESS = r"""
const vm = require("node:vm");
const fs = require("node:fs");
const [src, cases] = JSON.parse(fs.readFileSync(0, "utf8"));
const out = cases.map(([pathname, search]) => {
  const context = vm.createContext({
    location: { pathname, search },
    document: { body: { dataset: { page: "none" } } },
    URLSearchParams, Intl, crypto,
  });
  vm.runInContext(src + "\n;globalThis.__mode = currentPayMode();", context);
  return context.__mode;
});
process.stdout.write(JSON.stringify(out));
"""


@pytest.mark.skipif(shutil.which("node") is None, reason="node is not installed")
def test_store_js_pay_mode_default():
    cases = [
        ("/store/checkout.html", "?item=laptop", "backend"),
        ("/store/", "", "backend"),
        ("/store/checkout.html", "?item=laptop&pay=mock", "mock"),
        ("/store/checkout.html", "?pay=other", "backend"),
        ("/checkout.html", "?item=laptop", "mock"),
        ("/checkout.html", "?pay=backend", "backend"),
        ("/storefront/checkout.html", "", "mock"),
        ("/demo-store/checkout.html", "", "mock"),
    ]
    src = (REPO / "demo-store" / "store.js").read_text(encoding="utf-8")
    result = subprocess.run(
        ["node", "-e", NODE_HARNESS], input=json.dumps([src, [[p, s] for p, s, _ in cases]]),
        capture_output=True, text=True, timeout=30, check=True,
    )
    assert json.loads(result.stdout) == [mode for _, _, mode in cases]


def test_log_message_is_text_only():
    from app.visa_acceptance import _message
    assert _message({"message": "General system failure."}) == "General system failure."
    assert _message({"errorInformation": {"message": "Declined - processor declined"}}) == "Declined - processor declined"
    # Anything with a run of 4+ digits never reaches the log.
    assert _message({"message": "Card 4111 failed"}) is None
    assert _message({"message": "x" * 200}) is None
    assert _message({}) is None
