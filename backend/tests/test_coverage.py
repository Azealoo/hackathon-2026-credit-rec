"""POST /v1/coverage (SPEC v2.1 §5.5, §7.3, §15.5; §15.7 step 12b).

Runs the 13 cases in fixtures/coverage_cases.json (D's hand-computed expectations, written before
this code) through the route, checks every response against contracts/coverage.response.schema.json,
and covers the window rules, copy, deadlines, COVERAGE_MODE and the privacy guard. Card values in
expectations are read from data/cards.json, never typed in here.
"""

import ast
import asyncio
import copy
import datetime as dt
import inspect
import json
import sys
import types
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator
from referencing import Registry
from referencing.jsonschema import DRAFT202012

from app import catalog, coverage
from app.main import app
from app.models import CoverageRequest, CoverageResponse

REPO = Path(__file__).resolve().parents[2]
CONTRACTS_DIR = REPO / "contracts"
CASES = json.loads((REPO / "fixtures" / "coverage_cases.json").read_text(encoding="utf-8"))["cases"]
BY_ID = {case["id"]: case for case in CASES}

SCHEMAS = {p.name: json.loads(p.read_text(encoding="utf-8")) for p in CONTRACTS_DIR.glob("*.schema.json")}
REGISTRY = Registry().with_resources((name, DRAFT202012.create_resource(s)) for name, s in SCHEMAS.items())
RESPONSE_VALIDATOR = Draft202012Validator(
    {"$ref": "coverage.response.schema.json"}, registry=REGISTRY, format_checker=Draft202012Validator.FORMAT_CHECKER
)

FU = "chase-freedom-unlimited"
DISCLAIMER = "Only the benefit administrator decides claims. Paywise never files for you."

client = TestClient(app)


def body_for(case_id: int, purchase: dict | None = None, incident: dict | None = None, as_of: str | None = None) -> dict:
    """The request for a fixture case, with optional field changes."""
    case = copy.deepcopy(BY_ID[case_id])
    case["purchase"].update(purchase or {})
    case["incident"].update(incident or {})
    return {"purchase": case["purchase"], "incident": case["incident"], "asOf": as_of or case["asOf"]}


def post(body: dict, fmt: str | None = None):
    url = "/v1/coverage" if fmt is None else f"/v1/coverage?format={fmt}"
    return client.post(url, json=body)


def verdict(body: dict) -> dict:
    response = post(body)
    assert response.status_code == 200, response.text
    data = response.json()
    assert [e.message for e in RESPONSE_VALIDATOR.iter_errors(data)] == []
    return data


def mismatches(case: dict, got: dict) -> list[str]:
    """Which of verdict, benefit, route, payoutCapUsd, citesSection, checklistIncludes differ."""
    expected, problems = case["expected"], []
    for key in ("verdict", "benefit", "route"):
        if got[key] != expected[key]:
            problems.append(f"{key}: {got[key]!r} != {expected[key]!r}")
    if got["limit"]["payoutCapUsd"] != expected["payoutCapUsd"]:
        problems.append(f"payoutCapUsd: {got['limit']['payoutCapUsd']!r} != {expected['payoutCapUsd']!r}")
    cited = got["citations"][0]["section"] if got["citations"] else None
    if cited != expected["citesSection"]:
        problems.append(f"citesSection: {cited!r} != {expected['citesSection']!r}")
    checklist = " | ".join(got["checklist"]).casefold()
    problems += [f"checklist lacks {p!r}" for p in expected["checklistIncludes"] if p.casefold() not in checklist]
    return problems


@pytest.fixture(scope="module")
def results() -> dict[int, dict]:
    return {case["id"]: verdict(body_for(case["id"])) for case in CASES}


# --------------------------------------------------------------------- the 13 fixture cases


def test_coverage_scoreboard(results, capsys):
    """§15.7 step 12b: ≥12/13; every not_covered case right; cases 3 and 13 cap at $500;
    every verdict cites a section and a version date."""
    passed = [c["id"] for c in CASES if not mismatches(c, results[c["id"]])]
    not_covered = [c for c in CASES if c["expected"]["verdict"] == "not_covered"]
    not_covered_right = [c for c in not_covered if not mismatches(c, results[c["id"]])]
    with capsys.disabled():
        print(f"\nCOVERAGE pass={len(passed)}/{len(CASES)} not_covered_right={len(not_covered_right)}/{len(not_covered)}")
    assert len(CASES) == 13
    assert len(passed) >= 12
    assert len(not_covered_right) == len(not_covered)
    assert results[3]["limit"]["payoutCapUsd"] == 500
    assert results[13]["limit"]["payoutCapUsd"] == 500
    for case_id, data in results.items():
        assert data["citations"], case_id
        assert all(c["section"] and c["versionDate"] for c in data["citations"]), case_id


