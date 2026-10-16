"""Demo-store routes (SPEC v2.1 §9.2, §9.3, §15.5; docs/hosting.md Part 2).

- POST /v1/store/pay: contracts/store-pay.*. Mock or the Visa Acceptance sandbox (app.visa_acceptance).
  400 bad_request for a body that isn't the contract, an unknown savedCardId or an amount
  that isn't above $0.00 once rounded to cents. A processor problem is still 200, with status
  "error" (the contract's shape).
- A body with a card-number-like digit run never reaches this route: app.main's PrivacyGuard
  (app/middleware.py) answers it 400 privacy_rejected, in its §15.5 error shape, for every path.
  tests/test_store_pay.py pins that, so the route keeps no digit check of its own.
- /store/: the static demo-store/ folder (index.html for /store/), so the store and
  /v1/store/pay share one origin and store.js can call the backend (§15.7 step 13).

Request bodies are never logged.
"""

from pathlib import Path

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import ValidationError

from app import visa_acceptance
from app.models import StorePayRequest

STORE_DIR = Path(__file__).resolve().parents[2] / "demo-store"
MAX_BODY_BYTES = 2048

router = APIRouter()

# Mounted by app.main at /store. check_dir: a missing folder stops startup (fail fast).
store_files = StaticFiles(directory=STORE_DIR, html=True, check_dir=True)


def _error(code: str, message: str) -> JSONResponse:
    return JSONResponse(status_code=400, content={"error": {"code": code, "message": message}})


BAD_REQUEST = (
    "Send {orderId, savedCardId, amountUsd}: savedCardId one of the store's saved cards, "
    "amountUsd above 0."
)


@router.post("/v1/store/pay")
async def store_pay(request: Request) -> JSONResponse:
    body = await request.body()
    if len(body) > MAX_BODY_BYTES:
        return _error("bad_request", "Body too large.")
    try:
        # strict: amountUsd must be a JSON number, as in the contract, not a numeric string.
        pay_request = StorePayRequest.model_validate_json(body, strict=True)
    except ValidationError:
        return _error("bad_request", BAD_REQUEST)  # the details would echo the body, so they're dropped
    if not visa_acceptance.is_known_card(pay_request.saved_card_id):
        return _error("bad_request", "Unknown savedCardId.")
    if visa_acceptance.amount_cents(pay_request.amount_usd) is None:
        return _error("bad_request", "amountUsd must be above 0.")

    outcome = await visa_acceptance.pay(pay_request)
    return JSONResponse(outcome.response.model_dump(mode="json", by_alias=True))
