"""Real calculations plus scenario-only reviewed profiles, never client-supplied insurance."""

from copy import deepcopy
from datetime import date
import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator
from pydantic import ValidationError

from app.main import app
from app import middleware
from app.recommendation_v2.engine import (Coverage, Evaluated, ProtectionProfile, difference,
                                         evaluate, protection_guard, recommend, select)
from app.recommendation_v2.models import (CardOption, Interval, OptionEstimate, Preferences,
                                         ProductCatalog, Purchase, RecommendRequest, RecommendResponse)
from app.recommendation_v2.policy import PolicyError, SEED_PATH, load_snapshot, read_snapshot

REPO = Path(__file__).resolve().parents[2]
VECTORS = {v["id"]: v for v in json.loads((REPO / "docs/card-recommendation/acceptance-vectors.json").read_text())["cases"]}
DAY = date(2026, 10, 16)


def card(product="wells-fargo-active-cash", **changes):
    values = dict(wallet_card_id="synthetic-card", product_id=product, network="visa", active="yes",
                  path_eligible="yes", available_credit_minor=1_000_000, policy_confirmed_through=DAY,
                  issuer_eligible_purchase="yes", issuer_category="ordinary_merchandise",
                  category_confirmed_through=DAY, reward_period_date=DAY, expected_full_repayment="yes",
                  purchase_grace_period_active="yes", foreign_fee_applies="no", checkout_fee_minor=0)
    values.update(changes)
    return CardOption(**values)


def purchase(amount=10000, **changes):
    return Purchase(total_minor=amount, charge_date=changes.pop("charge_date", DAY),
                    accepted_networks=changes.pop("accepted_networks", ["visa", "mastercard", "amex", "discover"]), **changes)


def estimate(option, amount=10000, **changes):
    return evaluate(option, purchase(amount, **changes), load_snapshot().card(option.product_id))


def usage(posted=0, pending=0, reserved=0, *, quarter=False, **changes):
    values = dict(posted_minor=posted, pending_minor=pending, reserved_minor=reserved,
                  period_start="2026-10-01" if quarter else "2026-01-01", period_end="2026-12-31",
                  as_of="2026-10-16", account_scope_confirmed=True)
    values.update(changes)
    return values


def scenario_option(key, low, high=None, *, default=False, coverages=(), complete=True):
    return Evaluated(OptionEstimate(wallet_card_id=key, product_id="synthetic-product", payment_path="direct_card",
                                    availability="eligible", net=Interval(low_minor=low, high_minor=low if high is None else high)),
                     default, ProtectionProfile(complete, coverages))


def test_laptop_rewards_and_reviewed_target_sacrifice():
    v = VECTORS["laptop-fu-ac"]
    fu = estimate(card("chase-freedom-unlimited", wallet_card_id="synthetic-fu"), v["purchase_minor"])
    ac = estimate(card(is_default=True), v["purchase_minor"])
    assert fu.estimate.net.low_minor == v["expected_reward_minor"]["chase-freedom-unlimited"]
    assert ac.estimate.net.low_minor == v["expected_reward_minor"]["wells-fargo-active-cash"]
    # The vector explicitly assumes independently established eligibility. Production seed
    # profiles remain incomplete and cannot be substituted with these test-only stubs.
    fu.profile = ProtectionProfile(True, (Coverage("extended_warranty", 149900, extension_months=12, comparability_key="laptop"),))
    ac.profile = ProtectionProfile(True)
    prefs = Preferences(mode="protection_target", cash_sacrifice_budget_minor=1000,
                        protection_targets=[{"benefit_type": "extended_warranty", "min_extension_months": 12}])
    kind, reason, selected, delta = select([ac, fu], prefs)
    assert (kind, reason, selected) == (v["expected_decision"], "user_protection_target", fu)
    assert delta.low_minor == -v["expected_sacrifice_minor"]
    prefs.cash_sacrifice_budget_minor = None
    assert select([ac, fu], prefs)[:2] == (VECTORS["laptop-budget-unset"]["expected_decision"],
                                         VECTORS["laptop-budget-unset"]["expected_reason"])