@pytest.mark.parametrize("case", CASES, ids=lambda c: f"c{c['id']}")
def test_coverage_case(case, results):
    assert mismatches(case, results[case["id"]]) == []


@pytest.mark.parametrize("case", CASES, ids=lambda c: f"c{c['id']}")
def test_route_matches_pure_assess(case, results):
    """The route adds nothing: the verdict is assess() on the request (rules mode)."""
    pure = coverage.assess(CoverageRequest.model_validate(body_for(case["id"])))
    assert pure.model_dump(mode="json", by_alias=True) == results[case["id"]]
    CoverageResponse.model_validate(results[case["id"]])


@pytest.mark.parametrize("case", CASES, ids=lambda c: f"c{c['id']}")
def test_disclaimer_and_payout_cap_rules(case, results):
    data = results[case["id"]]
    assert data["disclaimer"] == DISCLAIMER
    if data["verdict"] != "may_be_eligible":
        assert data["limit"]["payoutCapUsd"] is None
    else:
        purchase = case["purchase"]
        charged = purchase["amountOnCardUsd"] if purchase["paidWith"] == "card_partial" else purchase["priceUsd"]
        prot = catalog.card(purchase["cardId"]).protection(data["benefit"])
        assert data["limit"]["payoutCapUsd"] == min(float(prot.limits.per_item_usd), charged)
        assert data["limit"]["perItemUsd"] == float(prot.limits.per_item_usd)


# --------------------------------------------------------------------- §5.5 copy


def test_copy_extended_warranty(results):
    data = results[1]
    assert data["headline"] == "May be eligible: Extended warranty (Freedom Unlimited)."
    # §5.5, word for word.
    assert data["why"] == "The maker's 1-year warranty ended Oct 17, 2027; the extra year runs to Oct 17, 2028."
    assert data["checklist"] == ["Itemized receipt", "Card statement showing the purchase",
                                 "Original warranty", "Repair estimate"]


def test_copy_purchase_protection_capped(results):
    for case_id in (3, 13):
        assert results[case_id]["headline"] == "May be eligible: Purchase protection, up to $500 of the $1,499."
        assert "120 days (90 in NY), to Feb 14, 2027" in results[case_id]["why"]
    assert results[13]["why"] == "Theft is covered within 120 days (90 in NY), to Feb 14, 2027."
    assert any("Police report" in item and "48 hours" in item for item in results[13]["checklist"])
    # Uncapped: the full $249 fits under $500, so the headline names the card instead.
    assert results[4]["headline"] == "May be eligible: Purchase protection (Freedom Unlimited)."


def test_copy_not_covered(results):
    assert results[2]["headline"] == "Not covered."
    assert results[2]["why"] == ("Damage was covered for 120 days (90 in NY), to Feb 14, 2027. "
                                 "The extended warranty covers failures, not drops.")
    assert results[2]["checklist"] == []
    assert results[2]["contact"] == {"administrator": None, "url": None}
    assert results[2]["deadline"] == {"type": "unknown", "date": None, "note": None}


def test_copy_maker_route(results):
    assert results[7]["headline"] == "Not covered by your card yet: it's still under the maker's warranty."
    assert results[7]["why"] == "Contact the manufacturer first. The card's extra year starts Oct 17, 2027."


def test_copy_need_more_info(results):
    data = results[5]
    assert data["headline"] == "Need more info."
    assert data["why"] == ("Theft and “involuntary and accidental parting” may be covered within 120 days (90 in NY); "
                           "simply losing something may not be. See the cited clause.")


def test_copy_partial_payment(results):
    assert results[12]["headline"] == "May be eligible: Extended warranty, up to $1,000 of the $1,499."
    assert "$1,000 paid on the card" in results[12]["why"]


# --------------------------------------------------------------------- deadlines, contact, citations


@pytest.mark.parametrize("case_id", [1, 3, 4, 5, 12, 13])
def test_deadlines_count_from_the_incident(case_id, results):
    case, data = BY_ID[case_id], results[case_id]
    notice = catalog.card(case["purchase"]["cardId"]).protection(data["benefit"]).notice
    incident = dt.date.fromisoformat(case["incident"]["date"])
    notify = incident + dt.timedelta(days=notice.notify_within_days)
    docs = incident + dt.timedelta(days=notice.submit_docs_within_days)
    assert data["deadline"]["type"] == "notify_by"
    assert data["deadline"]["date"] == notify.isoformat()
    assert data["deadline"]["note"] == (f"Notify by {coverage.fmt_date(notify)}; send documents by "
                                        f"{coverage.fmt_date(docs)}, or as soon as reasonably possible.")


