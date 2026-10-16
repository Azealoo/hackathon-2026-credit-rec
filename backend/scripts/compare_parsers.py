"""Side-by-side cart-parser eval for the on-device feasibility test (experiment/on-device-parser).

Scores three readers on the same fixtures, the same way scripts/eval_parser.py does:
- llm:   the live Claude parser (parser_llm.parse; needs LLM_API_KEY, never printed);
- rules: the deterministic rules parser;
- raw:   raw JSON from Apple's on-device model, captured on the iPhone by ParserLab
         (ios/Paywise/Debug/ParserLab.swift). It goes through the same parser_llm.build() as
         Claude's output, so the only thing that differs is the model.

Fixture sets: base = fixtures/ocr + fixtures/carts (the demo-store screens); hard = fixtures/ocr-hard +
fixtures/carts-hard (8 harder fake screens, scripts/make_hard_fixtures.py).

    cd backend && set -a && source ../.env && set +a
    uv run python scripts/compare_parsers.py llm --rounds 3 --json-out ../docs/parser-lab/llm.json
    uv run python scripts/compare_parsers.py rules --json-out ../docs/parser-lab/rules.json
    uv run python scripts/compare_parsers.py raw ../docs/parser-lab/ondevice-raw.jsonl --json-out ../docs/parser-lab/ondevice.json

How to run the on-device side on an eligible iPhone: docs/on-device-parser-handoff.md.
"""

import argparse
import asyncio
import json
import os
import statistics
import sys
import time
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))
sys.path.insert(0, str(BACKEND / "scripts"))

from eval_parser import ITEM_CONFIDENCE_MIN, item_matches, percentile  # noqa: E402

FIXTURES = BACKEND.parent / "fixtures"
SETS = {"base": ("ocr", "carts"), "hard": ("ocr-hard", "carts-hard")}
METRICS = ["screen", "merchant", "total", "items", "condition", "payment", "conf"]


def load_cases(sets: list[str]) -> list[tuple[str, str, str, dict]]:
    cases = []
    for name in sets:
        ocr_dir, cart_dir = SETS[name]
        for ocr in sorted((FIXTURES / ocr_dir).glob("*.txt")):
            expected = json.loads((FIXTURES / cart_dir / f"{ocr.stem}.json").read_text(encoding="utf-8"))
            cases.append((name, ocr.stem, ocr.read_text(encoding="utf-8"), expected))
    return cases


def checks_for(expected: dict, parsed, error: bool) -> dict[str, bool]:
    """The same per-screen checks as eval_parser.run()."""
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
            e["condition"] == g["condition"] for e, g in zip(exp_items, got_items))
    if expected["screenType"] == "checkout":
        checks["conf"] = bool(cart) and cart["confidence"]["items"] >= ITEM_CONFIDENCE_MIN
    return checks


def summarize(rows: list[dict]) -> dict:
    out = {}
    for metric in METRICS:
        scored = [r["checks"][metric] for r in rows if metric in r["checks"]]
        out[metric] = [sum(scored), len(scored)]
    latencies = [r["ms"] for r in rows if r["ms"] is not None]
    out["p50_ms"] = round(statistics.median(latencies)) if latencies else None
    out["p90_ms"] = percentile(latencies, 90) if latencies else None
    out["max_ms"] = round(max(latencies)) if latencies else None
    out["errors"] = sum(1 for r in rows if r["error"])
    out["calls"] = len(rows)
    return out


def print_summary(label: str, rows: list[dict], show_misses: bool) -> dict:
    by_set = {name: [r for r in rows if r["set"] == name] for name in SETS}
    result = {"all": summarize(rows)}
    for name, subset in by_set.items():
        if subset:
            result[name] = summarize(subset)
    for name, s in result.items():
        frac = " ".join(f"{m.upper()}={s[m][0]}/{s[m][1]}" for m in METRICS)
        print(f"{label} SET={name} {frac} P50_MS={s['p50_ms']} P90_MS={s['p90_ms']} MAX_MS={s['max_ms']} "
              f"ERRORS={s['errors']} CALLS={s['calls']}")
    if show_misses:
        for r in rows:
            missed = [m for m, ok in r["checks"].items() if not ok]
            if missed or r["error"]:
                print(f"miss {label} round={r['round']} fixture={r['fixture']} error={r['error']} "
                      f"metrics={','.join(missed)}")
    return result


async def run_live(parser: str, rounds: int, sets: list[str]) -> list[dict]:
    from app import llm, parser_llm, parser_rules

    rows = []
    for round_no in range(1, rounds + 1):
        for set_name, stem, text, expected in load_cases(sets):
            started = time.perf_counter()
            error = None
            try:
                parsed = await parser_llm.parse(text) if parser == "llm" else parser_rules.parse(text)
            except llm.LLMError as exc:
                parsed, error = None, type(exc).__name__
            ms = (time.perf_counter() - started) * 1000
            rows.append({"set": set_name, "fixture": stem, "round": round_no, "ms": ms, "error": error,
                         "checks": checks_for(expected, parsed, error is not None)})
    return rows


def run_raw(path: Path, sets: list[str]) -> list[dict]:
    from app import llm, parser_llm

    cases = {(s, stem): (text, expected) for s, stem, text, expected in load_cases(sets)}
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        rec = json.loads(line)
        if "fixture" not in rec:  # ParserLab's start / instruction_tokens / done events
            continue
        key = (rec["set"], rec["fixture"])
        if key not in cases:
            continue
        text, expected = cases[key]
        error, parsed = rec.get("error"), None
        if not error:
            try:
                parsed = parser_llm.build(rec["raw"], text)
            except llm.LLMError as exc:
                error = type(exc).__name__
        rows.append({"set": rec["set"], "fixture": rec["fixture"], "round": rec["round"], "ms": rec.get("ms"),
                     "error": error, "checks": checks_for(expected, parsed, error is not None)})
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("parser", choices=["llm", "rules", "raw"])
    ap.add_argument("raw_file", nargs="?", type=Path, help="ParserLab JSONL (raw mode only)")
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--sets", default="base,hard")
    ap.add_argument("--json-out", type=Path)
    ap.add_argument("--show-misses", action="store_true")
    args = ap.parse_args()
    sets = [s for s in args.sets.split(",") if s]
    if args.parser == "llm" and os.environ.get("LLM_API_KEY", "changeme").strip() in ("", "changeme"):
        print("LLM_API_KEY is not set; load .env first", file=sys.stderr)
        return 2
    if args.parser == "raw":
        if not args.raw_file:
            print("raw mode needs the ParserLab JSONL file", file=sys.stderr)
            return 2
        rows = run_raw(args.raw_file, sets)
        label = "ONDEVICE"
    else:
        rows = asyncio.run(run_live(args.parser, args.rounds, sets))
        label = args.parser.upper()
        if args.parser == "llm":
            from app import llm
            label += f"({llm.model()})"
    summary = print_summary(label, rows, args.show_misses)
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps({"label": label, "summary": summary, "rows": rows}, indent=1) + "\n",
                                 encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