def test_bce_crossing_cap_and_switch_threshold():
    v = VECTORS["bce-cap-crossing"]
    bce = estimate(card("amex-blue-cash-everyday", is_default=True,
                        issuer_category="us_online_retail_physical_goods",
                        cap_usage={"bce-online-calendar-year": usage(posted=v["posted_usage_minor"])}), v["purchase_minor"])
    ac = estimate(card(wallet_card_id="synthetic-ac"), v["purchase_minor"])
    assert bce.estimate.reward.low_minor == bce.estimate.reward.high_minor == v["expected_reward_minor"]
    bce.profile = ac.profile = ProtectionProfile(True)
    assert select([bce, ac], Preferences(switch_threshold_minor=v["switch_threshold_minor"]))[0] == v["expected_decision"]


def test_bofa_shared_pool_and_membership():
    v = VECTORS["bofa-shared-cap"]
    options = dict(issuer_category="online_shopping", category_selection="online_shopping",
                   selection_effective_at=DAY, membership_bonus_bps=0)
    account = card("bofa-customized-cash-rewards", **options,
                   cap_usage={"bofa-choice-grocery-wholesale-quarter": usage(sum(v["shared_usage_components_minor"].values()), quarter=True)})
    assert estimate(account, v["purchase_minor"]).estimate.reward.low_minor == v["expected_reward_minor"]
    member = VECTORS["bofa-member-ordinary"]
    account.membership_bonus_bps = member["membership_bonus_bps"]
    account.cap_usage = card("bofa-customized-cash-rewards",
                            cap_usage={"bofa-choice-grocery-wholesale-quarter": usage(quarter=True)}).cap_usage
    result = estimate(account, member["purchase_minor"]).estimate
    assert result.reward.low_minor == result.reward.high_minor == member["expected_reward_minor"]


def test_bofa_intro_not_silently_stacked():
    result = estimate(card("bofa-customized-cash-rewards", membership_bonus_bps=7500,
                           confirmed_intro_offer_ids=["bofa-public-first-year-choice-extra"])).estimate
    assert result.net is None
    assert VECTORS["bofa-intro-stacking-unknown"]["expected_reason"] in result.missing_fields


def test_reviewed_return_target_is_not_a_guaranteed_payout():
    v = VECTORS["bcp-return-target"]
    bcp = estimate(card("amex-blue-cash-preferred", wallet_card_id="synthetic-bcp"), v["purchase_minor"])
    ac = estimate(card(is_default=True), v["purchase_minor"])
    assert bcp.estimate.reward.low_minor == v["expected_reward_minor"]["amex-blue-cash-preferred"]
    assert ac.estimate.reward.low_minor == v["expected_reward_minor"]["wells-fargo-active-cash"]
    bcp.profile = ProtectionProfile(True, (Coverage("return_protection", 20000, window_days=90),))
    ac.profile = ProtectionProfile(True)
    prefs = Preferences(mode="protection_target", cash_sacrifice_budget_minor=v["cash_sacrifice_budget_minor"],
                        protection_targets=[{"benefit_type": "return_protection", "min_window_days": 90}])
    assert select([ac, bcp], prefs)[2] is bcp
    # There is no profile, payout prediction, or eligibility override accepted in the API.
    assert "profile" not in CardOption.model_fields
    assert "actual_payout_estimate_minor" not in OptionEstimate.model_fields


def test_discover_quarter_stays_disabled_and_base_is_visible():
    v = VECTORS["discover-unverified-quarter"]
    result = estimate(card("discover-it-cash-back"), v["purchase_minor"]).estimate
    assert result.reward.low_minor == result.reward.high_minor == v["verified_base_reward_minor"]
    assert result.net is None
    assert v["expected_reason"] in result.missing_fields
    assert "discover-quarterly" not in result.rule_ids


def test_foreign_fee_changes_winner():
    v = VECTORS["foreign-qs-ac"]
    ac = estimate(card(is_default=True, foreign_fee_applies="yes"), v["purchase_minor"])
    qs = estimate(card("capital-one-quicksilver", wallet_card_id="synthetic-qs", foreign_fee_applies="yes"), v["purchase_minor"])
    assert ac.estimate.net.low_minor == v["expected_net_minor"]["wells-fargo-active-cash"]
    assert qs.estimate.net.low_minor == v["expected_net_minor"]["capital-one-quicksilver"]
    assert difference(qs.estimate.net, ac.estimate.net).low_minor == v["expected_difference_minor"]
    assert select([ac, qs], Preferences())[0] == "choice_required"
    assert select([ac, qs], Preferences(allow_loss_of_existing_protection=True))[0] == "switch"