def test_deadline_case_1_dates(results):
    assert results[1]["deadline"]["note"] == (
        "Notify by Mar 16, 2028; send documents by Apr 15, 2028, or as soon as reasonably possible.")


def test_deadline_passed_uses_as_of_not_today():
    data = verdict(body_for(1, as_of="2028-06-01"))
    assert data["verdict"] == "may_be_eligible"
    assert data["deadline"]["note"].endswith("That date has passed, so act as soon as you can.")


@pytest.mark.parametrize("case_id", [1, 3, 4, 5, 12, 13])
def test_contact_and_citation_come_from_cards_json(case_id, results):
    data = results[case_id]
    prot = catalog.card(BY_ID[case_id]["purchase"]["cardId"]).protection(data["benefit"])
    assert data["contact"] == {"administrator": prot.claim.administrator, "url": prot.claim.url}
    assert data["citations"] == [{
        "document": prot.source.document, "section": prot.source.section,
        "versionDate": prot.source.version_date.isoformat(), "quote": prot.source.quote,
        "verification": prot.verification.status,
    }]


@pytest.mark.parametrize("case_id", [6, 10])
def test_card_without_benefits_cites_the_dated_whole_document(case_id, results):
    card = catalog.card(BY_ID[case_id]["purchase"]["cardId"])
    assert card.protection("purchase_protection") is None and card.protection("extended_warranty") is None
    citation = results[case_id]["citations"][0]
    source = next(s for s in card.sources if s.section == citation["section"])
    assert source.section.startswith("whole") and source.version_date is not None
    assert citation["versionDate"] == source.version_date.isoformat()


# --------------------------------------------------------------------- window rules beyond the fixtures


def test_add_months_clamps_to_month_end():
    assert coverage.add_months(dt.date(2027, 1, 31), 1) == dt.date(2027, 2, 28)
    assert coverage.add_months(dt.date(2027, 10, 17), 12) == dt.date(2028, 10, 17)
    assert coverage.add_months(dt.date(2026, 11, 30), 3) == dt.date(2027, 2, 28)


def test_window_edges_are_inclusive():
    pp_end = dt.date(2026, 10, 17) + dt.timedelta(days=catalog.card(FU).protection("purchase_protection").window_days)
    on_last_day = verdict(body_for(13, incident={"date": pp_end.isoformat()},
                                   as_of=(pp_end + dt.timedelta(days=1)).isoformat()))
    assert on_last_day["verdict"] == "may_be_eligible"
    day_after = pp_end + dt.timedelta(days=1)
    after = verdict(body_for(13, incident={"date": day_after.isoformat()}, as_of=day_after.isoformat()))
    assert after["verdict"] == "not_covered"
    # Failure on the maker's last day is still the maker's; the day after starts the card's year.
    assert verdict(body_for(7, incident={"date": "2027-10-17"}, as_of="2027-10-18"))["route"] == "manufacturer"
    assert verdict(body_for(7, incident={"date": "2027-10-18"}, as_of="2027-10-19"))["route"] == "card_extended_warranty"


def ew_terms():
    return catalog.card(FU).protection("extended_warranty")


def test_extended_warranty_end_edge_is_inclusive():
    """Case 1's purchase: the card's year runs to maker end + extendsByMonths, that day included."""
    purchase = dt.date.fromisoformat(BY_ID[1]["purchase"]["purchaseDate"])
    maker_end = coverage.add_months(purchase, BY_ID[1]["purchase"]["manufacturerWarrantyMonths"])
    ew_end = coverage.add_months(maker_end, ew_terms().extends_by_months)
    assert ew_end == dt.date(2028, 10, 17)  # the fixture's workings say the same
    last = verdict(body_for(1, incident={"date": ew_end.isoformat()}, as_of=ew_end.isoformat()))
    assert (last["verdict"], last["route"]) == ("may_be_eligible", "card_extended_warranty")
    after = ew_end + dt.timedelta(days=1)
    late = verdict(body_for(1, incident={"date": after.isoformat()}, as_of=after.isoformat()))
    assert (late["verdict"], late["route"]) == ("not_covered", "none")
    assert late["why"].endswith(f"ended {coverage.fmt_date(ew_end)}.")


def test_maker_warranty_at_the_limit_still_gets_the_extended_warranty():
    """maxOriginalWarrantyMonths is inclusive: a maker's warranty of exactly that length is extended."""
    limit = ew_terms().max_original_warranty_months
    data = verdict(body_for(1, purchase={"manufacturerWarrantyMonths": limit},
                            incident={"date": "2030-01-01"}, as_of="2030-01-02"))
    assert (data["verdict"], data["route"]) == ("may_be_eligible", "card_extended_warranty")


