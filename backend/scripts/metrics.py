"""Paywise metrics harness (SPEC §13, §15.7 step 15). Prints aggregates only.

It prints counts, rates and latency percentiles. It never prints a request body, OCR text or a
response body. Results go in docs/metrics.md.

    cd backend && uv run python scripts/metrics.py                 # offline: no network, no keys
    cd backend && set -a && source ../.env && set +a && uv run python scripts/metrics.py --live

Offline:
    SCENARIOS    pass=x/28 false_switches=n protection_drops=n must_pass=yes|no (5, 21, 22, 23, 25, 26)
    COVERAGE     pass=x/14 not_covered_right=x/y cites_section_and_date=x/14 cap500_cases_3_13=yes|no
    CHECK_LOCAL  POST /v1/check S1 through TestClient, PARSER_MODE=rules, one warm-up left out;
                 parser= counts the parser each timed request really used (rulesxN)

--live adds:
    LIVE_HEALTH  GET /health on Render
    LIVE_CHECK   POST /v1/check S1 on Render (whatever PARSER_MODE Render has), s1_copy = exact §6.3 copy,
                 server_parse = the response's timingMs.parse
    then scripts/eval_parser.py's own aggregate lines: the LLM cart parser on fixtures/ocr, then cause
    classification on the coverage cases (needs LLM_API_KEY; skipped without it)

Live requests each open a new connection (as a press after a pause would). The first request is a
warm-up: it is reported as warmup_ms and left out of p50/p90. p50 = median; p90 = nearest rank.
"""

import argparse
import asyncio
import contextlib
import datetime as dt
import json
import logging
import math
import os
import statistics
import subprocess
import sys
import time
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
BACKEND = SCRIPTS.parent
REPO = BACKEND.parent
FIXTURES = REPO / "fixtures"
for path in (str(BACKEND), str(SCRIPTS)):
    if path not in sys.path:
        sys.path.insert(0, path)

LIVE_BASE_URL = "https://paywise-api-n0f9.onrender.com"
LOCAL_RUNS = 200
LIVE_RUNS = 10
LIVE_TIMEOUT_S = 90.0  # a sleeping or cold Render instance can take this long to answer


# --- Aggregation helpers (tested in tests/test_metrics_script.py) ---------------------------------


def percentile(values: list[float], pct: float) -> float:
    """Nearest-rank percentile: the smallest value with at least pct% of the values at or below it."""
    if not values:
        raise ValueError("no values")
    ordered = sorted(values)
    return ordered[max(0, math.ceil(pct / 100 * len(ordered)) - 1)]


def summarize(samples_ms: list[float]) -> dict:
    """n, p50 (median), p90 (nearest rank) and max of a list of latencies in ms."""
    return {
        "n": len(samples_ms),
        "p50": statistics.median(samples_ms),
        "p90": percentile(samples_ms, 90),
        "max": max(samples_ms),
    }


def ms(value: float) -> str:
    """Two decimals under 10 ms (local runs), whole ms above (network runs)."""
    return f"{value:.2f}" if value < 10 else f"{value:.0f}"


def frac(ok: int, total: int) -> str:
    return f"{ok}/{total}"


def yes(flag: bool) -> str:
    return "yes" if flag else "no"


def status_counts(codes: list[int | str]) -> str:
    """HTTP status codes (or error names) with counts, most common first: '200x10' or '200x9,ReadTimeoutx1'."""
    counts: dict[str, int] = {}
    for code in codes:
        counts[str(code)] = counts.get(str(code), 0) + 1
    return ",".join(f"{code}x{n}" for code, n in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])))


def latency_line(label: str, samples_ms: list[float], ok: int, total: int, extra: str = "") -> str:
    if not samples_ms:
        return f"{label} runs=0 ok={frac(ok, total)}{extra}"
    s = summarize(samples_ms)
    return (f"{label} runs={s['n']} ok={frac(ok, total)} p50_ms={ms(s['p50'])} p90_ms={ms(s['p90'])} "
            f"max_ms={ms(s['max'])}{extra}")


@contextlib.contextmanager
def env(**values: str):
    """Set environment variables for the block, then put the old values back."""
    old = {key: os.environ.get(key) for key in values}
    os.environ.update(values)
    try:
        yield
    finally:
        for key, value in old.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


# --- Inputs ----------------------------------------------------------------------------------------


