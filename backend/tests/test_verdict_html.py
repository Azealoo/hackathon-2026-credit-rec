"""templates/verdict.html through POST /v1/coverage?format=html (SPEC v2.1 §5.5, §12.3, §15.7 step 12c;
docs/design.md §1-§4, §8).

Renders cases 1, 2, 7 and 13 and checks the §5.5 copy, the footer, the always-dark page, phone
width, no external resources, no "concept" label, and that every value is autoescaped.
"""

import copy
import json
import re
from html.parser import HTMLParser
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import catalog, coverage
from app.main import app

REPO = Path(__file__).resolve().parents[2]
CASES = {c["id"]: c for c in json.loads((REPO / "fixtures" / "coverage_cases.json").read_text(encoding="utf-8"))["cases"]}
DISCLAIMER = "Only the benefit administrator decides claims. Paywise never files for you."

client = TestClient(app)


class Page(HTMLParser):
    """Visible text (style skipped), plus every tag with its attributes."""

    def __init__(self, html: str):
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self.tags: list[tuple[str, dict]] = []
        self.footer: list[str] = []
        self._skip = 0
        self._in_footer = 0
        self.feed(html)
        self.text = " ".join(" ".join(self.parts).split())
        self.footer_text = " ".join(" ".join(self.footer).split())

    def handle_starttag(self, tag, attrs):
        self.tags.append((tag, dict(attrs)))
        if tag in ("style", "title"):
            self._skip += 1
        if tag == "footer":
            self._in_footer += 1

    def handle_endtag(self, tag):
        if tag in ("style", "title"):
            self._skip -= 1
        if tag == "footer":
            self._in_footer -= 1

    def handle_data(self, data):
        if not self._skip:
            self.parts.append(data)
            if self._in_footer:
                self.footer.append(data)


def render(case_id: int, purchase: dict | None = None, incident: dict | None = None) -> tuple[str, Page]:
    case = copy.deepcopy(CASES[case_id])
    case["purchase"].update(purchase or {})
    case["incident"].update(incident or {})
    response = client.post("/v1/coverage?format=html",
                           json={"purchase": case["purchase"], "incident": case["incident"], "asOf": case["asOf"]})
    assert response.status_code == 200, response.text
    assert response.headers["content-type"].startswith("text/html")
    return response.text, Page(response.text)


def style(html: str) -> str:
    return re.search(r"<style>(.*?)</style>", html, re.S).group(1)


def clause_line(card_id: str, benefit: str) -> str:
    source = catalog.card(card_id).protection(benefit).source
    return f"{source.document} · {source.section} · version {coverage.fmt_date(source.version_date)}"


FU = "chase-freedom-unlimited"
EW_CLAIM = catalog.card(FU).protection("extended_warranty").claim
PP_CLAIM = catalog.card(FU).protection("purchase_protection").claim

KEY_COPY = {
    1: [
        "May be eligible: Extended warranty (Freedom Unlimited).",
        "The maker's 1-year warranty ended Oct 17, 2027; the extra year runs to Oct 17, 2028.",
        "Notify by Mar 16, 2028; send documents by Apr 15, 2028, or as soon as reasonably possible.",
        "What to send", "Itemized receipt", "Card statement showing the purchase",
        "Original warranty", "Repair estimate",
        "Payout cap", "$1,499.00",
        clause_line(FU, "extended_warranty"),
        "You file it yourself at",
        "Aero 14 Laptop, 14-inch", "Lines across the screen. Never dropped.",
    ],
    2: [
        "Not covered.",
        "Damage was covered for 120 days (90 in NY), to Feb 14, 2027.",
        "The extended warranty covers failures, not drops.",
        clause_line(FU, "extended_warranty"),
        "Dropped or damaged · Dec 17, 2027",
    ],
    7: [
        "Not covered by your card yet: it's still under the maker's warranty.",
        "Contact the manufacturer first. The card's extra year starts Oct 17, 2027.",
        clause_line(FU, "extended_warranty"),
    ],
    13: [
        "May be eligible: Purchase protection, up to $500 of the $1,499.",
        "Theft is covered within 120 days (90 in NY), to Feb 14, 2027.",
        "Notify by Feb 14, 2027; send documents by Mar 16, 2027, or as soon as reasonably possible.",
        "Police report (made within 48 hours if you can)",
        "Payout cap", "$500.00",
        clause_line(FU, "purchase_protection"),
        "You file it yourself at",
    ],
}

ABSENT_COPY = {
    # §5.5: "...runs to Oct 17, 2028." with nothing after it, and "You file it yourself at {administrator url}".
    1: ["Assumed", "A failure without a drop", "You file it yourself with", EW_CLAIM.administrator],
    2: ["What to send", "Payout cap", "Notify by", "You file it yourself"],
    7: ["What to send", "Payout cap", "Notify by", "You file it yourself"],
    13: ["Assumed", "You file it yourself with", PP_CLAIM.administrator],
}


