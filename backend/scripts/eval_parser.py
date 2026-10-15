"""Live eval of the LLM cart parser on fixtures/ocr/*.txt against fixtures/carts/*.json (§15.7 step 9).

Calls the real model (needs LLM_API_KEY in the environment; never printed). Prints aggregates only:

    MERCHANT=x/y TOTAL=x/y ITEMS=x/y CONDITION=x/y SCREEN=x/y P50_MS=… P90_MS=…
    EXTRA PAYMENT=x/y ITEMS_CONF_OK=x/y ERRORS=n CALLS=n API_CALLS=n MODEL=…

Per screen-run: MERCHANT = merchantId, TOTAL = totalUsd (exact), SCREEN = screenType, ITEMS = the
item list (same length; per item: name loosely, price exact, category exact). CONDITION counts
screen-runs whose fixture has items, per item in order. PAYMENT = paymentOptionsVisible (as a set)
+ selectedPayment. ITEMS_CONF_OK = checkout screens with confidence.items >= 0.8 (the engine's
threshold). A call that raises counts as wrong on every metric and as one ERROR. CALLS = parses;
API_CALLS = requests sent, including hedges (llm.py LLM_HEDGE_AFTER_S).
Targets: merchant + total 100%, items + condition >= 85%, p50 <= 1500 ms, p90 <= 3000 ms.

    cd backend && set -a && source ../.env && set +a && uv run python scripts/eval_parser.py [--rounds 3] [--model ID]

--causes instead runs llm.classify_cause on every fixtures/coverage_cases.json description and
compares it to the user-confirmed cause: CAUSE=x/y P50_MS=… P90_MS=… (aggregates only).
"""

import argparse
import asyncio
import difflib
import json
import math
import os
import re
import statistics
import sys
import time
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

FIXTURES = BACKEND.parent / "fixtures"
ITEM_CONFIDENCE_MIN = 0.8  # SPEC §7.2


def _tokens(name: str) -> list[str]:
    return re.findall(r"[a-z0-9]+", name.casefold())


def name_matches(expected: str, got: str) -> bool:
    """Loose: same words ignoring case and punctuation, or a close spelling (ratio >= 0.85)."""
    a, b = _tokens(expected), _tokens(got)
    if a == b:
        return True
    return difflib.SequenceMatcher(None, " ".join(a), " ".join(b)).ratio() >= 0.85


def item_matches(expected: dict, got: dict) -> bool:
    return (
        name_matches(expected["name"], got["name"])
        and round(got["priceUsd"] * 100) == round(expected["priceUsd"] * 100)
        and got["category"] == expected["category"]
    )


def percentile(values: list[float], pct: float) -> int:
    ordered = sorted(values)
    return round(ordered[max(0, math.ceil(pct / 100 * len(ordered)) - 1)])


async def run(rounds: int, show_misses: bool) -> int:
    from app import llm, parser_llm

    cases = []
    for ocr in sorted((FIXTURES / "ocr").glob("*.txt")):
        expected = json.loads((FIXTURES / "carts" / f"{ocr.stem}.json").read_text(encoding="utf-8"))
        cases.append((ocr.stem, ocr.read_text(encoding="utf-8"), expected))

    score = dict.fromkeys(["merchant", "total", "items", "condition", "screen", "payment", "conf"], 0)
    counts = dict.fromkeys(score, 0)
    latencies, errors = [], 0

    for round_no in range(1, rounds + 1):
        for stem, text, expected in cases:
            started = time.perf_counter()
            try:
                parsed = await parser_llm.parse(text)
                error = False
            except llm.LLMError:
                parsed, error = None, True
            latencies.append((time.perf_counter() - started) * 1000)
            errors += error

            cart = parsed.cart.model_dump(by_alias=True) if parsed and parsed.cart else None
            got_items = cart["items"] if cart else []
            exp_items = expected["items"]
            checks = {
                "screen": not error and parsed.screen_type == expected["screenType"],
                "merchant": not error and (cart["merchant"]["merchantId"] if cart else None)
                == expected["merchant"]["merchantId"],
                "total": not error and (cart["totalUsd"] if cart else None) == expected["totalUsd"],
                "items": not error and len(got_items) == len(exp_items)
                and all(item_matches(e, g) for e, g in zip(exp_items, got_items)),
                "payment": not error
                and set(cart["paymentOptionsVisible"] if cart else []) == set(expected["paymentOptionsVisible"])
                and (cart["selectedPayment"] if cart else {"kind": "unknown", "network": "unknown"})
                == expected["selectedPayment"],
            }
            if exp_items:
                checks["condition"] = not error and len(got_items) == len(exp_items) and all(
                    e["condition"] == g["condition"] for e, g in zip(exp_items, got_items)
                )
            if expected["screenType"] == "checkout":
                checks["conf"] = bool(cart) and cart["confidence"]["items"] >= ITEM_CONFIDENCE_MIN
            for key, ok in checks.items():
                counts[key] += 1
                score[key] += ok
            if show_misses:
                missed = [k for k, ok in checks.items() if not ok]
                if missed or error:
                    print(f"miss round={round_no} fixture={stem} error={error} metrics={','.join(missed)}")

    def frac(key: str) -> str:
        return f"{score[key]}/{counts[key]}"

    print(
        f"MERCHANT={frac('merchant')} TOTAL={frac('total')} ITEMS={frac('items')} "
        f"CONDITION={frac('condition')} SCREEN={frac('screen')} "
        f"P50_MS={round(statistics.median(latencies))} P90_MS={percentile(latencies, 90)}"
    )
    print(
        f"EXTRA PAYMENT={frac('payment')} ITEMS_CONF_OK={frac('conf')} ERRORS={errors} "
        f"CALLS={len(latencies)} API_CALLS={llm.calls_today()} MODEL={llm.model()}"
    )
    return 0


async def run_causes(rounds: int) -> int:
    from app import llm

    cases = json.loads((FIXTURES / "coverage_cases.json").read_text(encoding="utf-8"))["cases"]
    right, total, latencies = 0, 0, []
    for _ in range(rounds):
        for case in cases:
            incident = case["incident"]
            started = time.perf_counter()
            cause = await llm.classify_cause(incident["description"])
            latencies.append((time.perf_counter() - started) * 1000)
            right += cause == incident["cause"]
            total += 1
    print(f"CAUSE={right}/{total} P50_MS={round(statistics.median(latencies))} P90_MS={percentile(latencies, 90)} "
          f"MODEL={llm.model()}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--model", help="override LLM_MODEL for this run, e.g. claude-sonnet-5-5")
    parser.add_argument("--show-misses", action="store_true", help="also list fixture names and missed metrics")
    parser.add_argument("--causes", action="store_true", help="evaluate classify_cause on the coverage cases instead")
    args = parser.parse_args()
    if not os.environ.get("LLM_API_KEY", "").strip() or os.environ["LLM_API_KEY"].strip() == "changeme":
        print("LLM_API_KEY is not set; load .env first", file=sys.stderr)
        return 2
    if args.model:
        os.environ["LLM_MODEL"] = args.model
    if args.causes:
        return asyncio.run(run_causes(args.rounds))
    return asyncio.run(run(args.rounds, args.show_misses))


if __name__ == "__main__":
    raise SystemExit(main())
