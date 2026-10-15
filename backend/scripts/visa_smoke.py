"""Live G4 check (SPEC v2.1 §15.7 step 13): one Visa Acceptance sandbox authorization.

Run from backend/:  uv run python scripts/visa_smoke.py

Loads the repo's .env into the environment (variables already set win) and sends order
NB-100234, saved card demo-visa-1234, $1,499.00 through app.visa_acceptance, whatever PAY_MODE
says. It is an authorization only (capture=false); no money moves.

Prints only:
  HTTP=<status> TARGET=<signature spelling>
  STATUS=<status> PROCESSOR=<processor> TXN_ID_LEN=<n> TXN_ID_SUFFIX=<last 6>
  REASON=<Cybersource reason code> FIELDS=<field names from an error, if any>
Never a value from .env, the card number, the request or the raw response.

- HTTP 401 with "(request-target)": retries once with "request-target" (docs/visa-sandbox.md §4).
- No DEMO_TEST_CARD_MAP entry for the card: says so, then runs an auth probe instead (a signed
  request with no card). HTTP 400 about the missing card there means the merchant ID, key and
  signature work; 401 means they don't. A 400 does NOT show the merchant is enabled for card
  payments: only a real authorization (a DEMO_TEST_CARD_MAP entry) can show that, so G4 stays
  open until this script exits 0.

Exit code 0 only when the sandbox approved the order.
"""

import asyncio
import os
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
REPO = BACKEND.parent
sys.path.insert(0, str(BACKEND))

from app import visa_acceptance  # noqa: E402
from app.models import StorePayRequest  # noqa: E402

TARGETS = ("(request-target)", "request-target")


def load_dotenv(path: Path) -> None:
    """KEY=VALUE lines; # comments; optional export and matching quotes. Never prints values."""
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.removeprefix("export ").strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        os.environ.setdefault(key, value)


def report(outcome: visa_acceptance.PayOutcome, target: str) -> None:
    txn = outcome.response.transaction_id or ""
    print(f"HTTP={outcome.http_status} TARGET={target}")
    print(
        f"STATUS={outcome.response.status} PROCESSOR={outcome.response.processor} "
        f"TXN_ID_LEN={len(txn)} TXN_ID_SUFFIX={txn[-6:] or '-'}"
    )
    print(f"REASON={outcome.reason or '-'} FIELDS={','.join(outcome.fields) or '-'}")


async def main() -> int:
    load_dotenv(REPO / ".env")
    try:
        visa_acceptance.load_credentials(os.environ)
    except visa_acceptance.ConfigError as exc:
        print(f"CONFIG_ERROR={exc}")  # names keys only
        return 2

    request = StorePayRequest(order_id="NB-100234", saved_card_id="demo-visa-1234", amount_usd=1499.00)
    card_ready = True
    try:
        visa_acceptance.load_test_card(os.environ, request.saved_card_id)
    except visa_acceptance.ConfigError as exc:
        card_ready = False
        print(f"CARD_NOT_CONFIGURED={exc}")  # names keys and the saved-card ID only

    for target in TARGETS:
        if card_ready:
            outcome = await visa_acceptance.visa_pay(request, os.environ, request_target=target)
        else:
            print("AUTH_PROBE (signed request without a card; cannot be approved)")
            outcome = await visa_acceptance.probe_auth(os.environ, request_target=target)
        report(outcome, target)
        if outcome.http_status != 401:
            break
    return 0 if outcome.response.status == "approved" else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