def test_maker_warranty_one_month_over_the_limit_is_not_extended():
    """The over-limit check on its own: at limit + 1 months the maxTotalFromPurchaseMonths clamp
    would still leave the card's year running on the incident date, so only this check blocks it."""
    ew, purchase = ew_terms(), dt.date.fromisoformat(BY_ID[1]["purchase"]["purchaseDate"])
    months, day = ew.max_original_warranty_months + 1, dt.date(2030, 1, 1)
    maker_end = coverage.add_months(purchase, months)
    clamped_end = min(coverage.add_months(maker_end, ew.extends_by_months),
                      coverage.add_months(purchase, ew.max_total_from_purchase_months))
    assert maker_end < day <= clamped_end  # without the check, this day would be in the card's year
    data = verdict(body_for(1, purchase={"manufacturerWarrantyMonths": months},
                            incident={"date": day.isoformat()}, as_of=day.isoformat()))
    assert (data["verdict"], data["route"]) == ("not_covered", "none")
    assert data["why"] == (f"The extended warranty only extends maker's warranties of "
                           f"{coverage.months_phrase(ew.max_original_warranty_months)} or less.")


def test_windows_clamp_the_extended_warranty_to_max_total_from_purchase():
    """With the real terms the clamp never binds (36 + 12 = 48), so use synthetic terms."""
    purchase = dt.date(2026, 10, 17)
    ew = ew_terms().model_copy(update={"max_total_from_purchase_months": 18, "max_original_warranty_months": None})
    w = coverage.Windows(purchase, 12, None, ew)
    assert (w.ew_block, w.ew_end) == (None, coverage.add_months(purchase, 18))
    assert w.in_ew(coverage.add_months(purchase, 18)) and not w.in_ew(coverage.add_months(purchase, 18) + dt.timedelta(days=1))
    # A clamp at or before the maker's end leaves nothing to extend.
    capped = coverage.Windows(purchase, 12, None, ew.model_copy(update={"max_total_from_purchase_months": 12}))
    assert (capped.ew_block, capped.ew_end) == ("maker_too_long", None)
    unclamped = coverage.Windows(purchase, 12, None, ew.model_copy(update={"max_total_from_purchase_months": None}))
    assert unclamped.ew_end == coverage.add_months(purchase, 24)


def test_assess_uses_the_max_total_clamp(tmp_path):
    """End to end through assess() with a catalog whose Freedom Unlimited caps the total at 18 months."""
    raw = json.loads((REPO / "data" / "cards.json").read_text(encoding="utf-8"))
    card = next(c for c in raw["cards"] if c["id"] == FU)
    ew = next(p for p in card["protections"] if p["type"] == "extended_warranty")
    ew["maxTotalFromPurchaseMonths"] = 18
    cards_file = tmp_path / "cards.json"
    cards_file.write_text(json.dumps(raw), encoding="utf-8")
    cards = catalog.load_catalog(cards_file=cards_file)
    purchase = dt.date.fromisoformat(BY_ID[1]["purchase"]["purchaseDate"])
    end = coverage.add_months(purchase, 18)

    def at(day: dt.date) -> CoverageResponse:
        return coverage.assess(CoverageRequest.model_validate(
            body_for(1, incident={"date": day.isoformat()}, as_of=day.isoformat())), cards=cards)

    assert at(end).verdict == "may_be_eligible"
    assert f"runs to {coverage.fmt_date(end)}" in at(end).why
    assert at(end + dt.timedelta(days=1)).verdict == "not_covered"


def test_maker_route_copy_on_the_makers_last_day():
    """§5.5's "starts {maker end}" on any earlier day; on the last day itself, "starts after"."""
    assert verdict(body_for(7))["why"] == "Contact the manufacturer first. The card's extra year starts Oct 17, 2027."
    edge = verdict(body_for(7, incident={"date": "2027-10-17"}, as_of="2027-10-18"))
    assert edge["why"] == "Contact the manufacturer first. The card's extra year starts after Oct 17, 2027."
    assert verdict(body_for(7, incident={"date": "2027-10-16"}, as_of="2027-10-18"))["why"] == verdict(body_for(7))["why"]


