"""Why did a Visa Acceptance sandbox authorization fail? Prints the processor's reply for one
transaction ID from the Transaction Details API (GET /tss/v2/transactions/{id}).

    cd backend && set -a && source ../.env && set +a && uv run python scripts/visa_txn.py <transactionId>

Needs only VISA_ACCEPTANCE_MERCHANT_ID / _KEY_ID / _SECRET_KEY. Prints reason codes, the
processor name and its message; digit runs of 6+ are shortened, and no card or secret is printed.
"""

import asyncio
import base64
import hashlib
import hmac
import json
import os
import re
import sys

import httpx

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app import visa_acceptance as va  # noqa: E402

HOST = "apitest.cybersource.com"


def _short(value: object) -> str:
    text = json.dumps(value, ensure_ascii=False)
    return re.sub(r"\d{6,}", lambda m: "…" + m.group(0)[-4:], text)[:400]


async def details(transaction_id: str) -> httpx.Response:
    credentials = va.load_credentials(os.environ)
    path = f"/tss/v2/transactions/{transaction_id}"
    date = va.http_date()
    to_sign = "\n".join([
        f"host: {HOST}", f"date: {date}", f"(request-target): get {path}",
        f"v-c-merchant-id: {credentials.merchant_id}",
    ])
    signature = base64.b64encode(hmac.new(credentials.secret, to_sign.encode(), hashlib.sha256).digest()).decode()
    headers = {
        "v-c-merchant-id": credentials.merchant_id, "Host": HOST, "Date": date,
        "Accept": "application/hal+json;charset=utf-8",
        "Signature": (
            f'keyid="{credentials.key_id}", algorithm="HmacSHA256", '
            f'headers="host date (request-target) v-c-merchant-id", signature="{signature}"'
        ),
    }
    async with httpx.AsyncClient(base_url=f"https://{HOST}", timeout=20) as client:
        return await client.get(path, headers=headers)


async def main(transaction_ids: list[str]) -> int:
    for transaction_id in transaction_ids:
        if not re.fullmatch(r"[0-9]{10,32}", transaction_id):
            print(f"skip {transaction_id!r}: not a transaction ID")
            continue
        response = await details(transaction_id)
        print(f"TXN …{transaction_id[-6:]} HTTP={response.status_code}")
        if response.status_code != 200:
            continue
        payload = response.json()
        for app in (payload.get("applicationInformation") or {}).get("applications", []):
            if app.get("name") == "ics_auth":
                print(f"  auth reasonCode={app.get('reasonCode')} rFlag={app.get('rFlag')} rMessage={app.get('rMessage')!r}")
        processor = ((payload.get("processorInformation") or {}).get("processor") or {}).get("name")
        print(f"  processor={processor}")
        if "errorInformation" in payload:
            print(f"  error={_short(payload['errorInformation'])}")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main(sys.argv[1:])))
