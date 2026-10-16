"""Write fixtures/replay/<merchantId>_<totalCents>.json for the 4 demo checkouts (SPEC.md §15.7 step 10).

Each file is the real POST /v1/check response (rules parser + engine) for the demo-3card wallet on
2026-10-17 (R11: the phone's replay key is merchant + total only, so one wallet per checkout).
timingMs is zeroed so regenerating gives the same bytes. Every file must validate against
contracts/check.response.schema.json.

    cd backend && uv run python scripts/make_replay.py
"""

import json
import os
import sys
from decimal import Decimal
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
REPO = BACKEND.parent
sys.path.insert(0, str(BACKEND))

from fastapi.testclient import TestClient  # noqa: E402
from jsonschema import Draft202012Validator  # noqa: E402
from referencing import Registry  # noqa: E402
from referencing.jsonschema import DRAFT202012  # noqa: E402

from app.main import app  # noqa: E402

CHECKOUTS = ["laptop-checkout", "laptop-renewed-checkout", "earbuds-checkout", "mug-checkout"]
WALLET_ID = "demo-3card"
CLIENT_DATE = "2026-10-17"
REQUEST_ID = "5f0c0000-aaaa-4bbb-8ccc-ddddeeeeffff"  # the contracts' example id; the phone keys on merchant + total
REPLAY_DIR = REPO / "fixtures" / "replay"


def validator() -> Draft202012Validator:
    schemas = {p.name: json.loads(p.read_text(encoding="utf-8")) for p in (REPO / "contracts").glob("*.schema.json")}
    registry = Registry().with_resources((name, DRAFT202012.create_resource(s)) for name, s in schemas.items())
    return Draft202012Validator({"$ref": "check.response.schema.json"}, registry=registry,
                                format_checker=Draft202012Validator.FORMAT_CHECKER)


def request_body(ocr_text: str) -> dict:
    wallets = json.loads((REPO / "fixtures" / "wallets.json").read_text(encoding="utf-8"))["wallets"]
    cards = next(w for w in wallets if w["id"] == WALLET_ID)["cards"]
    return {
        "requestId": REQUEST_ID,
        "client": {"app": "paywise-ios", "version": "0.1.0"},
        "clientDate": CLIENT_DATE,
        "screen": {"ocrText": ocr_text, "redactions": ["card_number", "address", "email", "phone"],
                   "ocrConfidence": 0.93},
        "wallet": {"cards": [{"cardId": c["cardId"], "isDefault": i == 0} for i, c in enumerate(cards)]},
        "prefs": {"paysInFull": None},
    }


def main() -> int:
    os.environ["PARSER_MODE"] = "rules"  # read per request by app.parsing; never call the LLM here
    client, check = TestClient(app), validator()
    REPLAY_DIR.mkdir(parents=True, exist_ok=True)
    for name in CHECKOUTS:
        text = (REPO / "fixtures" / "ocr" / f"{name}.txt").read_text(encoding="utf-8")
        response = client.post("/v1/check", json=request_body(text))
        if response.status_code != 200:
            print(f"{name}: HTTP {response.status_code}", file=sys.stderr)
            return 1
        data = response.json()
        data["timingMs"] = {"parse": 0, "engine": 0}
        errors = [e.message for e in check.iter_errors(data)]
        if errors:
            print(f"{name}: doesn't match check.response.schema.json: {errors}", file=sys.stderr)
            return 1
        merchant_id = data["cart"]["merchant"]["merchantId"]
        total_cents = int(Decimal(str(data["cart"]["totalUsd"])) * 100)
        path = REPLAY_DIR / f"{merchant_id}_{total_cents}.json"
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        decision = data["decision"]
        print(f"{path.relative_to(REPO)}: {decision['kind']}/{decision['reason']} -> {decision['recommendedCardId']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