@pytest.mark.parametrize("card_id", catalog.CATALOG.card_ids())
@pytest.mark.parametrize("cause", [*coverage.CAUSES, None])
def test_every_verdict_cites_a_section_and_the_best_dated_source(card_id, cause):
    """Beyond the fixtures: every card and cause cites a section, and a version date whenever
    data/cards.json has one to cite (a benefit's own source, or a dated "whole…" card source)."""
    card = catalog.card(card_id)
    data = verdict(body_for(1, purchase={"cardId": card_id}, incident={"cause": cause, "causeSource": None}))
    assert data["citations"]
    for citation in data["citations"]:
        assert citation["section"]
        if citation["versionDate"] is None:
            # Only when cards.json has nothing dated for this card to cite.
            assert not any(s.version_date and (s.section or "").startswith("whole") for s in card.sources)
            assert citation["section"] in {s.section for s in card.sources}


def test_new_york_note_after_day_90():
    data = verdict(body_for(13, incident={"date": "2027-02-01"}, as_of="2027-02-02"))
    assert data["verdict"] == "may_be_eligible"
    assert any(a.startswith("In NY, purchase protection lasts 90 days") for a in data["assumptions"])
    assert not any("In NY" in a for a in verdict(body_for(13))["assumptions"])


def test_maker_warranty_over_the_limit_gets_no_extended_warranty():
    ew = catalog.card(FU).protection("extended_warranty")
    months = ew.max_original_warranty_months + 12
    under = verdict(body_for(1, purchase={"manufacturerWarrantyMonths": months}))
    assert (under["verdict"], under["route"]) == ("not_covered", "manufacturer")
    assert under["headline"] == "Not covered by your card: it's still under the maker's warranty."
    late = dt.date(2026, 10, 17) + dt.timedelta(days=31 * (months + 2))
    after = verdict(body_for(1, purchase={"manufacturerWarrantyMonths": months},
                             incident={"date": late.isoformat()}, as_of=late.isoformat()))
    assert (after["verdict"], after["route"]) == ("not_covered", "none")
    assert after["citations"][0]["section"] == ew.source.section


def test_null_maker_warranty_means_no_extended_warranty():
    data = verdict(body_for(1, purchase={"manufacturerWarrantyMonths": None}))
    assert data["verdict"] == "not_covered"
    assert "nothing to extend" in data["why"]
    assert any("treats it as none" in a for a in data["assumptions"])


def test_assumed_maker_warranty_is_labeled():
    data = verdict(body_for(1, purchase={"manufacturerWarrantySource": "assumed"}))
    assert data["verdict"] == "may_be_eligible"
    assert any("Don't know" in a for a in data["assumptions"])


def test_partial_payment_without_amount_caps_at_price_and_says_so():
    data = verdict(body_for(1, purchase={"paidWith": "card_partial", "amountOnCardUsd": None}))
    assert data["limit"]["payoutCapUsd"] == 1499.0
    assert any("at most that part" in a for a in data["assumptions"])


def test_theft_r9_never_routes_to_the_maker():
    """R9: theft under the maker's warranty goes straight to purchase protection."""
    assert verdict(body_for(13))["route"] == "card_purchase_protection"
    assert verdict(body_for(9))["route"] == "none"


def test_porch_theft_adds_carrier_line():
    data = verdict(body_for(13, incident={"description": "Package taken from my porch."}))
    assert "Claim with the carrier or store first" in data["checklist"]
    assert "Claim with the carrier or store first" not in verdict(body_for(13))["checklist"]


@pytest.mark.parametrize(
    "changes, verdict_, benefit",
    [
        pytest.param({"condition": "renewed"}, "need_more_info", "extended_warranty", id="renewed-with-warranty"),
        pytest.param({"paidWith": "bnpl"}, "need_more_info", "extended_warranty", id="bnpl"),
        pytest.param({"condition": "unknown"}, "may_be_eligible", "extended_warranty", id="unknown-condition"),
        pytest.param({"status": "planned"}, "may_be_eligible", "extended_warranty", id="planned"),
    ],
)
def test_purchase_terms(changes, verdict_, benefit):
    data = verdict(body_for(1, purchase=changes))
    assert (data["verdict"], data["benefit"]) == (verdict_, benefit)
    if verdict_ == "need_more_info":
        assert data["limit"]["payoutCapUsd"] is None
    else:
        assert data["assumptions"]


def test_cosmetic_damage_needs_more_info_in_window():
    data = verdict(body_for(3, incident={"cause": "cosmetic"}))
    assert (data["verdict"], data["benefit"]) == ("need_more_info", "purchase_protection")


def test_card_without_extended_warranty_under_maker_routes_to_maker():
    data = verdict(body_for(6, incident={"date": "2027-06-17"}, as_of="2027-06-18"))
    assert (data["verdict"], data["route"]) == ("not_covered", "manufacturer")
    assert data["headline"] == "Not covered by your card: it's still under the maker's warranty."
    assert data["citations"][0]["section"].startswith("whole")