@pytest.mark.parametrize("case_id", sorted(KEY_COPY))
def test_key_copy(case_id):
    _, page = render(case_id)
    for text in KEY_COPY[case_id]:
        assert text in page.text, text
    for text in ABSENT_COPY[case_id]:
        assert text not in page.text, text


@pytest.mark.parametrize("case_id", sorted(KEY_COPY))
def test_footer_disclaimer_verbatim(case_id):
    _, page = render(case_id)
    assert page.footer_text == DISCLAIMER


@pytest.mark.parametrize("case_id, label", [(1, "May be eligible"), (13, "May be eligible"), (2, "Not covered"),
                                            (7, "Not covered"), (5, "Need more info")])
def test_verdict_glyph_is_not_only_color(case_id, label):
    """Shield + check for may_be_eligible, ✗ circle for not_covered, each with a text label."""
    html, page = render(case_id)
    glyphs = [attrs for tag, attrs in page.tags if tag == "svg" and attrs.get("class") == "glyph"]
    assert len(glyphs) == 1 and glyphs[0]["role"] == "img" and glyphs[0]["aria-label"] == label
    svg = re.search(r'<svg class="glyph".*?</svg>', html, re.S).group(0)
    if label == "May be eligible":
        assert "M12 2.6 19.4 5.4" in svg and 'class="mark"' in svg  # the design.md §5 shield
    else:
        assert "<circle" in svg and 'class="mark"' in svg


@pytest.mark.parametrize("case_id", sorted(KEY_COPY))
def test_contact_link(case_id):
    _, page = render(case_id)
    links = [attrs["href"] for tag, attrs in page.tags if tag == "a"]
    if case_id == 1:
        assert links == [EW_CLAIM.url]
    elif case_id == 13:
        assert links == [PP_CLAIM.url]
    else:
        assert links == []


@pytest.mark.parametrize("case_id", sorted(KEY_COPY))
def test_always_dark_phone_width_design_tokens(case_id):
    html, _ = render(case_id)
    css = style(html)
    assert '<meta name="color-scheme" content="dark">' in html
    assert "prefers-color-scheme" not in html  # never follows the system setting (design.md §1)
    assert re.search(r"--bg:\s*#000\b", css)
    assert re.search(r"--cell:\s*#1c1c1e\b", css)
    assert re.search(r"body\s*\{[^}]*background:\s*var\(--bg\)", css)
    assert re.search(r"html\s*\{[^}]*background:\s*var\(--bg\)", css)
    for token in ("--green: #30d158", "--red: #ff453a", "--notice: #ffd60a", "--fp-accent-dark: #5b74ff"):
        assert token in css
    assert "-apple-system, BlinkMacSystemFont" in css
    assert "font-variant-numeric: tabular-nums" in css
    assert "border-radius: 28px" in css  # verdict card (design.md §4)
    assert '<meta name="viewport" content="width=device-width' in html
    assert "max-width: 430px" in css
    widths = [int(w) for w in re.findall(r"(?<![-\w])(?:min-)?width:\s*(\d+)px", css)]
    assert widths and max(widths) <= 430  # nothing forces a horizontal scroll at phone width
    assert "overflow-wrap: anywhere" in css


@pytest.mark.parametrize("case_id", sorted(KEY_COPY))
def test_no_external_resources_and_no_scripts(case_id):
    html, page = render(case_id)
    lowered = html.lower()
    assert "<script" not in lowered
    assert "<link" not in lowered
    assert "@import" not in lowered and "url(" not in lowered
    assert not any("src" in attrs for _, attrs in page.tags)
    hrefs = [attrs["href"] for tag, attrs in page.tags if "href" in attrs]
    assert all(tag == "a" for tag, attrs in page.tags if "href" in attrs)
    assert all(href.startswith("https://") for href in hrefs)
    assert "default-src 'none'" in html


@pytest.mark.parametrize("case_id", sorted(KEY_COPY))
def test_no_concept_label(case_id):
    """§12.3: the app's own verdict page doesn't call itself a concept."""
    html, _ = render(case_id)
    assert "concept" not in html.lower()


def test_html_headers():
    case = CASES[1]
    response = client.post("/v1/coverage?format=html",
                           json={"purchase": case["purchase"], "incident": case["incident"], "asOf": case["asOf"]})
    assert response.headers["cache-control"] == "no-store"
    assert "default-src 'none'" in response.headers["content-security-policy"]


def test_autoescaping():
    item = '<script>alert("x")</script> Laptop & Co'
    description = "<img src=x onerror=alert(1)> it's \"broken\""
    html, page = render(1, purchase={"item": item}, incident={"description": description})
    assert "<script>" not in html and "<img" not in html
    assert "&lt;script&gt;" in html and "&lt;img src=x onerror=alert(1)&gt;" in html
    assert "&amp; Co" in html
    assert item in page.text and description in page.text  # shown as text, not markup
    assert not any(tag in ("script", "img") for tag, _ in page.tags)


def test_assumed_label_shows():
    _, page = render(1, purchase={"manufacturerWarrantySource": "assumed"})
    assert "Assumed" in page.text and "Don't know" in page.text
