"""Startup and /health (review 2026-10-17, Backend reliability): what is deployed, in which modes, warmed up."""

import logging
import os
import subprocess
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.main import app

BACKEND = Path(__file__).resolve().parents[1]
FAKE_SHA = "c0ffee" * 6 + "abcd"  # 40 hex characters, obviously not a real commit


@pytest.fixture(autouse=True)
def default_modes(monkeypatch):
    for name in ("PARSER_MODE", "COVERAGE_MODE", "PAY_MODE", "RENDER_GIT_COMMIT"):
        monkeypatch.delenv(name, raising=False)


def run_python(code: str, **env: str) -> str:
    """Run `code` in a fresh interpreter (a cold start), with `env` added; returns its stdout."""
    clean = {k: v for k, v in os.environ.items() if k not in ("RENDER", "PARSER_MODE", "COVERAGE_MODE", "PAY_MODE")}
    done = subprocess.run([sys.executable, "-c", code], cwd=BACKEND, env=clean | env, capture_output=True, text=True,
                          timeout=60)
    assert done.returncode == 0, done.stderr
    return done.stdout


def test_health():
    response = TestClient(app).get("/health")
    assert response.status_code == 200
    assert response.json() == {"ok": True, "commit": None, "modes": {"parser": "rules", "coverage": "rules", "pay": "mock"}}


def test_health_shows_the_deployed_commit_and_modes(monkeypatch):
    """Render sets RENDER_GIT_COMMIT at build and run time: /health says which commit is live."""
    monkeypatch.setenv("RENDER_GIT_COMMIT", FAKE_SHA)
    monkeypatch.setenv("PARSER_MODE", "llm")
    monkeypatch.setenv("COVERAGE_MODE", "LLM")
    monkeypatch.setenv("PAY_MODE", "visa_acceptance")
    assert TestClient(app).get("/health").json() == {
        "ok": True, "commit": FAKE_SHA, "modes": {"parser": "llm", "coverage": "llm", "pay": "visa_acceptance"}}


def test_startup_logs_the_effective_modes_and_warns_on_unknown_values(monkeypatch, caplog):
    """PARSER_MODE=lllm and PAY_MODE=visa-acceptance ran rules and mock with no warning."""
    monkeypatch.setenv("PARSER_MODE", "lllm")
    monkeypatch.setenv("COVERAGE_MODE", "changeme")  # the .env.example placeholder means unset: no warning
    monkeypatch.setenv("PAY_MODE", "visa-acceptance")
    monkeypatch.setenv("RENDER_GIT_COMMIT", FAKE_SHA)
    with caplog.at_level(logging.INFO, logger="paywise"), TestClient(app):
        pass
    records = [r for r in caplog.records if r.name == "paywise.config"]
    warnings = sorted(r.getMessage() for r in records if r.levelno == logging.WARNING)
    assert len(warnings) == 2
    assert "PARSER_MODE" in warnings[0] and "'lllm'" in warnings[0] and "rules" in warnings[0]
    assert "PAY_MODE" in warnings[1] and "'visa-acceptance'" in warnings[1] and "mock" in warnings[1]
    (info,) = [r.getMessage() for r in records if r.levelno == logging.INFO]
    assert "parser=rules coverage=rules pay=mock" in info and FAKE_SHA[:7] in info


def test_known_modes_log_no_warning(monkeypatch, caplog):
    monkeypatch.setenv("PARSER_MODE", "LLM")
    monkeypatch.setenv("COVERAGE_MODE", " rules ")
    monkeypatch.setenv("PAY_MODE", "")
    with caplog.at_level(logging.INFO, logger="paywise"), TestClient(app):
        pass
    assert not [r for r in caplog.records if r.name == "paywise.config" and r.levelno >= logging.WARNING]


def test_the_llm_modules_load_at_startup():
    """The anthropic import took about 1 s, outside the 4.5 s parse deadline, on the first LLM request after a deploy."""
    out = run_python("import sys, app.main; print(sorted(m for m in ('anthropic', 'app.llm', 'app.parser_llm') "
                     "if m in sys.modules))")
    assert out.strip() == "['anthropic', 'app.llm', 'app.parser_llm']"


API_DOCS = ("/docs", "/redoc", "/openapi.json")
PROBE = ("from fastapi.testclient import TestClient; from app.main import app; c = TestClient(app); "
         "print(' '.join(str(c.get(p).status_code) for p in {paths!r}))").format(paths=API_DOCS)


def test_api_docs_are_off_on_render():
    """Render sets RENDER=true on every service; /docs also loaded an unpinned swagger-ui from a CDN."""
    assert run_python(PROBE, RENDER="true").split() == ["404", "404", "404"]


def test_api_docs_stay_on_for_local_development():
    assert run_python(PROBE).split() == ["200", "200", "200"]
