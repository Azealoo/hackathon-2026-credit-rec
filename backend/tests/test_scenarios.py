"""fixtures/scenarios.json (22 scenarios, written by D before the engine) through the §7.2 engine.

SPEC §13 / §15.7 step 4: ≥20/22 correct picks, 0 false switches, 0 protection drops, and
scenarios 5, 21 and 22 (the protection-loss guard) must pass. Never edit a fixture to make a
test pass: a fixture that contradicts SPEC §7.2 gets xfail(strict=True) with the reason.
"""

import datetime as dt
import json
from decimal import Decimal
from pathlib import Path

import pytest

from app import catalog, engine
from app.models import Cart, WalletCard

REPO = Path(__file__).resolve().parents[2]
FIXTURES = REPO / "fixtures"
DATA = json.loads((FIXTURES / "scenarios.json").read_text(encoding="utf-8"))
SCENARIOS = DATA["scenarios"]
DEMO_DATE = dt.date.fromisoformat(DATA["demoDate"])
WALLETS = {w["id"]: w for w in json.loads((FIXTURES / "wallets.json").read_text(encoding="utf-8"))["wallets"]}
MUST_PASS = {5, 21, 22}


def wallet_cards(wallet_id: str) -> list[WalletCard]:
    """The first card listed is the default (fixtures/wallets.json)."""
    return [WalletCard(card_id=c["cardId"], is_default=i == 0) for i, c in enumerate(WALLETS[wallet_id]["cards"])]


def run(scenario: dict) -> engine.EngineResult:
    cart = dict(scenario["cart"])
    screen_type = cart.pop("screenType")
    return engine.decide(screen_type, Cart.model_validate(cart), wallet_cards(scenario["wallet"]), DEMO_DATE)


def observed(scenario: dict, result: engine.EngineResult) -> dict:
    d = result.decision
    return {
        "kind": d.kind, "reason": d.reason, "presentation": d.presentation,
        "recommendedCardId": d.recommended_card_id, "cashBestCardId": d.cash_best_card_id,
        "cashByCard": d.cash.by_card if d.cash else None,
        "cashDeltaVsCashBest": d.cash.delta_vs_cash_best if d.cash else None,
        "cashDeltaVsDefault": d.cash.delta_vs_default if d.cash else None,
        "protectionsGained": [p.type for p in d.protections_gained],
        "eligibilityNotes": d.eligibility_notes,
        "paymentPath": d.payment_path,
    }


def mismatches(scenario: dict, result: engine.EngineResult) -> dict:
    """Every expected field (and the scenario's paymentPath) that the engine got wrong."""
    got = observed(scenario, result)
    expected = dict(scenario["expected"], paymentPath=scenario["paymentPath"])
    return {key: {"expected": value, "got": got[key]} for key, value in expected.items() if got[key] != value}


def false_switch(scenario: dict, result: engine.EngineResult) -> bool:
    """A switch where the fixture expects keep / no_checkout, or a switch to a different card."""
    d, e = result.decision, scenario["expected"]
    return d.kind == "switch" and (e["kind"] != "switch" or d.recommended_card_id != e["recommendedCardId"])


def protection_drop(scenario: dict, result: engine.EngineResult) -> bool:
    """The recommended card lacks an eligible PP/EW type the default has on a qualifying item.
    Computed straight from data/cards.json, independently of the engine's own eligibility code."""
    d = result.decision
    if d.recommended_card_id is None or d.recommended_card_id == d.default_card_id:
        return False

    def types(card_id: str, item: dict) -> set[str]:
        category = catalog.item_category(item["category"])
        relevant = set()
        if category.theft_damage_relevant:
            relevant.add("purchase_protection")
        if category.warranty_relevant:
            relevant.add("extended_warranty")
        out = set()
        for p in catalog.card(card_id).protections:
            allowed = p.eligibility.conditions_allowed
            if (p.type in relevant and (allowed is None or item["condition"] in allowed)
                    and item["category"] not in p.eligibility.excluded_categories):
                out.add(p.type)
        return out

    for item in scenario["cart"]["items"]:
        if Decimal(str(item["priceUsd"])) < 100 or item["isGiftCard"] or item["isServicePlan"]:
            continue
        if types(d.default_card_id, item) - types(d.recommended_card_id, item):
            return True
    return False


