"""Opt-in structured recommendation API. Uses no OCR, LLM, network, or persistence."""

import logging
import os

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse
from pydantic import ValidationError

from app.recommendation_v2.engine import recommend
from app.recommendation_v2.models import ProductCatalog, ProductSummary, RecommendRequest
from app.recommendation_v2.policy import PolicyError, load_snapshot

router = APIRouter(tags=["recommendation-v2"])
log = logging.getLogger(__name__)
NO_STORE = {"Cache-Control": "no-store"}


def error(status: int, code: str, message: str):
    return JSONResponse({"error": {"code": code, "message": message}}, status_code=status, headers=NO_STORE)


@router.get("/v2/catalog")
async def product_catalog():
    if os.environ.get("RECOMMENDATION_V2_ENABLED") != "1":
        return error(404, "feature_disabled", "Recommendation v2 is disabled.")
    try:
        snapshot = load_snapshot()
        products = []
        source_urls = {s["id"]: s["url"] for s in snapshot.sources}
        for product_id in snapshot.product_ids:
            card = snapshot.card(product_id)
            categories = set()
            for rule in card["reward_rules"]:
                if not rule.get("enabled", True):
                    continue
                match = rule["match"]
                if "issuer_category" in match:
                    categories.add(match["issuer_category"])
                categories.update(match.get("issuer_category_in", []))
            products.append(ProductSummary(id=card["id"], issuer=card["issuer"], product=card["product"],
                category_options=sorted(categories),
                membership_bonus_options_bps=card.get("membership_bonus", {}).get("allowed_bonus_bps", []),
                terms_urls=[source_urls[sid] for sid in card["source_ids"]], observed_at=card["observed_at"]))
        result = ProductCatalog(policy_version=snapshot.version, products=products)
    except (PolicyError, OSError, ValueError, KeyError, TypeError):
        return error(503, "policy_unavailable", "The reviewed policy snapshot could not be loaded.")
    return JSONResponse(result.model_dump(mode="json", by_alias=True), headers=NO_STORE)


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
