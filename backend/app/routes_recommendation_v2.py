"""Opt-in structured recommendation API. Uses no OCR, LLM, network, or persistence."""

import logging
import os

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse
from pydantic import ValidationError

from app.recommendation_v2.engine import recommend
from app.recommendation_v2.models import RecommendRequest
from app.recommendation_v2.policy import PolicyError, load_snapshot

router = APIRouter(tags=["recommendation-v2"])
log = logging.getLogger(__name__)
NO_STORE = {"Cache-Control": "no-store"}


def error(status: int, code: str, message: str):
    return JSONResponse({"error": {"code": code, "message": message}}, status_code=status, headers=NO_STORE)


@router.post("/v2/recommend")
async def post_recommendation(request: Request):
    if os.environ.get("RECOMMENDATION_V2_ENABLED") != "1":
        return error(404, "feature_disabled", "Recommendation v2 is disabled.")
    try:
        payload = RecommendRequest.model_validate_json(await request.body())
    except ValidationError as exc:
        fields = sorted({".".join(str(p) for p in e["loc"]) or "body" for e in exc.errors(include_input=False)})
        return error(400, "bad_request", "Invalid recommendation request: " + ", ".join(fields[:5]))
    try:
        snapshot = load_snapshot()
    except (PolicyError, OSError, ValueError, KeyError, TypeError):
        log.error("recommendation-v2 policy unavailable")
        return error(503, "policy_unavailable", "The reviewed policy snapshot could not be loaded.")
    try:
        result = recommend(payload, snapshot)
    except ValueError:
        return error(400, "bad_request", "Unknown product or unsupported account inputs.")
    return JSONResponse(result.model_dump(mode="json", by_alias=True), headers=NO_STORE)
