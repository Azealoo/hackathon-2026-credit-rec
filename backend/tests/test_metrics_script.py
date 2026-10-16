"""scripts/metrics.py (SPEC §13, §15.7 step 15): the aggregation helpers, and that the offline report
prints aggregates only and leaves the environment as it found it. No network."""

import importlib.util
import os
import re
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "metrics.py"
_spec = importlib.util.spec_from_file_location("paywise_metrics", SCRIPT)
metrics = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(metrics)


def test_percentile_is_nearest_rank():
    values = [float(v) for v in range(1, 11)]  # 1..10
    assert metrics.percentile(values, 90) == 9
    assert metrics.percentile(values, 100) == 10
    assert metrics.percentile(values, 10) == 1
    assert metrics.percentile([7.0], 90) == 7
    assert metrics.percentile([3.0, 1.0, 2.0], 50) == 2  # order doesn't matter
    with pytest.raises(ValueError):
        metrics.percentile([], 50)


def test_summarize_uses_the_median_for_p50():
    s = metrics.summarize([4.0, 1.0, 3.0, 2.0])
    assert s == {"n": 4, "p50": 2.5, "p90": 4.0, "max": 4.0}


def test_ms_formatting():
    assert metrics.ms(0.634) == "0.63"
    assert metrics.ms(9.999) == "10.00"
    assert metrics.ms(1234.4) == "1234"


def test_status_counts_and_fractions():
    assert metrics.status_counts([200] * 9 + ["ReadTimeout"]) == "200x9,ReadTimeoutx1"
    assert metrics.status_counts([500, 200, 200]) == "200x2,500x1"
    assert metrics.frac(3, 10) == "3/10"
    assert metrics.yes(True) == "yes" and metrics.yes(False) == "no"


def test_latency_line_with_and_without_samples():
    line = metrics.latency_line("LIVE_CHECK", [1000.0, 1200.0, 3000.0], 3, 3, " s1_copy=3/3")
    assert line == "LIVE_CHECK runs=3 ok=3/3 p50_ms=1200 p90_ms=3000 max_ms=3000 s1_copy=3/3"
    assert metrics.latency_line("LIVE_CHECK", [], 0, 10) == "LIVE_CHECK runs=0 ok=0/10"


def test_is_s1_matches_only_the_exact_copy():
    expected = metrics.s1_copy()
    assert metrics.is_s1({"decision": {"copy": dict(expected)}}, expected)
    assert not metrics.is_s1({"decision": {"copy": dict(expected, line3="other")}}, expected)
    assert not metrics.is_s1(None, expected)
    assert not metrics.is_s1({"error": {"code": "privacy_rejected"}}, expected)


def test_env_puts_values_back(monkeypatch):
    monkeypatch.setenv("PARSER_MODE", "llm")
    monkeypatch.delenv("COVERAGE_MODE", raising=False)
    with metrics.env(PARSER_MODE="rules", COVERAGE_MODE="rules"):
        assert os.environ["PARSER_MODE"] == "rules" and os.environ["COVERAGE_MODE"] == "rules"
    assert os.environ["PARSER_MODE"] == "llm"
    assert "COVERAGE_MODE" not in os.environ


def _spy_parse_screen(monkeypatch, fake_name=None):
    """Wrap app.main.parse_screen and record the parser name of every call. fake_name relabels the
    result, to show the CHECK_LOCAL line prints what was measured."""
    from app import main as app_main

    real, names = app_main.parse_screen, []

    async def spy(ocr_text):
        parsed, name = await real(ocr_text)
        name = fake_name or name
        names.append(name)
        return parsed, name

    monkeypatch.setattr(app_main, "parse_screen", spy)
    return names


def test_offline_report_prints_aggregates_only(monkeypatch):
    from app import middleware

    monkeypatch.setenv("PARSER_MODE", "llm")  # the report must force rules and never call the LLM
    monkeypatch.setenv("LLM_API_KEY", "changeme")  # with this key a forced-llm run falls back to rules_fallback
    names = _spy_parse_screen(monkeypatch)
    limit = middleware.LIMITER.per_minute
    lines = metrics.offline_report(runs=5)

    # "rules", not "rules_fallback": the rules path was chosen, the LLM path was never tried.
    assert names == ["rules"] * 6  # 1 warm-up + 5 timed

    assert [line.split()[0] for line in lines] == ["SCENARIOS", "COVERAGE", "CHECK_LOCAL"]
    assert re.fullmatch(r"SCENARIOS pass=\d+/22 false_switches=\d+ protection_drops=\d+ must_pass_5_21_22=(yes|no)",
                        lines[0])
    assert re.fullmatch(r"COVERAGE pass=\d+/13 not_covered_right=\d+/\d+ cites_section_and_date=\d+/13 "
                        r"cap500_cases_3_13=(yes|no)", lines[1])
    assert re.fullmatch(r"CHECK_LOCAL runs=5 ok=5/5 p50_ms=[\d.]+ p90_ms=[\d.]+ max_ms=[\d.]+ s1_copy=5/5 parser=rulesx5",
                        lines[2])
    # Nothing from a request or response body: no OCR text, merchant, item, money, or fake identity.
    text = "\n".join(lines)
    for leak in ("Northbay", "NORTHBAY", "Aero", "Laptop", "$", "Alex", "Freedom", "ocrText", "{"):
        assert leak not in text
    assert os.environ["PARSER_MODE"] == "llm"
    assert middleware.LIMITER.per_minute == limit
    from app import main as app_main
    assert app_main.parse_screen.__name__ == "spy"  # the script put back what it wrapped


def test_local_check_refuses_to_run_unless_rules(monkeypatch):
    monkeypatch.setenv("PARSER_MODE", "llm")
    names = _spy_parse_screen(monkeypatch)
    with pytest.raises(RuntimeError, match="PARSER_MODE=rules"):
        metrics.local_check_line(runs=2)
    assert names == []  # stopped before the first request


def test_local_check_prints_the_measured_parser(monkeypatch):
    monkeypatch.setenv("PARSER_MODE", "rules")
    _spy_parse_screen(monkeypatch, fake_name="rules_fallback")
    line = metrics.local_check_line(runs=3)
    assert line.endswith(" parser=rules_fallbackx3")
