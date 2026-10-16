"""Read the versioned research seed without enabling its unfinished benefit packs."""

from copy import deepcopy
from dataclasses import dataclass
from datetime import date
from functools import lru_cache
from hashlib import sha256
import json
from pathlib import Path

SEED_PATH = Path(__file__).resolve().parents[3] / "docs/card-recommendation/card-policy-seed.json"


class PolicyError(ValueError):
    pass


@dataclass(frozen=True)
class Snapshot:
    version: str
    snapshot_id: str
    _cards: dict
    sources: tuple[dict, ...]

    def card(self, product_id: str) -> dict:
        if product_id not in self._cards:
            raise ValueError("unknown product id")
        return deepcopy(self._cards[product_id])


def read_snapshot(path: Path) -> Snapshot:
    raw = path.read_bytes()
    data = json.loads(raw)
    if data.get("schema_version") != "research-seed-1" or data.get("not_production_policy_bundle") is not True:
        raise PolicyError("unsupported policy bundle")
    if data.get("amount_unit") != "integer_USD_cents" or data.get("rate_unit") != "basis_points":
        raise PolicyError("unsupported policy units")
    source_ids = [s["id"] for s in data["sources"]]
    card_ids = [c["id"] for c in data["cards"]]
    if len(set(source_ids)) != len(source_ids) or len(set(card_ids)) != len(card_ids):
        raise PolicyError("duplicate policy IDs")

    def references(node):
        if isinstance(node, dict):
            if not set(node.get("source_ids", [])) <= set(source_ids):
                raise PolicyError("unresolved source reference")
            for value in node.values():
                references(value)
        elif isinstance(node, list):
            for value in node:
                references(value)

    references(data)
    rule_ids = set()
    for card in data["cards"]:
        pools = {p["id"]: p for p in card["cap_pools"]}
        if len(pools) != len(card["cap_pools"]):
            raise PolicyError("duplicate cap pool")
        for pool in pools.values():
            if type(pool["spend_cap_minor"]) is not int or pool["spend_cap_minor"] < 0:
                raise PolicyError("invalid cap")
            if pool["period"] not in ("calendar_year", "calendar_quarter"):
                raise PolicyError("unsupported cap period")
        bases = []
        for rule in card["reward_rules"]:
            for key in ("valid_from", "valid_to", "effective_from", "effective_to"):
                if rule.get(key) is not None:
                    try:
                        date.fromisoformat(rule[key])
                    except (ValueError, TypeError) as exc:
                        raise PolicyError("invalid rule date") from exc
            if rule["id"] in rule_ids:
                raise PolicyError("duplicate reward rule")
            rule_ids.add(rule["id"])
            if type(rule["rate_bps"]) is not int or not 0 <= rule["rate_bps"] <= 10000:
                raise PolicyError("invalid reward rate")
            if rule.get("cap_pool_id") and rule["cap_pool_id"] not in pools:
                raise PolicyError("unresolved cap reference")
            if rule.get("enabled", True) is False:
                continue
            if (rule["knowledge"] != "verified_rule" or rule["rate_semantics"] != "total_not_additive"
                    or rule["exclusive_group"] != "ordinary_purchase_rate"):
                raise PolicyError("unsupported reward semantics")
            if not set(rule["match"]) <= {"eligible_purchase", "issuer_category", "issuer_category_in",
                                            "issuer_category_equals_account_choice"}:
                raise PolicyError("unsupported reward predicate")
            if not set(rule["requires"]) <= {"account_policy_applicability_confirmed",
                    "issuer_eligible_purchase_confirmed", "issuer_category_or_channel_evidence_confirmed"}:
                raise PolicyError("unsupported reward prerequisite")
            if rule["match"] == {"eligible_purchase": True}:
                bases.append(rule)
        if len(bases) != 1 or bases[0].get("cap_pool_id"):
            raise PolicyError("one uncapped base rule required")
        for rule in card["reward_rules"]:
            if rule.get("enabled", True) is False:
                continue
            is_base = rule is bases[0]
            if rule["priority"] != (0 if is_base else 10) or rule["rate_bps"] < bases[0]["rate_bps"]:
                raise PolicyError("unsupported reward precedence")
        fee = card["foreign_fee_bps"]
        if fee["value"] is not None and (type(fee["value"]) is not int or not 0 <= fee["value"] <= 10000):
            raise PolicyError("invalid foreign fee")
        if any(b.get("automatic_item_eligibility_enabled") is not False for b in card["benefits"]):
            raise PolicyError("automatic benefit packs are not implemented")
        for conditional in card.get("conditional_rewards", []):
            if (conditional.get("basis") != "eligible_purchase_principal_repaid_with_corresponding_purchase_tracker"
                    or conditional.get("knowledge") != "verified_rule"
                    or type(conditional.get("rate_bps")) is not int
                    or not 0 <= conditional["rate_bps"] <= 10000
                    or set(conditional.get("requires", [])) != {"account_policy_applicability_confirmed",
                            "eligible_payment_confirmed", "repayment_assumption_disclosed"}):
                raise PolicyError("unsupported conditional reward")
    if any(t.get("automatic_activation") is not False for t in data["conditional_benefit_templates"]):
        raise PolicyError("automatic benefit templates are not implemented")
    return Snapshot(data["policy_version"], sha256(raw).hexdigest(),
                    {c["id"]: c for c in data["cards"]}, tuple(data["sources"]))


@lru_cache(maxsize=1)
def load_snapshot() -> Snapshot:
    return read_snapshot(SEED_PATH)
