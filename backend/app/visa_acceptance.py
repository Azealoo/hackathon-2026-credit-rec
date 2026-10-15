"""Demo-store payment for POST /v1/store/pay (SPEC v2.1 §9.2, §11.2, §15.5; docs/visa-sandbox.md §4).

PAY_MODE (read on every call, so a changed environment needs no restart in tests):
- "mock" (the default, also for an unset or unknown value): approves at once with a
  "MOCK-XXXXXXXX" transaction ID. No network, works offline (§15.8).
- "visa_acceptance": one Visa Acceptance (Cybersource) sandbox authorization,
  POST https://apitest.cybersource.com/pts/v2/payments with HTTP Signature auth and
  capture=false, so it is an authorization only and no money moves (§11.2).

Environment (names per .env.example):
- VISA_ACCEPTANCE_MERCHANT_ID, VISA_ACCEPTANCE_KEY_ID, VISA_ACCEPTANCE_SECRET_KEY (base64).
- DEMO_TEST_CARD_MAP: JSON object, saved-card ID -> processor test card. A value is either
  the card number as a string, or an object
  {"number": "...", "expMonth": "12", "expYear": "2031", "cvv": "123"} where every field but
  the number is optional (expMonth/expYear default to 12/2031; no cvv means no security code
  is sent). The longer Cybersource names (expirationMonth, expirationYear, securityCode) work too.
  Test card numbers live only in this variable, never in the repo (CLAUDE.md).

Never logged: the card number, the secret, the signature, the request body or headers.
Logged: the outcome, the sandbox's HTTP status and its reason code, and the transaction ID's
last 6 characters.
"""

from __future__ import annotations

import asyncio
import base64
import binascii
import datetime as dt
import email.utils
import hashlib
import hmac
import json
import logging
import os
import re
import secrets
import string
from collections.abc import Mapping
from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation
from typing import Literal

import httpx

from app.models import StorePayRequest, StorePayResponse

log = logging.getLogger(__name__)

SANDBOX_BASE_URL = "https://apitest.cybersource.com"
PAYMENTS_PATH = "/pts/v2/payments"
TIMEOUT_S = 10.0

# docs/visa-sandbox.md §4 caveat: Cybersource is moving from "(request-target)" to
# "request-target". Both spellings are supported; this is the one the live check passed with.
REQUEST_TARGET = "(request-target)"
SIGNED_HEADERS = ("host", "date", "{target}", "digest", "v-c-merchant-id")

# The demo store's saved cards (demo-store/store.js CARDS). Network and last 4 only; these are
# not card products, and no reward or benefit data belongs here (that is data/cards.json).
SAVED_CARD_IDS = ("demo-mastercard-5678", "demo-visa-4321", "demo-visa-1234")
NETWORK_LABELS = {"visa": "Visa", "mastercard": "Mastercard", "amex": "Amex", "discover": "Discover"}

# The fake identity from SPEC §15 (same as the demo store's checkout page).
BILL_TO = {
    "firstName": "Alex",
    "lastName": "Doe",
    "address1": "123 Example St",
    "locality": "Seattle",
    "administrativeArea": "WA",
    "postalCode": "98000",
    "country": "US",
    "email": "alex@example.com",
    "phoneNumber": "5550100000",
}
DEFAULT_EXP_MONTH = "12"
DEFAULT_EXP_YEAR = "2031"

# Cybersource "status" values that are a real answer but not an approval (docs/visa-sandbox.md §4).
DECLINED_STATUSES = frozenset({
    "DECLINED",
    "AUTHORIZED_PENDING_REVIEW",
    "AUTHORIZED_RISK_DECLINED",
    "PARTIAL_AUTHORIZED",
    "PENDING_REVIEW",
    "PENDING_AUTHENTICATION",
})

TXN_ID = re.compile(r"^[A-Za-z0-9-]{1,64}$")  # what demo-store/confirm.html accepts
SAFE_REASON = re.compile(r"^[A-Za-z0-9 _.()-]{1,80}$")
MOCK_ALPHABET = string.ascii_uppercase + string.digits

PayMode = Literal["mock", "visa_acceptance"]

# Tests swap this for an httpx.MockTransport. None means a real network connection.
TRANSPORT: httpx.AsyncBaseTransport | None = None


@dataclass(frozen=True)
class PayOutcome:
    """The /v1/store/pay response, plus diagnostics that never hold card data or secrets."""

    response: StorePayResponse
    http_status: int | None = None  # the sandbox's HTTP status; None when no call was made
    processor_status: str | None = None  # Cybersource "status", e.g. AUTHORIZED
    reason: str | None = None  # Cybersource reason code, or one of ours (e.g. card_not_configured)
    fields: tuple[str, ...] = ()  # field names from a Cybersource error's details, if any