def test_phone_on_a_card_with_cell_phone_protection_needs_more_info():
    data = verdict(body_for(10, purchase={"category": "phones"}, incident={"cause": "theft"}))
    assert (data["verdict"], data["benefit"]) == ("need_more_info", "none")
    cpp = catalog.card("wf-active-cash").protection("cell_phone_protection")
    assert data["citations"][0]["section"] == cpp.source.section


# --------------------------------------------------------------------- COVERAGE_MODE and the classifier


def fake_llm(monkeypatch, classify) -> list[str]:
    """Install a stand-in app.llm module; returns the descriptions it was asked to classify."""
    calls: list[str] = []

    if inspect.iscoroutinefunction(classify):
        async def classify_cause(description):
            calls.append(description)
            return await classify(description)
    else:
        def classify_cause(description):
            calls.append(description)
            return classify(description)

    module = types.ModuleType("app.llm")
    module.classify_cause = classify_cause
    monkeypatch.setitem(sys.modules, "app.llm", module)
    return calls


def explode(_description):
    raise AssertionError("classifier must not be called")


def test_rules_mode_null_cause_asks_to_pick(monkeypatch):
    monkeypatch.setenv("COVERAGE_MODE", "rules")
    calls = fake_llm(monkeypatch, explode)
    data = verdict(body_for(13, incident={"cause": None, "causeSource": None}))
    assert (data["verdict"], data["benefit"], data["route"]) == ("need_more_info", "none", "none")
    assert data["why"].startswith("Pick what happened")
    assert data["citations"] and calls == []


def test_default_mode_is_rules(monkeypatch):
    monkeypatch.delenv("COVERAGE_MODE", raising=False)
    fake_llm(monkeypatch, explode)
    assert verdict(body_for(13, incident={"cause": None, "causeSource": None}))["verdict"] == "need_more_info"


def test_llm_mode_classifies_a_null_cause(monkeypatch):
    monkeypatch.setenv("COVERAGE_MODE", "llm")

    async def classify(_description):
        return "theft"

    calls = fake_llm(monkeypatch, classify)
    data = verdict(body_for(13, incident={"cause": None, "causeSource": None}))
    assert mismatches(BY_ID[13], data) == []
    assert calls == [BY_ID[13]["incident"]["description"]]
    assert any("“Stolen”" in a for a in data["assumptions"])


def test_llm_mode_sets_cause_source_llm(monkeypatch):
    monkeypatch.setenv("COVERAGE_MODE", "llm")
    fake_llm(monkeypatch, lambda _d: {"cause": "failure"})
    req = CoverageRequest.model_validate(body_for(1, incident={"cause": None, "causeSource": None}))
    classified, failed = asyncio.run(coverage.classify_if_needed(req))
    assert not failed
    assert (classified.incident.cause, classified.incident.cause_source) == ("failure", "llm")
    assert asyncio.run(coverage.check(req)).verdict == "may_be_eligible"


@pytest.mark.parametrize("answer", [None, "dropped", 42, RuntimeError("down")], ids=["none", "bad", "type", "error"])
def test_llm_mode_classifier_failure_asks_to_pick(monkeypatch, answer):
    monkeypatch.setenv("COVERAGE_MODE", "llm")

    def classify(_description):
        if isinstance(answer, Exception):
            raise answer
        return answer

    fake_llm(monkeypatch, classify)
    data = verdict(body_for(13, incident={"cause": None, "causeSource": None}))
    assert data["verdict"] == "need_more_info"
    assert data["why"].startswith("Paywise couldn't tell what happened")


def test_llm_mode_keeps_a_user_confirmed_cause(monkeypatch):
    monkeypatch.setenv("COVERAGE_MODE", "llm")
    calls = fake_llm(monkeypatch, explode)
    assert mismatches(BY_ID[2], verdict(body_for(2))) == []
    assert calls == []


def test_llm_is_imported_lazily():
    tree = ast.parse(Path(coverage.__file__).read_text(encoding="utf-8"))
    top_level = [n for n in tree.body if isinstance(n, (ast.Import, ast.ImportFrom))]
    names = {getattr(n, "module", None) for n in top_level} | {a.name for n in top_level for a in n.names}
    assert "app.llm" not in names and "llm" not in names


def test_coverage_never_reads_the_clock():
    source = Path(coverage.__file__).read_text(encoding="utf-8")
    for call in ("today(", "now(", "utcnow(", "time.time(", "localtime("):
        assert call not in source


# --------------------------------------------------------------------- route errors and privacy