def test_unverified_zero_fee_is_not_a_verified_zero_cost():
    policy = load_snapshot().card("capital-one-quicksilver")
    policy["foreign_fee_bps"]["knowledge"] = "unknown"
    result = evaluate(card("capital-one-quicksilver", foreign_fee_applies="yes"), purchase(), policy).estimate
    assert result.net is None
    assert "foreign_fee_unknown" in result.missing_fields


def test_unknown_network_never_inherits_capital_one_template():
    result = estimate(card("capital-one-quicksilver", network=None)).estimate
    assert result.reward.low_minor == 150
    assert result.availability == "needs_info"
    assert all(b.eligibility == "needs_info" and not b.automatic_item_eligibility_enabled for b in result.benefits)


def test_citi_payment_reward_is_separate():
    v = VECTORS["citi-conditional-repayment-reward"]
    result = estimate(card("citi-double-cash", eligible_payment_and_tracker_confirmed="yes"), v["purchase_minor"]).estimate
    assert result.reward.low_minor == v["expected_purchase_reward_minor"]
    assert result.conditional_payment_reward.low_minor == v["expected_conditional_payment_reward_minor"]
    assert result.net.low_minor == result.net.high_minor == v["expected_final_reward_minor"]
    unknown = estimate(card("citi-double-cash")).estimate
    assert (unknown.net.low_minor, unknown.net.high_minor) == (100, 200)


@pytest.mark.parametrize("changes", [
    {"expected_full_repayment": "unknown"}, {"purchase_grace_period_active": "unknown"},
    {"expected_full_repayment": "no"},
    {"purchase_grace_period_active": "no", "purchase_intro_apr": {
        "apr_bps": 0, "valid_from": "2026-01-01", "valid_through": "2026-11-01",
        "repayment_complete_by": "2026-12-01", "verified": True}},
])
def test_financing_never_assumes_zero(changes):
    out = estimate(card(is_default=True, **changes))
    assert out.estimate.net is None
    assert select([out], Preferences())[:2] == (VECTORS["financing-unknown"]["expected_decision"],
                                               VECTORS["financing-unknown"]["expected_reason"])


def test_verified_purchase_zero_apr_covers_whole_repayment_period():
    out = estimate(card(expected_full_repayment="unknown", purchase_grace_period_active="no",
                        purchase_intro_apr={"apr_bps": 0, "valid_from": "2026-01-01", "valid_through": "2027-01-01",
                                            "repayment_complete_by": "2026-12-01", "verified": True}))
    assert out.estimate.net.low_minor == 200


def test_same_benefit_type_does_not_make_shorter_coverage_an_upgrade():
    v = VECTORS["same-type-not-same-protection"]
    old, new = v["baseline"], v["candidate"]
    baseline = scenario_option("baseline", 100, default=True, coverages=(Coverage(old["type"], old["limit_minor"], old["window_days"], comparability_key="same-events"),))
    candidate = scenario_option("candidate", 200, coverages=(Coverage(new["type"], new["limit_minor"], new["window_days"], comparability_key="same-events"),))
    assert protection_guard(candidate, baseline) == v["expected_guard"]
    assert select([baseline, candidate], Preferences())[0] == "choice_required"


def test_uncertain_ranking_uses_cross_interval_difference():
    v = VECTORS["uncertain-reward-ranking"]
    baseline = scenario_option("baseline", *v["baseline_net_interval_minor"], default=True)
    candidate = scenario_option("candidate", *v["candidate_net_interval_minor"])
    delta = difference(candidate.estimate.net, baseline.estimate.net)
    assert [delta.low_minor, delta.high_minor] == v["expected_difference_interval_minor"]
    assert select([baseline, candidate], Preferences())[:2] == ("needs_info", "ranking_uncertain")


