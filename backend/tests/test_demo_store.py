"""demo-store/ (SPEC v2.1 §9.3, §15.7 step 5): the static Northbay Electronics pages stay safe
to serve, both from the Render static site and from the backend at /store/."""

import json
import re
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
STORE = REPO / "demo-store"
PAGES = ["index.html", "checkout.html", "confirm.html", "feed.html"]
FILES = PAGES + ["store.css", "store.js"]

CSP = (
    '<meta http-equiv="Content-Security-Policy" content="default-src \'self\'; img-src \'self\' data:; '
    "style-src 'self'; script-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'; "
    "object-src 'none'\">"
)


def read(name: str) -> str:
    return (STORE / name).read_text(encoding="utf-8")


def store_files() -> list[Path]:
    return sorted(path for path in STORE.rglob("*") if path.is_file())


@pytest.mark.parametrize("name", FILES)
def test_store_file_exists(name):
    assert (STORE / name).is_file()


def test_no_long_digit_runs():
    for path in store_files():
        assert not re.search(r"\d{12,}", path.read_text(encoding="utf-8", errors="replace")), path.name


def test_links_are_relative_and_local():
    for path in store_files():
        text = path.read_text(encoding="utf-8", errors="replace")
        assert "http://" not in text and "https://" not in text, path.name
        assert not re.search(r"""(?:href|src)\s*=\s*["']?/|url\(\s*["']?/""", text), path.name
    # The only absolute path is the same-origin payment endpoint.
    js = read("store.js")
    assert set(re.findall(r"""["'`](/[^"'`]*)["'`]""", js)) == {"/v1/store/pay"}
    assert 'const PAY_URL = "/v1/store/pay";' in js


@pytest.mark.parametrize("name", PAGES)
def test_page_head_and_csp(name):
    html = read(name)
    assert CSP in html
    assert '<meta name="robots" content="noindex, nofollow">' in html
    # Mobile Safari would turn the contact phone into a tel: link and underline it in screenshots.
    assert '<meta name="format-detection" content="telephone=no">' in html
    assert "viewport-fit=cover" not in html
    # The CSP blocks inline code, so none may creep in.
    assert not re.search(r"<script(?![^>]*\ssrc=)", html), "inline <script>"
    assert not re.search(r"\sstyle\s*=", html), "style attribute"
    assert not re.search(r"\son[a-z]+\s*=", html), "on* handler attribute"


def test_store_js_items_cards_and_order():
    js = read("store.js")
    prices = {"laptop": 149900, "laptop-renewed": 109900, "earbuds": 24900, "mug": 1800}
    for key, cents in prices.items():
        assert re.search(rf'"{re.escape(key)}":\s*\{{[^}}]*\bpriceCents:\s*{cents}\b', js), key
    schema = json.loads((REPO / "contracts" / "store-pay.request.schema.json").read_text(encoding="utf-8"))
    card_id_pattern = schema["properties"]["savedCardId"]["pattern"]
    for card_id in ["demo-mastercard-5678", "demo-visa-4321", "demo-visa-1234"]:
        assert f'"{card_id}"' in js
        assert re.fullmatch(card_id_pattern, card_id)
    assert '"NB-100234"' in js


def test_feed_has_no_checkout_words():
    # The feed-not-checkout fixture must fail the on-device checkout gate.
    text = re.sub(r"<[^>]+>", " ", read("feed.html")).lower()
    for word in ["$", "total", "checkout", "place order", "pay", "order", "cart", "northbay"]:
        assert word not in text, word
    assert not re.search(r"\d\.\d{2}\b", text), "money amount"