RESULTS = {s["id"]: run(s) for s in SCENARIOS}


def test_there_are_22_scenarios():
    assert [s["id"] for s in SCENARIOS] == list(range(1, 23))


@pytest.mark.parametrize("scenario", SCENARIOS, ids=[f"{s['id']:02d}-{s['title']}" for s in SCENARIOS])
def test_scenario(scenario):
    assert mismatches(scenario, RESULTS[scenario["id"]]) == {}


def test_scenario_summary(capsys):
    passed = [s["id"] for s in SCENARIOS if not mismatches(s, RESULTS[s["id"]])]
    false_switches = [s["id"] for s in SCENARIOS if false_switch(s, RESULTS[s["id"]])]
    drops = [s["id"] for s in SCENARIOS if protection_drop(s, RESULTS[s["id"]])]
    with capsys.disabled():
        print(f"\nSCENARIOS pass={len(passed)}/{len(SCENARIOS)} false_switches={len(false_switches)} "
              f"protection_drops={len(drops)}")
    assert len(passed) >= 20
    assert false_switches == []
    assert drops == []
    assert MUST_PASS <= set(passed)


def test_s1_copy_is_exact():
    """§6.3 Switch, protection, with the §15.5 example's placeholders."""
    copy = RESULTS[1].decision.copy_
    assert copy.line1 == "Use Freedom ••{last4:chase-freedom-unlimited}"
    assert copy.line2 == "Adds a warranty year + $500 theft cover"
    assert copy.line3 == "$7.49 less cash back than Active Cash"
    assert copy.instruction == "Change card to Visa ••{last4:chase-freedom-unlimited}, then place order"
    assert copy.primary_button == "Paying with Freedom"


def test_renewed_flip_copy():
    """§12.1 optional beat: Use Active Cash / $10.99 more cash back than Apple Card / the note."""
    copy = RESULTS[2].decision.copy_
    assert copy.line1 == "Use Active Cash ••{last4:wf-active-cash}"
    assert copy.line2 == "$10.99 more cash back than Apple Card"
    assert copy.line3 == "Renewed, no warranty: no card covers it"
    assert copy.primary_button == "Paying with Active Cash"


def test_pick_also_cash_best_copy():
    for scenario_id in (16, 17):
        assert RESULTS[scenario_id].decision.copy_.line3 == "Also earns the most cash back here"


def test_keep_copy_variants():
    assert RESULTS[4].decision.copy_.line2 == "Switching gains under $5 here"
    assert RESULTS[5].decision.copy_.line1 == "✓ Keep Freedom ••{last4:chase-freedom-unlimited}"
    assert RESULTS[5].decision.copy_.line3 == "Save it so you can claim later"
    assert RESULTS[6].decision.copy_.line2 == "Best of your 2 cards here"
    assert RESULTS[8].decision.copy_.line1 == "✓ Apple Card: use Apple Pay"
    assert RESULTS[8].decision.copy_.line2 == "3% ($5.40) with Apple Pay vs 1% typed"
    assert RESULTS[8].decision.instruction == "use_apple_pay"
    assert RESULTS[13].decision.copy_.line1 == "No checkout total found"
    assert RESULTS[15].decision.copy_.line1 == "Already paid?"
    assert RESULTS[18].decision.copy_.line2 == "Couldn't read the items, so no switch"


def test_purchase_draft_dates_for_s1():
    draft = RESULTS[1].purchase_draft
    assert draft is not None and draft.card_id == "chase-freedom-unlimited"
    by_type = {c.type: c for c in draft.coverage}
    assert by_type["purchase_protection"].until == dt.date(2027, 2, 14)
    assert by_type["purchase_protection"].limit_usd == 500
    assert by_type["extended_warranty"].until == dt.date(2028, 10, 17)
    assert by_type["extended_warranty"].assumes_manufacturer_warranty_months == 12


def test_snippet_states_save_a_draft_and_island_states_dont():
    for scenario in SCENARIOS:
        result = RESULTS[scenario["id"]]
        assert (result.purchase_draft is not None) == (result.decision.presentation == "snippet"), scenario["id"]