@pytest.mark.parametrize("patch,expected", [
    ({"pending": None}, (300, 700)),
    ({"pending": 5000, "reserved": 5000}, (500, 500)),
    ({"as_of": "2026-10-15"}, (300, 900)),
    ({"account_scope_confirmed": False}, (300, 900)),
    ({"period_start": "2025-01-01", "period_end": "2025-12-31"}, (300, 900)),
])
def test_caps_unknown_pending_stale_or_wrong_period(patch, expected):
    # Unknown pending leaves at most $200 in the cap when $5,800 has posted.
    pending = patch.pop("pending", 0)
    reserved = patch.pop("reserved", 0)
    out = estimate(card("amex-blue-cash-everyday", issuer_category="us_online_retail_physical_goods",
                        cap_usage={"bce-online-calendar-year": usage(580000, pending, reserved, **patch)}), 30000).estimate
    # $300 at 1%–3% => $3–$9, even if more than $300 remains in the cap.
    assert (out.reward.low_minor, out.reward.high_minor) == expected


def test_round_once_after_components_half_up():
    result = estimate(card("citi-double-cash", eligible_payment_and_tracker_confirmed="yes"), 25).estimate
    assert result.reward.low_minor == 0 and result.conditional_payment_reward.low_minor == 0
    assert result.net.low_minor == 1  # .25 + .25 cents, rounded only after summing.


def test_cap_period_uses_confirmed_issuer_posting_assignment():
    option = card("amex-blue-cash-everyday", issuer_category="us_online_retail_physical_goods",
                  reward_period_date=date(2027, 1, 1), cap_usage={"bce-online-calendar-year": usage(
                      period_start="2027-01-01", period_end="2027-12-31", as_of="2026-12-31")})
    out = estimate(option, 10000, charge_date=date(2026, 12, 31)).estimate
    # Account and category evidence must also cover the charge date.
    assert out.net is None
    option.policy_confirmed_through = option.category_confirmed_through = date(2026, 12, 31)
    out = estimate(option, 10000, charge_date=date(2026, 12, 31)).estimate
    assert (out.reward.low_minor, out.reward.high_minor) == (300, 300)
    option.reward_period_date = None
    out = estimate(option, 10000, charge_date=date(2026, 12, 31)).estimate
    assert (out.reward.low_minor, out.reward.high_minor) == (100, 300)
    assert "reward_period_date" in out.missing_fields


def test_expired_bonus_rule_does_not_earn_bonus():
    policy = load_snapshot().card("chase-freedom-unlimited")
    policy["reward_rules"][1]["valid_to"] = "2026-10-15"
    out = evaluate(card("chase-freedom-unlimited", issuer_category="dining"), purchase(), policy).estimate
    assert out.reward.low_minor == out.reward.high_minor == 150


@pytest.mark.parametrize("changes,reason", [
    ({"foreign_fee_applies": "unknown"}, "foreign_fee_unknown"),
    ({"checkout_fee_minor": None}, "checkout_fee_unknown"),
    ({"policy_confirmed_through": None}, "account_policy_applicability"),
])
def test_missing_net_inputs_remain_unknown(changes, reason):
    out = estimate(card(**changes)).estimate
    assert out.net is None and reason in out.missing_fields


def test_exact_default_path_does_not_assert_verified_insurance():
    old = scenario_option("same-card", 200, default=True, complete=False)
    other_path = deepcopy(old)
    other_path.is_default = False
    other_path.estimate.payment_path = "apple_pay"
    assert protection_guard(old, old) == "pass"
    assert protection_guard(other_path, old) == "unknown"


def test_unknown_baseline_protection_is_not_treated_as_none():
    old = scenario_option("baseline", 100, default=True, complete=False)
    new = scenario_option("candidate", 1000, complete=True)
    assert select([old, new], Preferences())[:2] == ("choice_required", "protection_comparison_incomplete_or_loss")
    old.estimate.availability = "ineligible"
    assert select([old, new], Preferences())[:2] == ("recommend", "best_verified_feasible_option")


def test_default_survives_small_gain_and_ties():
    old = scenario_option("baseline", 200, default=True)
    new = scenario_option("candidate", 201)
    assert select([old, new], Preferences())[2] is old
    assert select([old, new], Preferences())[3] is None
    new.estimate.net = Interval(low_minor=200, high_minor=200)
    assert select([new, old], Preferences())[2] is old


def test_seed_keeps_not_listed_separate_from_absence_and_citi_summary():
    ac = estimate(card()).estimate
    assert {b.knowledge for b in ac.benefits} == {"not_listed"}
    citi = estimate(card("citi-double-cash")).estimate
    assert next(b for b in citi.benefits if b.benefit_type == "extended_warranty").knowledge == "verified_summary"