def s1_body() -> dict:
    """The §6.3 S1 check: the demo-store laptop OCR fixture and the demo-3card wallet (fake data)."""
    wallets = json.loads((FIXTURES / "wallets.json").read_text(encoding="utf-8"))["wallets"]
    cards = next(w for w in wallets if w["id"] == "demo-3card")["cards"]
    return {
        "requestId": "5f0c0000-aaaa-4bbb-8ccc-ddddeeeeffff",
        "client": {"app": "paywise-ios", "version": "0.1.0"},
        "clientDate": "2026-10-17",
        "screen": {"ocrText": (FIXTURES / "ocr" / "laptop-checkout.txt").read_text(encoding="utf-8"),
                   "redactions": ["card_number", "address", "email", "phone"], "ocrConfidence": 0.93},
        "wallet": {"cards": [{"cardId": c["cardId"], "isDefault": i == 0} for i, c in enumerate(cards)]},
        "prefs": {"paysInFull": None},
    }


def s1_copy() -> dict:
    """The exact S1 copy, from the contract example (contracts/check.response.example.json)."""
    example = json.loads((REPO / "contracts" / "check.response.example.json").read_text(encoding="utf-8"))
    return example["decision"]["copy"]


def is_s1(data: object, expected_copy: dict) -> bool:
    return (isinstance(data, dict) and isinstance(data.get("decision"), dict)
            and data["decision"].get("copy") == expected_copy)


# --- Offline ---------------------------------------------------------------------------------------


def scenarios_line() -> str:
    """fixtures/scenarios.json through the engine, with the same checks as tests/test_scenarios.py."""
    from tests import test_scenarios as t

    results = {s["id"]: t.run(s) for s in t.SCENARIOS}
    passed = {s["id"] for s in t.SCENARIOS if not t.mismatches(s, results[s["id"]])}
    false_switches = sum(t.false_switch(s, results[s["id"]]) for s in t.SCENARIOS)
    drops = sum(t.protection_drop(s, results[s["id"]]) for s in t.SCENARIOS)
    return (f"SCENARIOS pass={frac(len(passed), len(t.SCENARIOS))} false_switches={false_switches} "
            f"protection_drops={drops} must_pass={yes(t.MUST_PASS <= passed)}")


def coverage_line() -> str:
    """fixtures/coverage_cases.json through POST /v1/coverage, with the checks in tests/test_coverage.py."""
    from tests import test_coverage as t

    results = {c["id"]: t.verdict(t.body_for(c["id"])) for c in t.CASES}
    passed = [c for c in t.CASES if not t.mismatches(c, results[c["id"]])]
    not_covered = [c for c in t.CASES if c["expected"]["verdict"] == "not_covered"]
    nc_right = [c for c in not_covered if not t.mismatches(c, results[c["id"]])]
    cited = sum(bool(r["citations"]) and all(c["section"] and c["versionDate"] for c in r["citations"])
                for r in results.values())
    cap = results[3]["limit"]["payoutCapUsd"] == 500 and results[13]["limit"]["payoutCapUsd"] == 500
    return (f"COVERAGE pass={frac(len(passed), len(t.CASES))} not_covered_right={frac(len(nc_right), len(not_covered))} "
            f"cites_section_and_date={frac(cited, len(t.CASES))} cap500_cases_3_13={yes(cap)}")


def local_check_line(runs: int = LOCAL_RUNS) -> str:
    """POST /v1/check S1 in-process (TestClient), rules parser, rate limit off for the run.

    parser= is measured: the names parse_screen returned on the timed runs ('rulesx200'). The run
    stops before any request if PARSER_MODE isn't rules, so it can never reach the LLM."""
    from fastapi.testclient import TestClient

    from app import main as app_main
    from app import middleware, parsing

    if parsing.parser_mode() != "rules":
        raise RuntimeError("CHECK_LOCAL needs PARSER_MODE=rules (run it through offline_report)")

    client, body, expected = TestClient(app_main.app), s1_body(), s1_copy()
    real_parse, used = app_main.parse_screen, []

    async def counted_parse(ocr_text: str):
        parsed, name = await real_parse(ocr_text)
        used.append(name)
        return parsed, name

    limit = middleware.LIMITER.per_minute
    middleware.LIMITER.per_minute = 0
    app_main.parse_screen = counted_parse
    try:
        client.post("/v1/check", json=body)  # warm-up, left out
        used.clear()
        times, ok, exact = [], 0, 0
        for _ in range(runs):
            started = time.perf_counter()
            response = client.post("/v1/check", json=body)
            times.append((time.perf_counter() - started) * 1000)
            ok += response.status_code == 200
            exact += response.status_code == 200 and is_s1(response.json(), expected)
    finally:
        app_main.parse_screen = real_parse
        middleware.LIMITER.per_minute = limit
        middleware.LIMITER.reset()
    parsers = status_counts(used) if used else "none"
    return latency_line("CHECK_LOCAL", times, ok, runs, f" s1_copy={frac(exact, runs)} parser={parsers}")


