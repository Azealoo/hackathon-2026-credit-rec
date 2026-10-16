"""POST /v1/coverage?format=json|html (SPEC v2.1 §5.5, §15.5; §15.7 steps 12b and 12c).

JSON is the contracts/coverage.response.schema.json body. HTML renders the same verdict through
templates/verdict.html (Jinja2, autoescaped) for the app's in-app web view: always dark, phone
width, no scripts and no external resources.

The JSON carries `incident` {"cause", "causeSource"}: the cause the verdict used (ruling R17). With
COVERAGE_MODE=llm, a request whose cause is null comes back with the LLM's cause and causeSource
"llm", whatever the verdict, so the claim screen can pre-select that chip before the user confirms
it (§5.5). The HTML shows the same cause as its chip label.

Request bodies are never logged. A body with a run of 12+ digits is rejected with 400
privacy_rejected (§15.5), before it is parsed.
"""

import logging
import re
from pathlib import Path
from typing import Literal
from urllib.parse import urlsplit

from fastapi import APIRouter, Query, Request
from fastapi.responses import HTMLResponse, JSONResponse
from jinja2 import Environment, FileSystemLoader, StrictUndefined
from pydantic import ValidationError

from app import catalog, coverage
from app.models import CoverageRequest, CoverageResponse

router = APIRouter(tags=["coverage"])
log = logging.getLogger(__name__)

LONG_DIGIT_RUN = re.compile(rb"\d{12,}")
TEMPLATES_DIR = Path(__file__).resolve().parent / "templates"

_env = Environment(
    loader=FileSystemLoader(TEMPLATES_DIR),
    autoescape=True,  # every value is escaped, including the user's own description
    undefined=StrictUndefined,
    trim_blocks=True,
    lstrip_blocks=True,
)

# The page loads nothing: inline CSS, inline SVG, no scripts.
CSP = "default-src 'none'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'"
NO_STORE = {"Cache-Control": "no-store"}
HTML_HEADERS = {**NO_STORE, "Content-Security-Policy": CSP, "X-Content-Type-Options": "nosniff"}

VERDICT_LABELS = {
    "may_be_eligible": "May be eligible",
    "not_covered": "Not covered",
    "need_more_info": "Need more info",
}


def _error(status: int, code: str, message: str) -> JSONResponse:
    return JSONResponse({"error": {"code": code, "message": message}}, status_code=status, headers=NO_STORE)


def _field(error: dict) -> str:
    """'purchase.priceUsd' from a pydantic error location (never the input value)."""
    return ".".join(str(part) for part in error.get("loc", ())) or "body"


@router.post("/v1/coverage")
async def post_coverage(request: Request, fmt: Literal["json", "html"] = Query("json", alias="format")):
    body = await request.body()
    if LONG_DIGIT_RUN.search(body):
        return _error(400, "privacy_rejected", "The request has a run of 12 or more digits.")
    try:
        req = CoverageRequest.model_validate_json(body)
    except ValidationError as exc:
        fields = sorted({_field(e) for e in exc.errors(include_input=False)})
        return _error(400, "bad_request", "Invalid coverage request: " + ", ".join(fields))
    try:
        req, classifier_failed = await coverage.classify_if_needed(req)
        result = coverage.assess(req, classifier_failed=classifier_failed)
        if fmt == "html":
            return HTMLResponse(render_verdict(req, result), headers=HTML_HEADERS)
        return JSONResponse(result.model_dump(mode="json", by_alias=True), headers=NO_STORE)
    except coverage.CoverageInputError as exc:
        return _error(400, "bad_request", str(exc))
    except (ArithmeticError, ValueError) as exc:
        # Safety net for a date or amount out of range that coverage.py didn't foresee
        # (OverflowError, decimal.InvalidOperation, date ValueError): a 400, not a 500.
        # Logged by type only, never the request.
        log.warning("coverage: request out of range (%s)", type(exc).__name__)
        return _error(400, "bad_request", "A date or amount in the request is out of range.")


# --- HTML ------------------------------------------------------------------------------------


def _citation_parts(citation) -> list[str]:
    """[document, section, 'version {date}']: shown as '{document} · {section} · version {date}' (§5.5)."""
    version = f"version {coverage.fmt_date(citation.version_date)}" if citation.version_date else "no version date"
    return [part for part in (citation.document, citation.section, version) if part]


def _payout(req: CoverageRequest, result: CoverageResponse) -> dict | None:
    limit = result.limit
    if result.verdict != "may_be_eligible":
        return None
    if limit.payout_cap_usd is None:
        # card_partial without amountOnCardUsd: the part paid on the card is unknown, so show the benefit's own cap
        # and say the payout is also limited to that part (§5.5).
        benefit_cap = limit.per_item_usd if limit.per_item_usd is not None else limit.per_claim_usd
        if req.purchase.paid_with != "card_partial" or benefit_cap is None:
            return None
        kind = "per-item" if limit.per_item_usd is not None else "per-claim"
        return {
            "amount": coverage.fmt_usd_cents(benefit_cap),
            "note": f"The {kind} cap. The payout is also at most the repair or replacement cost and the part "
                    "paid on the card.",
        }
    charged = "the part paid on the card" if req.purchase.paid_with == "card_partial" else "the amount charged to the card"
    if limit.per_item_usd is not None:
        cap = f", and the {coverage.fmt_usd(limit.per_item_usd)} per-item cap"
    elif limit.per_claim_usd is not None:
        cap = f", and the {coverage.fmt_usd(limit.per_claim_usd)} per-claim cap"
    else:
        cap = ""
    return {
        "amount": coverage.fmt_usd_cents(limit.payout_cap_usd),
        "note": f"The lesser of the repair or replacement cost, {charged}{cap}.",
    }


def _contact(result: CoverageResponse) -> dict | None:
    url = result.contact.url
    if not url:
        return None
    parts = urlsplit(url)
    if parts.scheme not in ("https", "http") or not parts.hostname:
        return None
    return {"url": url, "host": parts.hostname.removeprefix("www."), "administrator": result.contact.administrator}


def verdict_view(req: CoverageRequest, result: CoverageResponse) -> dict:
    """Display strings for templates/verdict.html. All formatting happens here, in code."""
    purchase, incident = req.purchase, req.incident
    card = catalog.card(purchase.card_id)
    cause = coverage.CAUSE_LABELS.get(incident.cause) if incident.cause else "Cause not picked"
    return {
        "verdict": result.verdict,
        "verdict_label": VERDICT_LABELS[result.verdict],
        "headline": result.headline,
        "why": result.why,
        "item": purchase.item,
        "meta": " · ".join([
            coverage.card_name(card),
            coverage.fmt_usd_cents(purchase.price_usd),
            f"bought {coverage.fmt_date(purchase.purchase_date)}",
        ]),
        "incident": f"{cause} · {coverage.fmt_date(incident.date)}",
        "description": incident.description.strip(),
        "payout": _payout(req, result),
        "notice": result.deadline.note,
        "assumptions": result.assumptions,
        "checklist": result.checklist,
        "citations": [{"parts": _citation_parts(c), "quote": c.quote} for c in result.citations],
        "contact": _contact(result),
        "disclaimer": result.disclaimer,
    }


def render_verdict(req: CoverageRequest, result: CoverageResponse) -> str:
    return _env.get_template("verdict.html").render(v=verdict_view(req, result))
