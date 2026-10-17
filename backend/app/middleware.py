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

RateLimit: a small in-memory sliding window per client (60 requests a minute by default; RATE_LIMIT_PER_MIN,
0 turns it off) for every request that can carry a body (any method but GET, HEAD and OPTIONS). /v1/check,
/v1/coverage and /v1/store/pay each have their own window; every other path shares one, so the privacy scan
can't be run unthrottled on /health or a 404. The client is CF-Connecting-IP (Cloudflare, in front of Render,
overwrites it), else the last X-Forwarded-For hop, else the socket peer: never a value the caller chose
(client_key). A header value that isn't one IP address is skipped, and an IPv6 client is its /64 (one subscriber's
network), so rotating addresses inside it doesn't reset the window. The first request keyed from each source logs
which one it was (never the address). The limiter keeps at most MAX_KEYS keys, dropping the least recently seen.
Answers 429 with the §15.5 error shape. It runs before PrivacyGuard, and sets CLIENT for app.llm's per-client budget.

PrivacyGuard reads at most body_cap(path) bytes, checked as the body arrives so an oversized body is never scanned:
32 KiB for /v1/check (a body is a few KB; parser_llm sends at most 6,000 characters of OCR text), 16 KiB for
/v1/coverage, 2 KiB for /v1/store/pay and 1 KiB on any other path (no other route takes a body). It answers 415
for a POST to /v1/check, /v1/coverage or /v1/store/pay that isn't application/json (a form or fetch() from another
site can send text/plain without a CORS preflight; the demo store is same-origin and the phone sends JSON), a body
on GET, HEAD or OPTIONS with 400 bad_request without scanning it, and JSON nested too deeply to scan with 400
bad_request. The scan runs in the thread pool, off the event loop, and its work is linear in the body: each digit
group starts at most 3 card-shaped windows.

Neither guard logs or echoes the body.
"""

import ipaddress
import json
import logging
import os
import re
import time
from collections import OrderedDict, deque
from collections.abc import Iterator
from contextvars import ContextVar

from starlette.concurrency import run_in_threadpool

from app import copy as copy_text
from app.models import CheckError, ErrorDecision, ErrorDetail

log = logging.getLogger("paywise.ratelimit")

MAX_BODY_BYTES = 32 * 1024
BODY_CAPS = {"/v1/check": MAX_BODY_BYTES, "/v1/coverage": 16 * 1024, "/v1/store/pay": 2 * 1024}
OTHER_BODY_CAP = 1024
JSON_PATHS = frozenset(BODY_CAPS)
BODYLESS_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})

_LITERAL_RUN = re.compile(r"\d{12,}")
# What may sit between two digit groups of a card number (the Redactor's set, plus line breaks as its cross-row
# check counts them, every Unicode space, and Unicode hyphens); a period followed by exactly two digits is a
# decimal point ("$18.00"), not a separator.
_SEPARATOR = (r"(?:[ \t\n\r\x0b\x0c\x85\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff"
              r"\-\u2010-\u2014\u2212]|\.(?!\d{2}(?!\d)))")
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


_DOUBLED = str.maketrans("0123456789", "0246813579")  # a Luhn-doubled digit, its two digits summed


def luhn_ok(digits: str) -> bool:
    return (sum(map(int, digits[::-2])) + sum(map(int, digits[-2::-2].translate(_DOUBLED)))) % 10 == 0


def _card_shaped(shape: list[int]) -> bool:
    """Group lengths of a card number as typed: 4-4-4-4 (13–19 digits, last group 1–4) or 4-6-5 / 4-6-4."""
    if shape in ([4, 6, 5], [4, 6, 4]):
        return True
    return len(shape) >= 4 and all(n == 4 for n in shape[:-1]) and 1 <= shape[-1] <= 4


def _card_number_in(run: str) -> bool:
    """A card-shaped window of 13–19 digits, aligned to the run's separators, that passes Luhn.

    Every card shape starts with a 4-digit group and spans 3 groups (4-6-5, 4-6-4) or 4–5 groups (4-4-4-4 plus a
    last group of 1–4, at most 19 digits), so only those windows are tried: the work is linear in the run."""
    groups = [g for g in _SEPARATORS.split(run) if g]
    lengths = [len(g) for g in groups]
    for start, first in enumerate(lengths):
        if first != 4:
            continue
        for size in (3, 4, 5):
            shape = lengths[start:start + size]
            if len(shape) < size:
                break
            if 13 <= sum(shape) <= 19 and _card_shaped(shape) and luhn_ok("".join(groups[start:start + size])):
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


def body_cap(path: str) -> int:
    """The most body bytes a path reads (BODY_CAPS; OTHER_BODY_CAP for a path with no body-taking route)."""
    return BODY_CAPS.get(path, OTHER_BODY_CAP)


def _is_json(scope) -> bool:
    """The request says its body is application/json (parameters such as charset allowed)."""
    for name, value in scope.get("headers") or []:
        if name == b"content-type":
            return value.decode("latin-1").split(";", 1)[0].strip().lower() == "application/json"
    return False


class PrivacyGuard:
    """Pure ASGI middleware: buffers the body, checks it, then hands it to the app unchanged."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        path, bodyless = scope.get("path", ""), scope.get("method") in BODYLESS_METHODS
        if not bodyless and path in JSON_PATHS and not _is_json(scope):
            return await _respond(send, 415, error_body("bad_request", "Send the body as application/json."))
        cap = body_cap(path)
        chunks, size, more = [], 0, True
        while more:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            chunk = message.get("body", b"")
            size += len(chunk)
            if size > cap:
                return await _respond(send, 400, error_body("bad_request", "The request body is too large."))
            chunks.append(chunk)
            more = message.get("more_body", False)
        body = b"".join(chunks)
        if body and bodyless:
            return await _respond(send, 400, error_body("bad_request", "This request takes no body."))
        try:
            # In the thread pool: a near-cap body takes a few ms, and the single worker keeps serving meanwhile.
            private = not body or await run_in_threadpool(body_is_private, body)
        except RecursionError:  # JSON nested deeper than the decoder or the scan can follow
            return await _respond(send, 400, error_body("bad_request", "The request body is nested too deeply."))
        if not private:
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
        self._hits: OrderedDict[str, deque[float]] = OrderedDict()  # least recently seen first

    def reset(self) -> None:
        self._hits.clear()

    def allow(self, key: str, now: float | None = None) -> bool:
        if self.per_minute <= 0:
            return True
        now = time.monotonic() if now is None else now
        hits = self._hits.get(key)
        if hits is None:
            hits = self._hits[key] = deque()
            if len(self._hits) > self.MAX_KEYS:
                self._hits.popitem(last=False)
        else:
            self._hits.move_to_end(key)
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
# Routes with a window of their own; any other path's requests share the "other" window.
RATE_LIMITED_PATHS = frozenset({"/v1/check", "/v1/coverage", "/v1/store/pay"})
OTHER_PATHS = "other"