@contextlib.contextmanager
def quiet_app_logs():
    """Hide the app's per-request INFO lines (metadata only) for the block; warnings still show."""
    logger = logging.getLogger("paywise")
    level = logger.level
    logger.setLevel(logging.WARNING)
    try:
        yield
    finally:
        logger.setLevel(level)


def offline_report(runs: int = LOCAL_RUNS) -> list[str]:
    # Rules everywhere: the offline numbers never call the LLM, whatever .env says.
    with env(PARSER_MODE="rules", COVERAGE_MODE="rules"):
        from app import main  # noqa: F401  (sets up the "paywise" log handler before it is quieted)

        with quiet_app_logs():
            return [scenarios_line(), coverage_line(), local_check_line(runs)]


# --- Live ------------------------------------------------------------------------------------------


def _timed(method: str, url: str, body: dict | None) -> tuple[float, int | str, object]:
    """One request on a new connection: (ms, status code or error name, parsed JSON or None)."""
    import httpx

    started = time.perf_counter()
    try:
        with httpx.Client(timeout=LIVE_TIMEOUT_S) as client:
            response = client.request(method, url, json=body)
        elapsed = (time.perf_counter() - started) * 1000
        try:
            data = response.json()
        except ValueError:
            data = None
        return elapsed, response.status_code, data
    except httpx.HTTPError as exc:
        return (time.perf_counter() - started) * 1000, type(exc).__name__, None


def live_lines(base_url: str, runs: int = LIVE_RUNS) -> list[str]:
    lines = []

    warmup_ms, warmup_code, _ = _timed("GET", f"{base_url}/health", None)
    times, codes, ok = [], [], 0
    for _ in range(runs):
        elapsed, code, data = _timed("GET", f"{base_url}/health", None)
        times.append(elapsed)
        codes.append(code)
        ok += code == 200 and data == {"ok": True}
    lines.append(latency_line("LIVE_HEALTH", times, ok, runs,
                              f" http={status_counts(codes)} warmup_ms={ms(warmup_ms)} warmup_http={warmup_code}"))

    body, expected = s1_body(), s1_copy()
    warmup_ms, warmup_code, _ = _timed("POST", f"{base_url}/v1/check", body)
    times, codes, parse_ms, ok, exact = [], [], [], 0, 0
    for _ in range(runs):
        elapsed, code, data = _timed("POST", f"{base_url}/v1/check", body)
        times.append(elapsed)
        codes.append(code)
        ok += code == 200
        exact += code == 200 and is_s1(data, expected)
        timing = data.get("timingMs") if isinstance(data, dict) else None
        if isinstance(timing, dict) and isinstance(timing.get("parse"), (int, float)):
            parse_ms.append(float(timing["parse"]))
    server = (f" server_parse_p50_ms={ms(statistics.median(parse_ms))} server_parse_p90_ms={ms(percentile(parse_ms, 90))}"
              if parse_ms else " server_parse=none")
    lines.append(latency_line("LIVE_CHECK", times, ok, runs,
                              f" s1_copy={frac(exact, runs)} http={status_counts(codes)}{server} "
                              f"warmup_ms={ms(warmup_ms)} warmup_http={warmup_code}"))
    return lines


def llm_eval(rounds: int) -> None:
    """scripts/eval_parser.py prints its own aggregate lines (parser, then causes)."""
    key = os.environ.get("LLM_API_KEY", "").strip()
    if not key or key == "changeme":
        print("LLM_EVAL skipped: LLM_API_KEY is not set (load .env first)")
        return
    import eval_parser

    print(f"LLM_PARSER rounds={rounds} fixtures=fixtures/ocr/*.txt")
    asyncio.run(eval_parser.run(rounds, show_misses=False))
    print(f"LLM_CAUSES rounds={rounds} cases=fixtures/coverage_cases.json")
    asyncio.run(eval_parser.run_causes(rounds))


# --- Main ------------------------------------------------------------------------------------------


def commit() -> str:
    try:
        out = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=REPO, capture_output=True, text=True,
                             timeout=10)
        return out.stdout.strip() or "unknown"
    except (OSError, subprocess.SubprocessError):
        return "unknown"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--live", action="store_true", help="also measure Render and run the LLM evals")
    parser.add_argument("--base-url", default=LIVE_BASE_URL, help=f"live backend (default {LIVE_BASE_URL})")
    parser.add_argument("--rounds", type=int, default=3, help="LLM eval rounds over the fixtures (default 3)")
    args = parser.parse_args()

    now = dt.datetime.now().astimezone().isoformat(timespec="seconds")
    print(f"METRICS commit={commit()} at={now}")
    for line in offline_report():
        print(line, flush=True)
    if args.live:
        for line in live_lines(args.base_url.rstrip("/")):
            print(line, flush=True)
        llm_eval(args.rounds)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
