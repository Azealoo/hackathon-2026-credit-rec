"""fixtures/replay/*.json (written by scripts/make_replay.py): valid responses, in step with the engine."""

import json
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "backend" / "scripts"))

import make_replay  # noqa: E402

from app.main import app  # noqa: E402

REPLAY = REPO / "fixtures" / "replay"
FILES = sorted(REPLAY.glob("*.json"))
EXPECTED_NAMES = {"northbay-electronics_149900.json", "northbay-electronics_109900.json",
                  "northbay-electronics_24900.json", "northbay-electronics_1800.json"}


@pytest.fixture(autouse=True)
def rules_parser(monkeypatch):
    monkeypatch.setenv("PARSER_MODE", "rules")


def test_one_replay_file_per_demo_checkout():
    assert {p.name for p in FILES} == EXPECTED_NAMES


@pytest.mark.parametrize("path", FILES, ids=[p.name for p in FILES])
def test_replay_file_matches_the_response_schema(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    assert [e.message for e in make_replay.validator().iter_errors(data)] == []
    merchant_id, total_cents = path.stem.rsplit("_", 1)
    assert data["cart"]["merchant"]["merchantId"] == merchant_id
    assert round(data["cart"]["totalUsd"] * 100) == int(total_cents)


@pytest.mark.parametrize("name", make_replay.CHECKOUTS)
def test_replay_file_equals_a_fresh_check(name):
    """Regenerate with `uv run python scripts/make_replay.py` after an engine or copy change."""
    text = (REPO / "fixtures" / "ocr" / f"{name}.txt").read_text(encoding="utf-8")
    fresh = TestClient(app).post("/v1/check", json=make_replay.request_body(text)).json()
    fresh["timingMs"] = {"parse": 0, "engine": 0}
    total_cents = round(fresh["cart"]["totalUsd"] * 100)
    stored = json.loads((REPLAY / f"{fresh['cart']['merchant']['merchantId']}_{total_cents}.json").read_text(encoding="utf-8"))
    assert stored == fresh


def test_s1_replay_has_the_exact_copy():
    data = json.loads((REPLAY / "northbay-electronics_149900.json").read_text(encoding="utf-8"))
    assert data["decision"]["copy"]["line2"] == "Adds a warranty year + $500 theft cover"
    assert data["decision"]["copy"]["line3"] == "$7.49 less cash back than Active Cash"