class ConfigError(RuntimeError):
    """The Visa Acceptance environment is missing or malformed. The message names keys, never values."""


@dataclass(frozen=True)
class Credentials:
    merchant_id: str
    key_id: str
    secret: bytes  # already base64-decoded

    def __repr__(self) -> str:  # keep the secret out of tracebacks and debug output
        return "Credentials(<redacted>)"


@dataclass(frozen=True)
class ProcessorCard:
    number: str
    exp_month: str
    exp_year: str
    cvv: str | None

    def __repr__(self) -> str:
        return "ProcessorCard(<redacted>)"


# --- Saved cards and amounts --------------------------------------------------------------


def is_known_card(saved_card_id: str) -> bool:
    return saved_card_id in SAVED_CARD_IDS


def card_label(saved_card_id: str) -> str | None:
    """'demo-visa-1234' -> 'Visa ••1234'. None for an ID the store doesn't have."""
    if not is_known_card(saved_card_id):
        return None
    _, network, last4 = saved_card_id.split("-")
    return f"{NETWORK_LABELS.get(network, network.title())} ••{last4}"


def amount_cents(amount_usd: float) -> Decimal | None:
    """The amount rounded half-up to cents, or None if it isn't a finite amount above $0.00."""
    try:
        amount = Decimal(str(amount_usd)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    except (InvalidOperation, ValueError):
        return None
    return amount if amount.is_finite() and amount > 0 else None


def pay_mode(env: Mapping[str, str] | None = None) -> PayMode:
    env = os.environ if env is None else env
    return "visa_acceptance" if env.get("PAY_MODE", "").strip().lower() == "visa_acceptance" else "mock"


# --- Environment --------------------------------------------------------------------------


def load_credentials(env: Mapping[str, str]) -> Credentials:
    names = ("VISA_ACCEPTANCE_MERCHANT_ID", "VISA_ACCEPTANCE_KEY_ID", "VISA_ACCEPTANCE_SECRET_KEY")
    values = {name: env.get(name, "").strip() for name in names}
    missing = [name for name, value in values.items() if not value or value == "changeme"]
    if missing:
        raise ConfigError("missing " + ", ".join(missing))
    try:
        secret = base64.b64decode(values["VISA_ACCEPTANCE_SECRET_KEY"], validate=True)
    except (binascii.Error, ValueError):
        raise ConfigError("VISA_ACCEPTANCE_SECRET_KEY is not base64") from None
    return Credentials(values["VISA_ACCEPTANCE_MERCHANT_ID"], values["VISA_ACCEPTANCE_KEY_ID"], secret)


def _field(entry: Mapping[str, object], *names: str) -> str | None:
    for name in names:
        value = entry.get(name)
        if isinstance(value, int) and not isinstance(value, bool):
            value = str(value)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def load_test_card(env: Mapping[str, str], saved_card_id: str) -> ProcessorCard:
    raw = env.get("DEMO_TEST_CARD_MAP", "").strip()
    if not raw or raw == "changeme":
        raise ConfigError("DEMO_TEST_CARD_MAP is empty")
    try:
        mapping = json.loads(raw)
    except json.JSONDecodeError:
        # from None: the JSONDecodeError quotes the text, which holds card numbers.
        raise ConfigError("DEMO_TEST_CARD_MAP is not JSON") from None
    if not isinstance(mapping, dict):
        raise ConfigError("DEMO_TEST_CARD_MAP is not a JSON object")
    entry = mapping.get(saved_card_id)
    if isinstance(entry, str):
        entry = {"number": entry}
    if not isinstance(entry, dict):
        raise ConfigError(f"DEMO_TEST_CARD_MAP has no usable entry for {saved_card_id}")
    number = _field(entry, "number", "cardNumber")
    if number is None:
        raise ConfigError(f"DEMO_TEST_CARD_MAP entry for {saved_card_id} has no number")
    number = re.sub(r"[ -]", "", number)
    return ProcessorCard(
        number=number,
        exp_month=(_field(entry, "expMonth", "expirationMonth") or DEFAULT_EXP_MONTH).zfill(2),
        exp_year=_field(entry, "expYear", "expirationYear") or DEFAULT_EXP_YEAR,
        cvv=_field(entry, "cvv", "securityCode"),
    )


# --- Request: body and HTTP Signature (docs/visa-sandbox.md §4) -----------------------------


def payment_body(order_id: str, amount: Decimal, card: ProcessorCard | None) -> dict:
    """The authorization request. card=None leaves paymentInformation out (the auth probe)."""
    body: dict = {
        "clientReferenceInformation": {"code": order_id},
        "processingInformation": {"capture": False},
    }
    if card is not None:
        card_fields = {"number": card.number, "expirationMonth": card.exp_month, "expirationYear": card.exp_year}
        if card.cvv:
            card_fields["securityCode"] = card.cvv
        body["paymentInformation"] = {"card": card_fields}
    body["orderInformation"] = {
        "amountDetails": {"totalAmount": f"{amount:.2f}", "currency": "USD"},
        "billTo": dict(BILL_TO),
    }
    return body


def encode_body(body: dict) -> bytes:
    return json.dumps(body, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def http_date(now: dt.datetime | None = None) -> str:
    """RFC 7231 date in GMT, e.g. 'Thu, 15 Oct 2026 18:00:00 GMT'."""
    now = now or dt.datetime.now(dt.UTC)
    return email.utils.format_datetime(now.astimezone(dt.UTC), usegmt=True)


def digest(body: bytes) -> str:
    return "SHA-256=" + base64.b64encode(hashlib.sha256(body).digest()).decode("ascii")


def signing_string(
    *, host: str, date: str, method: str, path: str, digest_value: str, merchant_id: str,
    request_target: str = REQUEST_TARGET,
) -> str:
    values = {
        "host": host,
        "date": date,
        request_target: f"{method.lower()} {path}",
        "digest": digest_value,
        "v-c-merchant-id": merchant_id,
    }
    return "\n".join(f"{name}: {values[name]}" for name in _signed_header_names(request_target))


def _signed_header_names(request_target: str) -> list[str]:
    return [request_target if name == "{target}" else name for name in SIGNED_HEADERS]


def signed_headers(
    *, credentials: Credentials, body: bytes, date: str, host: str = "apitest.cybersource.com",
    method: str = "post", path: str = PAYMENTS_PATH, request_target: str = REQUEST_TARGET,
) -> dict[str, str]:
    """Every header the request needs, signed with HmacSHA256 over host, date, request-target,
    digest and v-c-merchant-id using the base64-decoded shared secret."""
    digest_value = digest(body)
    to_sign = signing_string(
        host=host, date=date, method=method, path=path, digest_value=digest_value,
        merchant_id=credentials.merchant_id, request_target=request_target,
    )
    mac = hmac.new(credentials.secret, to_sign.encode("utf-8"), hashlib.sha256).digest()
    signature = (
        f'keyid="{credentials.key_id}", algorithm="HmacSHA256", '
        f'headers="{" ".join(_signed_header_names(request_target))}", '
        f'signature="{base64.b64encode(mac).decode("ascii")}"'
    )
    return {
        "v-c-merchant-id": credentials.merchant_id,
        "Host": host,
        "Date": date,
        "Digest": digest_value,
        "Content-Type": "application/json",
        "Signature": signature,
    }


# --- Response mapping ---------------------------------------------------------------------


def map_status(http_status: int, processor_status: str | None) -> Literal["approved", "declined", "error"]:
    """AUTHORIZED -> approved; a known non-approval -> declined; everything else -> error."""
    if not 200 <= http_status < 300:
        return "error"
    if processor_status == "AUTHORIZED":
        return "approved"
    if processor_status in DECLINED_STATUSES:
        return "declined"
    return "error"


def _safe(value: object) -> str | None:
    return value if isinstance(value, str) and SAFE_REASON.match(value) else None


def _reason(payload: dict) -> str | None:
    error_info = payload.get("errorInformation")
    rmsg = payload.get("response")
    candidates = [
        payload.get("reason"),
        error_info.get("reason") if isinstance(error_info, dict) else None,
        rmsg.get("rmsg") if isinstance(rmsg, dict) else None,
    ]
    return next((safe for safe in map(_safe, candidates) if safe), None)


def _fields(payload: dict) -> tuple[str, ...]:
    sources = [payload.get("details")]
    if isinstance(payload.get("errorInformation"), dict):
        sources.append(payload["errorInformation"].get("details"))
    names = []
    for details in sources:
        for detail in details if isinstance(details, list) else []:
            name = _safe(detail.get("field")) if isinstance(detail, dict) else None
            if name:
                names.append(name)
    return tuple(names)


# --- Calls ----------------------------------------------------------------------------------


def _response(status: str, processor: str, txn: str | None, saved_card_id: str) -> StorePayResponse:
    return StorePayResponse(
        status=status, processor=processor, transaction_id=txn, card_label=card_label(saved_card_id)
    )


def mock_pay(request: StorePayRequest) -> PayOutcome:
    txn = "MOCK-" + "".join(secrets.choice(MOCK_ALPHABET) for _ in range(8))
    return PayOutcome(_response("approved", "mock", txn, request.saved_card_id), reason="mock")


async def _post(body: bytes, credentials: Credentials, *, base_url: str, request_target: str) -> httpx.Response:
    host = httpx.URL(base_url).host
    headers = signed_headers(
        credentials=credentials, body=body, date=http_date(), host=host, request_target=request_target
    )
    # httpx's timeout is per phase (connect, write, read); asyncio.timeout caps the whole call.
    async with asyncio.timeout(TIMEOUT_S):
        async with httpx.AsyncClient(base_url=base_url, timeout=TIMEOUT_S, transport=TRANSPORT) as client:
            return await client.post(PAYMENTS_PATH, content=body, headers=headers)


async def visa_pay(
    request: StorePayRequest, env: Mapping[str, str] | None = None, *,
    base_url: str = SANDBOX_BASE_URL, request_target: str = REQUEST_TARGET,
) -> PayOutcome:
    """One sandbox authorization. Never raises: problems come back as status "error"."""
    env = os.environ if env is None else env
    processor = "visa_acceptance_sandbox"
    card_id = request.saved_card_id
    amount = amount_cents(request.amount_usd)
    if amount is None or not is_known_card(card_id):
        return PayOutcome(_response("error", processor, None, card_id), reason="bad_request")
    try:
        credentials = load_credentials(env)
        card = load_test_card(env, card_id)
    except ConfigError as exc:
        log.warning("store pay: Visa Acceptance not configured (%s)", exc)
        reason = "card_not_configured" if "DEMO_TEST_CARD_MAP" in str(exc) else "credentials_not_configured"
        return PayOutcome(_response("error", processor, None, card_id), reason=reason)

    body = encode_body(payment_body(request.order_id, amount, card))
    try:
        http_response = await _post(body, credentials, base_url=base_url, request_target=request_target)
    except (httpx.TimeoutException, TimeoutError):
        log.warning("store pay: Visa Acceptance timed out after %.0f s", TIMEOUT_S)
        return PayOutcome(_response("error", processor, None, card_id), reason="timeout")
    except httpx.HTTPError as exc:
        log.warning("store pay: Visa Acceptance unreachable (%s)", type(exc).__name__)
        return PayOutcome(_response("error", processor, None, card_id), reason="unreachable")

    return _outcome(http_response, processor, card_id)


def _outcome(http_response: httpx.Response, processor: str, card_id: str) -> PayOutcome:
    try:
        payload = http_response.json()
    except ValueError:
        payload = None
    if not isinstance(payload, dict):
        payload = {}
    processor_status = _safe(payload.get("status"))
    status = map_status(http_response.status_code, processor_status)
    txn_raw = payload.get("id")
    txn = txn_raw if isinstance(txn_raw, str) and TXN_ID.match(txn_raw) else None
    reason = _reason(payload)
    level = logging.INFO if status == "approved" else logging.WARNING
    log.log(
        level, "store pay: Visa Acceptance HTTP %s -> %s (status=%s reason=%s txn=…%s)",
        http_response.status_code, status, processor_status, reason, (txn or "")[-6:],
    )
    return PayOutcome(
        _response(status, processor, txn, card_id),
        http_status=http_response.status_code,
        processor_status=processor_status,
        reason=reason,
        fields=_fields(payload),
    )


async def probe_auth(
    env: Mapping[str, str] | None = None, *, order_id: str = "NB-100234", amount: Decimal = Decimal("1499.00"),
    base_url: str = SANDBOX_BASE_URL, request_target: str = REQUEST_TARGET,
) -> PayOutcome:
    """A signed authorization request with no card at all, to check the merchant ID, key and
    signature when DEMO_TEST_CARD_MAP isn't set. The sandbox can't approve it: a 400 about the
    missing card means the signature was accepted; a 401 means it wasn't."""
    env = os.environ if env is None else env
    credentials = load_credentials(env)
    body = encode_body(payment_body(order_id, amount, None))
    try:
        http_response = await _post(body, credentials, base_url=base_url, request_target=request_target)
    except (httpx.TimeoutException, TimeoutError):
        return PayOutcome(_response("error", "visa_acceptance_sandbox", None, ""), reason="timeout")
    except httpx.HTTPError as exc:
        return PayOutcome(_response("error", "visa_acceptance_sandbox", None, ""), reason=type(exc).__name__)
    return _outcome(http_response, "visa_acceptance_sandbox", "")


async def pay(request: StorePayRequest, env: Mapping[str, str] | None = None) -> PayOutcome:
    """POST /v1/store/pay: mock or the Visa Acceptance sandbox, per PAY_MODE."""
    if pay_mode(env) == "visa_acceptance":
        return await visa_pay(request, env)
    return mock_pay(request)
