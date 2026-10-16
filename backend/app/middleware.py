"""Request guards that run before any route reads a body (SPEC.md §9.2, §10, §15.5).

PrivacyGuard: answers 400 privacy_rejected for ANY request body holding a card-number-like run,
before parsing or logging. Rulings:
- Rejected: a literal run of 12+ digits (the §9.2 rule), and a card number as a card form, OCR or a
  paste formats it: 13–19 digits in groups of 4 (or 4-6-5), passing the Luhn check, with up to 5
  separators between groups: spaces (also no-break and figure spaces), tabs, hyphens (also Unicode
  hyphens and minus), en and em dashes, and periods ("4111  1111  1111  1111" as ReadingOrder joins
  OCR columns, "4111 - 1111 - 1111 - 1111", "4111.1111.1111.1111"). A period before exactly two
  digits is a decimal point, not a separator, as in the phone's Redactor (ios/Paywise/Reading/
  Redactor.swift, Patterns.digitSeparator). The shape and Luhn checks keep prices ("$1,499.00") and
  order numbers ("112-3456789-1234567") from tripping it.
- Checked in the raw body and in the JSON-decoded strings (so \\u0034-style escapes don't hide digits).
- The literal 12+ digit rule (§9.2/§15.5) reads every byte, the requestId included: nothing is exempt.
  A random v4 UUID's last group is all digits about one time in 282, so the phone draws its requestId
  again when it holds a 12+ digit run (ios/Paywise/Check/CheckFlow.swift, RequestID.make).
- The card-shape rule, which goes beyond the spec, skips only a UUID-shaped top-level requestId. Its
  hyphenated hex groups would otherwise look like a Luhn-valid 4-4-4-4 card about one time in 2,800.
- The privacy_rejected reply echoes the requestId only when it holds no 12+ digit run, and nothing about
  a rejected body is logged.

RateLimit: a small in-memory sliding window per client (60 POSTs a minute to /v1/check by default;
RATE_LIMIT_PER_MIN, 0 turns it off). The client is the first X-Forwarded-For hop (Render's proxy
sets it), else the socket peer. Answers 429 with the §15.5 error shape.

Neither guard logs or echoes the body.
"""

import json
import os
import re
import time
from collections import deque
from collections.abc import Iterator

from app import copy as copy_text
from app.models import CheckError, ErrorDecision, ErrorDetail

MAX_BODY_BYTES = 256 * 1024

_LITERAL_RUN = re.compile(r"\d{12,}")
# What may sit between two digit groups of a card number (the Redactor's set, plus Unicode spaces and
# hyphens); a period followed by exactly two digits is a decimal point ("$18.00"), not a separator.
_SEPARATOR = r"(?:[ \t\u00a0\u2007\u202f\-\u2010\u2011\u2012\u2013\u2014\u2212]|\.(?!\d{2}(?!\d)))"
MAX_SEPARATORS = 5
_SEPARATED_RUN = re.compile(r"\d(?:" + _SEPARATOR + "{0," + str(MAX_SEPARATORS) + r"}\d){12,}")
_SEPARATORS = re.compile(_SEPARATOR + "+")
_UUID = r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
_REQUEST_ID_FIELD = re.compile(r'"requestId"\s*:\s*"(' + _UUID + r')"')
_UUID_ONLY = re.compile(r"^" + _UUID + r"$")


def error_body(code: str, message: str, request_id: str | None = None, line2: str | None = None) -> bytes:
    """The §15.5 error shape as JSON bytes (line2 overrides the code's default second line)."""
    copy = copy_text.error(code)
    if line2:
        copy = copy.model_copy(update={"line2": line2})
    error = CheckError(
        request_id=request_id,
        decision=ErrorDecision(kind="error", reason="error", presentation="island", copy=copy),
        error=ErrorDetail(code=code, message=message),
    )
    return error.model_dump_json(by_alias=True).encode("utf-8")


def request_id_from(body: bytes) -> str | None:
    """The requestId, if the raw body carries a well-formed one with no 12+ digit run (for the error reply only)."""
    match = _REQUEST_ID_FIELD.search(body.decode("utf-8", "replace"))
    if not match or _LITERAL_RUN.search(match.group(1)):
        return None
    return match.group(1)


def luhn_ok(digits: str) -> bool:
    total = 0
    for position, char in enumerate(reversed(digits)):
        value = int(char)
        if position % 2:
            value *= 2
            if value > 9:
                value -= 9
        total += value
    return total % 10 == 0


def _card_shaped(shape: list[int]) -> bool:
    """Group lengths of a card number as typed: 4-4-4-4 (13–19 digits, last group 1–4) or 4-6-5 / 4-6-4."""
    if shape in ([4, 6, 5], [4, 6, 4]):
        return True
    return len(shape) >= 4 and all(n == 4 for n in shape[:-1]) and 1 <= shape[-1] <= 4


def _card_number_in(run: str) -> bool:
    """A card-shaped window of 13–19 digits, aligned to the run's separators, that passes Luhn."""
    groups = [g for g in _SEPARATORS.split(run) if g]
    for start in range(len(groups)):
        for end in range(start + 1, len(groups) + 1):
            window = groups[start:end]
            digits = "".join(window)
            if len(digits) > 19:
                break
            if len(digits) >= 13 and _card_shaped([len(g) for g in window]) and luhn_ok(digits):
                return True
    return False


def has_long_run(text: str) -> bool:
    """The §9.2/§15.5 rule, literally: a run of 12 or more digits."""
    return _LITERAL_RUN.search(text) is not None