def test_privacy_rejects_long_digit_runs():
    run = "4" * 6 + "1" * 6  # 12 digits, built so this file passes test_privacy
    response = post(body_for(13, incident={"description": f"Stolen, card {run}"}))
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "privacy_rejected"
    assert run not in response.text


@pytest.mark.parametrize(
    "body",
    [
        pytest.param(body_for(1, purchase={"cardId": "no-such-card"}), id="unknown-card"),
        pytest.param(body_for(1, purchase={"category": "no_such_category"}), id="unknown-category"),
        pytest.param(body_for(1, incident={"date": "2026-10-01"}), id="incident-before-purchase"),
        pytest.param(body_for(1, as_of="2027-12-01"), id="incident-after-as-of"),
        pytest.param(body_for(1, purchase={"last4": "1234"}), id="extra-field"),
        pytest.param({"purchase": {}}, id="missing-fields"),
    ],
)
def test_bad_requests(body):
    response = post(body)
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "bad_request"
    assert "1234" not in response.json()["error"]["message"]


lenient_client = TestClient(app, raise_server_exceptions=False)


@pytest.mark.parametrize(
    "body",
    [
        pytest.param(body_for(1, purchase={"manufacturerWarrantyMonths": 100000}), id="warranty-100000-months"),
        pytest.param(body_for(13, purchase={"purchaseDate": "9999-12-01"}, incident={"date": "9999-12-01"},
                              as_of="9999-12-02"), id="theft-window-past-9999"),
        pytest.param(body_for(1, purchase={"purchaseDate": "9999-01-01"}, incident={"date": "9999-06-01"},
                              as_of="9999-06-02"), id="failure-window-past-9999"),
        pytest.param(body_for(5, purchase={"purchaseDate": "9999-12-30"}, incident={"date": "9999-12-30"},
                              as_of="9999-12-31"), id="loss-window-past-9999"),
    ],
)
@pytest.mark.parametrize("fmt", ["json", "html"])
def test_dates_past_9999_are_bad_requests_not_server_errors(body, fmt):
    response = lenient_client.post(f"/v1/coverage?format={fmt}", json=body)
    assert response.status_code == 400
    assert response.json()["error"] == {"code": "bad_request", "message": coverage.OUT_OF_RANGE}


@pytest.mark.parametrize("fragment", [b'"priceUsd": 1e400', b'"priceUsd": Infinity', b'"priceUsd": NaN'])
def test_non_finite_prices_are_bad_requests(fragment):
    text = json.dumps(body_for(13)).encode()
    assert b'"priceUsd": 1499.0' in text
    response = lenient_client.post("/v1/coverage", content=text.replace(b'"priceUsd": 1499.0', fragment),
                                   headers={"content-type": "application/json"})
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "bad_request"


@pytest.mark.parametrize("price", [1e26, 1e308])
@pytest.mark.parametrize("fmt", ["json", "html"])
def test_huge_finite_prices_still_get_a_verdict(price, fmt):
    """Any finite price formats to cents: Decimal's default 28 digits overflowed at 1e26."""
    response = lenient_client.post(f"/v1/coverage?format={fmt}", json=body_for(13, purchase={"priceUsd": price}))
    assert response.status_code == 200
    if fmt == "json":
        data = response.json()
        assert [e.message for e in RESPONSE_VALIDATOR.iter_errors(data)] == []
        assert data["limit"]["payoutCapUsd"] == float(catalog.card(FU).protection("purchase_protection").limits.per_item_usd)
    assert coverage.fmt_usd_cents(price).endswith(".00")


def test_invalid_json_is_a_bad_request():
    response = client.post("/v1/coverage", content=b"{not json", headers={"content-type": "application/json"})
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "bad_request"


def test_format_param():
    assert post(body_for(1)).headers["content-type"].startswith("application/json")
    assert post(body_for(1), "json").headers["content-type"].startswith("application/json")
    html = post(body_for(1), "html")
    assert html.status_code == 200 and html.headers["content-type"].startswith("text/html")
    assert post(body_for(1), "xml").status_code == 422
    assert post(body_for(1)).headers["cache-control"] == "no-store"


# --------------------------------------------------------------------- incident echo (ruling R17)
# §5.5 "The LLM pre-selects a chip; the user confirms": the response says which cause it used and
# where it came from, so a null-cause request also works as the claim screen's classify call.


def echoed(data: dict) -> tuple:
    return data["incident"]["cause"], data["incident"]["causeSource"]


@pytest.mark.parametrize("case", CASES, ids=lambda c: f"c{c['id']}")
def test_every_verdict_echoes_the_user_confirmed_cause(case, results):
    assert echoed(results[case["id"]]) == (case["incident"]["cause"], "user_confirmed")