_SOURCES = {"cf": "CF-Connecting-IP", "xff": "the last X-Forwarded-For hop", "peer": "the socket peer"}
_logged_sources: set[str] = set()


def _ip_key(value: str) -> str | None:
    """An IPv4 address as written, an IPv6 address as its /64 (an IPv4-mapped one as IPv4); None if not one IP."""
    try:
        ip = ipaddress.ip_address(value.strip())
    except ValueError:
        return None
    if isinstance(ip, ipaddress.IPv6Address):
        if ip.ipv4_mapped:
            return str(ip.ipv4_mapped)
        return str(ipaddress.IPv6Network((ip, 64), strict=False))
    return str(ip)


def _keyed_from(source: str) -> None:
    if source not in _logged_sources:
        _logged_sources.add(source)
        log.info("rate limit: clients keyed by %s", _SOURCES[source])


def client_key(scope) -> str:
    """The client a request is counted against, from headers the caller can't set (BSEC-2).

    Render puts Cloudflare in front of every web service. Cloudflare overwrites CF-Connecting-IP with the
    address that connected to it, but only appends to X-Forwarded-For, so its first hop is whatever the caller
    sent. Order: CF-Connecting-IP, else the last X-Forwarded-For hop (the one the nearest proxy appended), else
    the socket peer. A header value that isn't one IP address wasn't written by the proxy and is skipped."""
    cf, forwarded = None, ""
    for name, value in scope.get("headers") or []:
        if name == b"cf-connecting-ip":
            cf = value.decode("latin-1")
        elif name == b"x-forwarded-for":
            forwarded = value.decode("latin-1")  # if repeated, the last header is the one appended last
    if cf is not None and (key := _ip_key(cf)):
        _keyed_from("cf")
        return key
    if key := _ip_key(forwarded.split(",")[-1]):
        _keyed_from("xff")
        return key
    _keyed_from("peer")
    client = scope.get("client")
    return (_ip_key(client[0]) or client[0]) if client else "unknown"


# The client the current request is counted against (client_key), for app.llm's per-client budget. None outside a
# request that RateLimit saw (scripts, the eval, GETs).
CLIENT: ContextVar[str | None] = ContextVar("paywise_client", default=None)


class RateLimit:
    def __init__(self, app, limiter: SlidingWindowLimiter = LIMITER, paths=RATE_LIMITED_PATHS):
        self.app, self.limiter, self.paths = app, limiter, paths

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or scope["method"] in BODYLESS_METHODS:
            return await self.app(scope, receive, send)
        client = client_key(scope)
        window = scope["path"] if scope["path"] in self.paths else OTHER_PATHS
        if not self.limiter.allow(f"{window} {client}"):
            # 429 with code bad_request: the §15.5 error codes have no rate-limit value.
            what = "checks" if window == "/v1/check" else "requests"
            body = error_body("bad_request", f"Too many {what}; try again in a minute.",
                              line2="Too many checks \u00b7 wait a minute")
            return await _respond(send, 429, body, [(b"retry-after", b"60")])
        token = CLIENT.set(client)
        try:
            await self.app(scope, receive, send)
        finally:
            CLIENT.reset(token)