def has_card_number(text: str) -> bool:
    """A card number as a card form formats it (up to 5 separators between groups, Luhn-valid)."""
    return any(_card_number_in(m.group(0)) for m in _SEPARATED_RUN.finditer(text))


def has_card_like_run(text: str) -> bool:
    return has_long_run(text) or has_card_number(text)


def _strings(node, top: bool = True, skip_request_id: bool = False) -> Iterator[str]:
    """Every key, string and number in the decoded body.

    skip_request_id leaves out the value of a UUID-shaped top-level requestId."""
    if isinstance(node, dict):
        for key, value in node.items():
            yield key
            if not (skip_request_id and top and key == "requestId" and isinstance(value, str)
                    and _UUID_ONLY.match(value)):
                yield from _strings(value, top=False)
    elif isinstance(node, list):
        for value in node:
            yield from _strings(value, top=False)
    elif isinstance(node, str):
        yield node
    elif isinstance(node, (int, float)) and not isinstance(node, bool):
        yield repr(node)


def loggable_id(request_id: str) -> str:
    """The requestId for a log line: its first group alone when it reads as card-like (the card-shape rule skips
    the requestId, so a crafted UUID could hold a hyphenated card number)."""
    return request_id[:8] + "…" if has_card_like_run(request_id) else request_id


def body_is_private(body: bytes) -> bool:
    """False when the body must be rejected (privacy_rejected).

    The literal 12+ digit rule reads every byte, the requestId included. The card-shape rule (an addition
    to the spec) reads every decoded key, string and number except a UUID-shaped top-level requestId: its
    all-digit 4-4-4 middle groups beside a group that starts or ends with digits look like a Luhn-valid
    card about 1 time in 2,800. A body that isn't JSON gets the card-shape rule over every byte."""
    text = body.decode("utf-8", "replace")
    if has_long_run(text):
        return False
    try:
        decoded = json.loads(text)
    except ValueError:
        return not has_card_number(text)
    if "\\u" in text and any(has_long_run(s) for s in _strings(decoded)):  # escapes can hide digits
        return False
    return not any(has_card_number(s) for s in _strings(decoded, skip_request_id=True))


async def _respond(send, status: int, body: bytes, headers: list[tuple[bytes, bytes]] | None = None) -> None:
    await send({"type": "http.response.start", "status": status,
                "headers": [(b"content-type", b"application/json"), (b"content-length", str(len(body)).encode()),
                            *(headers or [])]})
    await send({"type": "http.response.body", "body": body})


class PrivacyGuard:
    """Pure ASGI middleware: buffers the body, checks it, then hands it to the app unchanged."""

    def __init__(self, app, max_body: int = MAX_BODY_BYTES):
        self.app, self.max_body = app, max_body

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        chunks, size, more = [], 0, True
        while more:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            chunk = message.get("body", b"")
            size += len(chunk)
            if size > self.max_body:
                return await _respond(send, 400, error_body("bad_request", "The request body is too large."))
            chunks.append(chunk)
            more = message.get("more_body", False)
        body = b"".join(chunks)
        if body and not body_is_private(body):
            return await _respond(send, 400, error_body(
                "privacy_rejected", "The request held a run of 12 or more digits, so it wasn't read.",
                request_id_from(body)))

        delivered = False

        async def replay():
            nonlocal delivered
            if not delivered:
                delivered = True
                return {"type": "http.request", "body": body, "more_body": False}
            return await receive()

        await self.app(scope, replay, send)


class SlidingWindowLimiter:
    """At most per_minute hits per key in any 60-second window. per_minute <= 0 turns it off."""

    WINDOW_S = 60.0
    MAX_KEYS = 10_000

    def __init__(self, per_minute: int):
        self.per_minute = per_minute
        self._hits: dict[str, deque[float]] = {}

    def reset(self) -> None:
        self._hits.clear()

    def allow(self, key: str, now: float | None = None) -> bool:
        if self.per_minute <= 0:
            return True
        now = time.monotonic() if now is None else now
        if len(self._hits) > self.MAX_KEYS:
            self._hits = {k: q for k, q in self._hits.items() if q and q[-1] > now - self.WINDOW_S}
        hits = self._hits.setdefault(key, deque())
        while hits and hits[0] <= now - self.WINDOW_S:
            hits.popleft()
        if len(hits) >= self.per_minute:
            return False
        hits.append(now)
        return True


def _limit_from_env() -> int:
    try:
        return int(os.environ.get("RATE_LIMIT_PER_MIN", "60"))
    except ValueError:
        return 60


LIMITER = SlidingWindowLimiter(_limit_from_env())
RATE_LIMITED_PATHS = frozenset({"/v1/check"})


def client_key(scope) -> str:
    for name, value in scope.get("headers") or []:
        if name == b"x-forwarded-for":
            first = value.decode("latin-1").split(",")[0].strip()
            if first:
                return first
    client = scope.get("client")
    return client[0] if client else "unknown"


class RateLimit:
    def __init__(self, app, limiter: SlidingWindowLimiter = LIMITER, paths=RATE_LIMITED_PATHS):
        self.app, self.limiter, self.paths = app, limiter, paths

    async def __call__(self, scope, receive, send):
        if (scope["type"] == "http" and scope["method"] == "POST" and scope["path"] in self.paths
                and not self.limiter.allow(client_key(scope))):
            # 429 with code bad_request: the §15.5 error codes have no rate-limit value.
            body = error_body("bad_request", "Too many checks; try again in a minute.",
                              line2="Too many checks \u00b7 wait a minute")
            return await _respond(send, 429, body, [(b"retry-after", b"60")])
        await self.app(scope, receive, send)