@pytest.mark.parametrize("cause", coverage.CAUSES)
def test_llm_cause_is_echoed_whatever_the_verdict(monkeypatch, cause):
    """Case 13 (day 30, Freedom Unlimited): the classifier's answer comes back with causeSource "llm",
    also when the verdict is need_more_info (loss, cosmetic, unknown) or the maker's route (failure)."""
    monkeypatch.setenv("COVERAGE_MODE", "llm")
    calls = fake_llm(monkeypatch, lambda _d: cause)
    data = verdict(body_for(13, incident={"cause": None, "causeSource": None}))
    assert echoed(data) == (cause, "llm")
    assert calls == [BY_ID[13]["incident"]["description"]]
    expected = {"failure": "not_covered", "accidental_damage": "may_be_eligible", "theft": "may_be_eligible",
                "loss": "need_more_info", "cosmetic": "need_more_info", "unknown": "need_more_info"}
    assert data["verdict"] == expected[cause]


def test_llm_cause_matches_a_confirmed_cause_verdict(monkeypatch):
    """Classifying, then confirming the same chip, gives the same verdict; only the source and the
    "Paywise read the cause as" assumption differ."""
    monkeypatch.setenv("COVERAGE_MODE", "llm")
    fake_llm(monkeypatch, lambda _d: "failure")
    classified = verdict(body_for(1, incident={"cause": None, "causeSource": None}))
    confirmed = verdict(body_for(1))
    assert echoed(classified) == ("failure", "llm") and echoed(confirmed) == ("failure", "user_confirmed")
    for key in ("verdict", "benefit", "route", "headline", "limit", "checklist", "deadline"):
        assert classified[key] == confirmed[key], key
    assert any("“Stopped working”" in a for a in classified["assumptions"])
    assert not any("Paywise read the cause" in a for a in confirmed["assumptions"])


@pytest.mark.parametrize("answer", [None, "dropped", RuntimeError("down")], ids=["none", "bad", "error"])
def test_classifier_failure_echoes_no_cause(monkeypatch, answer):
    monkeypatch.setenv("COVERAGE_MODE", "llm")

    def classify(_description):
        if isinstance(answer, Exception):
            raise answer
        return answer

    fake_llm(monkeypatch, classify)
    data = verdict(body_for(13, incident={"cause": None, "causeSource": None}))
    assert data["verdict"] == "need_more_info"
    assert echoed(data) == (None, None)


@pytest.mark.parametrize("source", [None, "user_confirmed", "llm"])
def test_rules_mode_null_cause_echoes_no_cause(monkeypatch, source):
    """No cause was used, so no source either, whatever the request claimed."""
    monkeypatch.setenv("COVERAGE_MODE", "rules")
    fake_llm(monkeypatch, explode)
    data = verdict(body_for(13, incident={"cause": None, "causeSource": source}))
    assert data["verdict"] == "need_more_info"
    assert echoed(data) == (None, None)


@pytest.mark.parametrize("source", [None, "llm"])
def test_a_sent_cause_is_echoed_with_its_source(monkeypatch, source):
    """A non-null cause is never re-classified; it comes back with the source the request gave."""
    monkeypatch.setenv("COVERAGE_MODE", "llm")
    fake_llm(monkeypatch, explode)
    assert echoed(verdict(body_for(13, incident={"causeSource": source}))) == ("theft", source)


def test_html_shows_the_llm_cause_as_its_chip(monkeypatch):
    monkeypatch.setenv("COVERAGE_MODE", "llm")
    fake_llm(monkeypatch, lambda _d: "theft")
    html = post(body_for(13, incident={"cause": None, "causeSource": None}), "html")
    assert html.status_code == 200
    assert f"Stolen · {coverage.fmt_date(dt.date.fromisoformat(BY_ID[13]['incident']['date']))}" in html.text


def test_incident_is_optional_and_strict_in_the_contract():
    example = json.loads((CONTRACTS_DIR / "coverage.response.example.json").read_text(encoding="utf-8"))
    without = {k: v for k, v in example.items() if k != "incident"}
    assert RESPONSE_VALIDATOR.is_valid(without) and CoverageResponse.model_validate(without).incident is None
    assert RESPONSE_VALIDATOR.is_valid({**example, "incident": {"cause": None, "causeSource": None}})
    for bad in ({"cause": "dropped", "causeSource": "llm"}, {"cause": "theft", "causeSource": "user"},
                {"cause": "theft"}, {"cause": "theft", "causeSource": "llm", "confidence": 0.9}):
        assert not RESPONSE_VALIDATOR.is_valid({**example, "incident": bad}), bad
        with pytest.raises(ValueError):
            CoverageResponse.model_validate({**example, "incident": bad})
