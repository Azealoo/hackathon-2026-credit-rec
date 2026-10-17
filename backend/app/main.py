"""Paywise backend (SPEC.md §9.2): /health, POST /v1/check here; other tracks' routers are
included at the end of this file (one line each).

Request bodies are never logged. PrivacyGuard (app/middleware.py) rejects any body with a
card-number-like digit run before a route reads it; RateLimit caps each client's requests per route.
"""

import logging
import os
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response
from pydantic import ValidationError

from app import catalog  # Loads and validates data/cards.json: a bad catalog stops startup (§15.3).
from app import coverage, engine, visa_acceptance
from app import llm, parser_llm  # noqa: F401  Loaded now: importing the anthropic SDK takes ~1 s, too long for a request.
from app.middleware import PrivacyGuard, RateLimit, error_body, loggable_id, request_id_from
from app.models import CheckRequest, CheckResult, TimingMs
from app.parsing import parse_screen, parser_mode

log = logging.getLogger("paywise.check")
_paywise_log = logging.getLogger("paywise")
if not _paywise_log.handlers:  # uvicorn configures only its own loggers: show ours (metadata only, never bodies)
    _handler = logging.StreamHandler()
    _handler.setFormatter(logging.Formatter("%(levelname)s:     %(name)s %(message)s"))
    _paywise_log.addHandler(_handler)
    _paywise_log.setLevel(logging.INFO)

config_log = logging.getLogger("paywise.config")

# Each mode variable, its values, and the value it falls back to when unset or unknown. Read per request, so a test
# can change them; startup logs what they are and warns about a value that isn't one of these.
MODES = {
    "PARSER_MODE": ("parser", ("rules", "llm"), "rules"),
    "COVERAGE_MODE": ("coverage", ("rules", "llm"), "rules"),
    "PAY_MODE": ("pay", ("mock", "visa_acceptance"), "mock"),
}
UNSET = ("", "changeme")  # .env.example's placeholder means unset


def modes() -> dict[str, str]:
    return {"parser": parser_mode(), "coverage": coverage.coverage_mode(), "pay": visa_acceptance.pay_mode()}


def deployed_commit() -> str | None:
    """The commit Render deployed (Render sets RENDER_GIT_COMMIT at build and run time); None elsewhere."""
    return os.environ.get("RENDER_GIT_COMMIT", "").strip() or None


@asynccontextmanager
async def lifespan(_app: FastAPI):
    for name, (_, allowed, fallback) in MODES.items():
        value = os.environ.get(name, "").strip().lower()
        if value not in allowed and value not in UNSET:
            config_log.warning("%s=%r is not one of %s: using %s", name, value[:24], ", ".join(allowed), fallback)
    effective = " ".join(f"{key}={value}" for key, value in modes().items())
    config_log.info("config: %s commit=%s", effective, (deployed_commit() or "unknown")[:12])
    yield


# The interactive API docs only in local development: Render sets RENDER=true on every service.
_docs = {} if os.environ.get("RENDER", "").strip().lower() != "true" else {
    "docs_url": None, "redoc_url": None, "openapi_url": None}
app = FastAPI(title="Paywise", version="0.1.0", lifespan=lifespan, **_docs)
app.add_middleware(PrivacyGuard)
app.add_middleware(RateLimit)  # added last = outermost: a client over its limit is turned away first


@app.get("/health")
def health() -> dict:
    return {"ok": True, "commit": deployed_commit(), "modes": modes()}


def _error(status: int, code: str, message: str, request_id: str | None) -> Response:
    """The §15.5 error shape."""
    return Response(error_body(code, message, request_id), status_code=status, media_type="application/json")


def _describe(exc: ValidationError) -> str:
    """Field locations and messages only: pydantic's str() would echo the input values."""
    parts = [f"{'.'.join(str(p) for p in err['loc']) or 'body'}: {err['msg']}" for err in exc.errors()[:5]]
    return "Invalid request. " + "; ".join(parts)


def check_response(request: CheckRequest, parsed, parse_ms: int) -> tuple[dict, str, str]:
    """Run the engine on a parsed screen and build the /v1/check response (also used by
    scripts/make_replay.py). Returns (response JSON, decision kind, decision reason)."""
    started = time.perf_counter()
    result = engine.decide(parsed.screen_type, parsed.cart, request.wallet.cards, request.client_date)
    engine_ms = round((time.perf_counter() - started) * 1000)
    response = CheckResult(
        request_id=request.request_id,
        screen_type=parsed.screen_type,
        cart=parsed.cart if parsed.screen_type in ("checkout", "order_confirmation") else None,
        decision=result.decision,
        purchase_draft=result.purchase_draft,
        sources=result.sources,
        timing_ms=TimingMs(parse=parse_ms, engine=engine_ms),
    )
    body = response.model_dump(mode="json", by_alias=True, exclude_unset=True)
    return body, result.decision.kind, result.decision.reason


@app.post("/v1/check")
async def check(request: Request) -> Response:
    """§15.5: redacted OCR text + wallet card ids -> parse -> §7.2 engine -> decision + copy."""
    raw = await request.body()
    try:
        payload = CheckRequest.model_validate_json(raw)
    except ValidationError as exc:
        return _error(400, "bad_request", _describe(exc), request_id_from(raw))

    wallet_ids = [card.card_id for card in payload.wallet.cards]
    unknown = [card_id for card_id in wallet_ids if card_id not in catalog.CATALOG.card_ids()]
    if unknown:
        return _error(400, "bad_request", f"Unknown card id(s): {', '.join(unknown)}", payload.request_id)
    if len(set(wallet_ids)) != len(wallet_ids):
        return _error(400, "bad_request", "A card is listed twice in the wallet.", payload.request_id)

    started = time.perf_counter()
    try:
        parsed, parser = await parse_screen(payload.screen.ocr_text)
    except Exception as exc:  # the rules parser itself failed: never log the text
        log.error("check %s parse failed (%s)", loggable_id(payload.request_id), type(exc).__name__)
        return _error(500, "parse_failed", "Couldn't read this screen.", payload.request_id)
    parse_ms = round((time.perf_counter() - started) * 1000)

    try:
        body, kind, reason = check_response(payload, parsed, parse_ms)
    except engine.DateOutOfRange as exc:  # a schema-valid clientDate whose coverage dates pass Dec 31, 9999
        return _error(400, "bad_request", str(exc), payload.request_id)
    except Exception as exc:
        log.error("check %s engine failed (%s)", loggable_id(payload.request_id), type(exc).__name__)
        return _error(500, "server_error", "Something went wrong on our side.", payload.request_id)

    log.info("check %s parser=%s screen=%s decision=%s/%s parse_ms=%d engine_ms=%d", loggable_id(payload.request_id),
             parser, parsed.screen_type, kind, reason, parse_ms, body["timingMs"]["engine"])
    return JSONResponse(body)

from app.routes_store import router as store_router, store_files; app.include_router(store_router); app.mount("/store", store_files, name="store")  # noqa: E402, E702  /v1/store/pay + /store/ (§15.5, §9.3)
from app.routes_coverage import router as coverage_router; app.include_router(coverage_router)  # noqa: E402, E702  /v1/coverage (§15.5, §15.7 12b/12c)