@pytest.mark.parametrize("mutation", ["source", "duplicate", "benefit", "template", "predicate", "rate", "units"])
def test_policy_loader_rejects_unexecutable_or_corrupt_policy(tmp_path, mutation):
    data = json.loads(SEED_PATH.read_text())
    if mutation == "source":
        data["cards"][0]["reward_rules"][0]["source_ids"] = ["missing-source"]
    elif mutation == "duplicate":
        data["cards"].append(deepcopy(data["cards"][0]))
    elif mutation == "benefit":
        data["cards"][0]["benefits"][0]["automatic_item_eligibility_enabled"] = True
    elif mutation == "template":
        data["conditional_benefit_templates"][0]["automatic_activation"] = True
    elif mutation == "predicate":
        data["cards"][0]["reward_rules"][0]["requires"].append("unknown_requirement")
    elif mutation == "rate":
        data["cards"][0]["reward_rules"][0]["rate_bps"] = True
    elif mutation == "units":
        data["rate_unit"] = "percent"
    path = tmp_path / "policy.json"
    path.write_text(json.dumps(data))
    with pytest.raises(PolicyError):
        read_snapshot(path)


def example_request():
    return json.loads((REPO / "contracts/v2/recommend.request.example.json").read_text())


def test_api_disabled_by_default(monkeypatch):
    monkeypatch.delenv("RECOMMENDATION_V2_ENABLED", raising=False)
    response = TestClient(app).post("/v2/recommend", json=example_request())
    assert response.status_code == 404
    assert TestClient(app).get("/v2/catalog").status_code == 404


def test_product_metadata_and_contract_support_checkout_form(monkeypatch):
    monkeypatch.setenv("RECOMMENDATION_V2_ENABLED", "1")
    response = TestClient(app).get("/v2/catalog")
    assert response.status_code == 200
    body = response.json()
    assert len(body["products"]) == 9
    products = {p["id"]: p for p in body["products"]}
    assert len(products) == 9
    assert "us_online_retail_physical_goods" in products["amex-blue-cash-everyday"]["categoryOptions"]
    assert products["discover-it-cash-back"]["categoryOptions"] == []
    assert 7500 in products["bofa-customized-cash-rewards"]["membershipBonusOptionsBps"]
    assert all(p["termsUrls"] and all(url.startswith("https://") for url in p["termsUrls"]) for p in products.values())
    assert response.headers["cache-control"] == "no-store"
    schema = json.loads((REPO / "contracts/v2/catalog.response.schema.json").read_text())
    assert schema == ProductCatalog.model_json_schema(by_alias=True)
    Draft202012Validator(schema, format_checker=Draft202012Validator.FORMAT_CHECKER).validate(body)
    assert body == json.loads((REPO / "contracts/v2/catalog.response.example.json").read_text())


def test_api_policy_failure_is_a_generic_503(monkeypatch):
    from app import routes_recommendation_v2
    monkeypatch.setenv("RECOMMENDATION_V2_ENABLED", "1")
    def unavailable():
        raise PolicyError("private diagnostic")
    monkeypatch.setattr(routes_recommendation_v2, "load_snapshot", unavailable)
    response = TestClient(app).post("/v2/recommend", json=example_request())
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "policy_unavailable"
    assert "private diagnostic" not in response.text


def test_unknown_product_cannot_be_scored(monkeypatch):
    monkeypatch.setenv("RECOMMENDATION_V2_ENABLED", "1")
    body = example_request()
    body["options"][0]["productId"] = "unknown-card-product"
    assert TestClient(app).post("/v2/recommend", json=body).status_code == 400


def test_unknown_credit_blocks_global_ranking_but_insufficient_credit_does_not():
    baseline = estimate(card(is_default=True))
    unresolved = estimate(card("capital-one-quicksilver", wallet_card_id="synthetic-other", available_credit_minor=None))
    assert select([baseline, unresolved], Preferences(allow_loss_of_existing_protection=True))[0] == "needs_info"
    unavailable = estimate(card("capital-one-quicksilver", wallet_card_id="synthetic-other", available_credit_minor=1))
    assert select([baseline, unavailable], Preferences())[0] == "keep"


def test_api_enabled_contract_and_deterministic_read_only_result(monkeypatch):
    monkeypatch.setenv("RECOMMENDATION_V2_ENABLED", "1")
    body = example_request()
    before = SEED_PATH.read_bytes()
    with TestClient(app) as client:
        first = client.post("/v2/recommend", json=body)
        second = client.post("/v2/recommend", json=body)
    assert first.status_code == 200, first.text
    assert first.json() == second.json()
    assert first.json() == json.loads((REPO / "contracts/v2/recommend.response.example.json").read_text())
    assert first.headers["cache-control"] == "no-store"
    assert SEED_PATH.read_bytes() == before  # Evaluation never consumes caps or writes reservations.
    for name, model, value in (("request", RecommendRequest, body), ("response", RecommendResponse, first.json())):
        schema = json.loads((REPO / f"contracts/v2/recommend.{name}.schema.json").read_text())
        Draft202012Validator.check_schema(schema)
        Draft202012Validator(schema, format_checker=Draft202012Validator.FORMAT_CHECKER).validate(value)
        assert schema == model.model_json_schema(by_alias=True)


@pytest.mark.parametrize("amount", [-1, 1.5, True, "100", float("nan"), float("inf")])
def test_money_is_finite_nonnegative_integer(amount):
    body = example_request()
    body["purchase"]["totalMinor"] = amount
    with pytest.raises(ValidationError):
        RecommendRequest.model_validate(body)


@pytest.mark.parametrize("change", ["duplicate", "two_defaults", "negative_budget", "untrusted_profile", "untrusted_rate", "no_targets", "conflicting_account"])
def test_contract_rejects_invalid_or_untrusted_inputs(change):
    body = example_request()
    if change == "duplicate":
        body["options"].append(deepcopy(body["options"][0]))
    elif change == "two_defaults":
        body["options"][1]["isDefault"] = True
    elif change == "negative_budget":
        body["preferences"]["cashSacrificeBudgetMinor"] = -1
    elif change == "untrusted_profile":
        body["options"][0]["profile"] = {"complete": True}
    elif change == "untrusted_rate":
        body["options"][0]["rewardRateBps"] = 9999
    elif change == "no_targets":
        body["preferences"]["mode"] = "protection_target"
    elif change == "conflicting_account":
        other = deepcopy(body["options"][0])
        other.update(paymentPath="apple_pay", isDefault=False, availableCreditMinor=1)
        body["options"].append(other)
    with pytest.raises(ValidationError):
        RecommendRequest.model_validate(body)


def test_api_validation_errors_do_not_echo_financial_input(monkeypatch):
    monkeypatch.setenv("RECOMMENDATION_V2_ENABLED", "1")
    body = example_request()
    body["options"][0]["productId"] = "sensitive-invalid-value!"
    response = TestClient(app).post("/v2/recommend", json=body)
    assert response.status_code == 400
    assert "sensitive-invalid-value" not in response.text


def test_default_api_never_promotes_unreviewed_protection(monkeypatch):
    monkeypatch.setenv("RECOMMENDATION_V2_ENABLED", "1")
    body = example_request()
    body["preferences"]["allowLossOfExistingProtection"] = False
    response = TestClient(app).post("/v2/recommend", json=body)
    assert response.status_code == 200
    assert response.json()["decision"] == "choice_required"
    assert response.json()["selected"] is None
    assert all(b["eligibility"] == "needs_info" for o in response.json()["options"] for b in o["benefits"])


def test_api_targets_cannot_bypass_seed_readiness(monkeypatch):
    monkeypatch.setenv("RECOMMENDATION_V2_ENABLED", "1")
    body = example_request()
    body["preferences"].update(mode="protection_target", protectionTargets=[{"benefitType": "extended_warranty"}])
    response = TestClient(app).post("/v2/recommend", json=body)
    assert response.json()["reason"] == "protection_target_unverified"


def test_v2_shares_privacy_and_rate_guards(monkeypatch):
    monkeypatch.setenv("RECOMMENDATION_V2_ENABLED", "1")
    with TestClient(app) as client:
        body = example_request()
        body["requestId"] = "4" + "1" * 15
        assert client.post("/v2/recommend", json=body).json()["error"]["code"] == "privacy_rejected"
        middleware.LIMITER.reset()
        monkeypatch.setattr(middleware.LIMITER, "per_minute", 1)
        assert client.post("/v2/recommend", json=example_request()).status_code == 200
        assert client.post("/v2/recommend", json=example_request()).status_code == 429
