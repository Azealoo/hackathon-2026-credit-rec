"""Privacy guard for the repo's data (SPEC v2.1 §10, §15.4, §15.7 step 3; CLAUDE.md).

Every text file under fixtures/, data/, contracts/, demo-store/ and backend/ may hold only the
fake identity: "Alex Doe", "123 Example St, Seattle, WA 98000", alex@example.com, (555) 010-0000,
and last 4 of 1234, 5678 or 4321. No run of 12+ digits anywhere (card or account numbers).
Real-app screenshots never live in the repo (§15.2), so no file may match realapp-* or *-private*.

The name check is a heuristic: a common first name followed by a capitalised word. Obviously fake
surnames (Doe, Sample, Example, Test) pass, and so do a few fixed phrases where a first name is
part of a company or product name (NON_PERSON_PHRASES). Add to that list only for a real
non-person phrase, never for a person.
"""

import re
from fnmatch import fnmatch
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
SCANNED_DIRS = ["fixtures", "data", "contracts", "demo-store", "backend"]
SKIP_DIRS = {".venv", "__pycache__", ".pytest_cache", "node_modules", ".git", "DerivedData"}
SKIP_FILES = {"uv.lock"}
FORBIDDEN_FILE_PATTERNS = ["realapp-*", "*-private*"]

FAKE_NAME = "Alex Doe"
FAKE_STREET = "123 Example St"
FAKE_ZIP = "WA 98000"
FAKE_EMAIL_DOMAIN = "example.com"
FAKE_LAST4 = {"1234", "5678", "4321"}
FAKE_SURNAMES = {"Doe", "Sample", "Example", "Test"}

# Company and product names that start with a first name.
NON_PERSON_PHRASES = {
    "Chase Freedom", "Chase Bank", "Chase Travel", "Chase Card", "Chase Guide",
    "Virginia Surety", "Duane Reade",
}

# Common U.S. first names. Names that are also everyday capitalised words here (Will, Mark,
# May, Grace, Max, Bill, Cash…) are left out so the check doesn't fire on ordinary text.
FIRST_NAMES = {
    "Aaron", "Abigail", "Adam", "Alan", "Albert", "Alex", "Alexander", "Alexis", "Alice", "Amanda",
    "Amber", "Amy", "Andrea", "Andrew", "Angela", "Ann", "Anna", "Anthony", "Arthur", "Ashley",
    "Ava", "Avery", "Barbara", "Benjamin", "Betty", "Beverly", "Billy", "Bobby", "Brandon", "Brenda",
    "Brian", "Brittany", "Bruce", "Bryan", "Carl", "Carol", "Carolyn", "Casey", "Catherine", "Charles",
    "Charlotte", "Chase", "Cheryl", "Chloe", "Chris", "Christian", "Christina", "Christine",
    "Christopher", "Cynthia", "Daniel", "Danielle", "David", "Debra", "Deborah", "Denise", "Dennis",
    "Diana", "Diane", "Donald", "Donna", "Doris", "Dorothy", "Douglas", "Dylan", "Edward", "Elijah",
    "Elizabeth", "Emily", "Emma", "Eric", "Ethan", "Eugene", "Evelyn", "Frances", "Frank", "Gabriel",
    "Gary", "George", "Gerald", "Gloria", "Gregory", "Hannah", "Harold", "Heather", "Helen", "Henry",
    "Isabella", "Jack", "Jacob", "Jacqueline", "Jamie", "James", "Janet", "Janice", "Jason", "Jean",
    "Jeffrey", "Jennifer", "Jeremy", "Jerry", "Jesse", "Jessica", "Joan", "Joe", "John", "Johnny",
    "Jonathan", "Jordan", "Jose", "Joseph", "Joshua", "Joyce", "Juan", "Judith", "Judy", "Julia",
    "Julie", "Justin", "Karen", "Katherine", "Kathleen", "Kathryn", "Kayla", "Keith", "Kelly",
    "Kenneth", "Kevin", "Kimberly", "Kyle", "Larry", "Laura", "Lauren", "Lawrence", "Liam", "Lily",
    "Linda", "Lisa", "Logan", "Lori", "Louis", "Lucas", "Madison", "Margaret", "Maria", "Marilyn",
    "Martha", "Mary", "Matthew", "Megan", "Melissa", "Mia", "Michael", "Michelle", "Morgan",
    "Nancy", "Nathan", "Natalie", "Nicholas", "Nicole", "Noah", "Olivia", "Oliver", "Pamela",
    "Patricia", "Patrick", "Paul", "Peter", "Philip", "Quinn", "Rachel", "Ralph", "Randy", "Raymond",
    "Rebecca", "Richard", "Riley", "Robert", "Roger", "Ronald", "Roy", "Russell", "Ruth", "Ryan",
    "Samantha", "Samuel", "Sandra", "Sara", "Sarah", "Scott", "Sean", "Sharon", "Shirley", "Sophia",
    "Stephanie", "Stephen", "Steven", "Susan", "Taylor", "Teresa", "Terry", "Theresa", "Thomas",
    "Timothy", "Tyler", "Victoria", "Vincent", "Virginia", "Walter", "Wayne", "William", "Willie",
    "Zachary", "Zoe",
}

LONG_DIGIT_RUN = re.compile(r"\d{12,}")
# Overlapping "Firstname Lastname" pairs on one line.
NAME_PAIR = re.compile(r"(?=\b([A-Z][a-z]+) ([A-Z][a-z]+)\b)")
STREET = re.compile(
    r"\b\d{1,6}(?:[ \t]+[A-Z][A-Za-z]*\.?){1,4}[ \t]+"
    r"(?:St|Street|Ave|Avenue|Rd|Road|Blvd|Boulevard|Dr|Drive|Ln|Lane|Way|Ct|Court|Pl|Place|Pkwy|Parkway"
    r"|Hwy|Highway|Ter|Terrace|Cir|Circle)\b"
)
STATES = (
    "AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC "
    "ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY DC"
).split()
ZIP = re.compile(r"\b(?:" + "|".join(STATES) + r")[ \t]+\d{5}(?:-\d{4})?\b")
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,})")
LAST4 = re.compile(r"(?:••|••|ending in )\s?(\d{4})\b")


def skipped(path: Path) -> bool:
    return any(part in SKIP_DIRS for part in path.parts) or path.name in SKIP_FILES


def scanned_files() -> list[Path]:
    files = []
    for top in SCANNED_DIRS:
        files += [p for p in sorted((REPO / top).rglob("*")) if p.is_file() and not skipped(p.relative_to(REPO))]
    return files


def text_files() -> list[tuple[str, str]]:
    """(repo-relative path, text) for every scanned UTF-8 file; binary files (PNGs) are skipped."""
    out = []
    for path in scanned_files():
        try:
            out.append((str(path.relative_to(REPO)), path.read_text(encoding="utf-8")))
        except UnicodeDecodeError:
            continue
    return out


TEXT_FILES = text_files()
IDS = [name for name, _ in TEXT_FILES]


def real_looking_names(text: str) -> set[str]:
    found = set()
    for first, last in NAME_PAIR.findall(text):
        pair = f"{first} {last}"
        if first in FIRST_NAMES and last not in FAKE_SURNAMES and pair not in NON_PERSON_PHRASES:
            found.add(pair)
    return found


def test_scan_covers_the_data_folders():
    names = set(IDS)
    for expected in ["data/cards.json", "contracts/common.schema.json", "demo-store/checkout.html",
                     "fixtures/scenarios.json", "backend/app/models.py"]:
        assert expected in names
    assert not any("/.venv/" in n or n.endswith("uv.lock") for n in names)


@pytest.mark.parametrize("name, text", TEXT_FILES, ids=IDS)
def test_no_long_digit_runs(name, text):
    assert LONG_DIGIT_RUN.findall(text) == []


@pytest.mark.parametrize("name, text", TEXT_FILES, ids=IDS)
def test_only_the_fake_identity(name, text):
    assert real_looking_names(text) == set(), "real-looking names"
    assert set(STREET.findall(text)) <= {FAKE_STREET}, "street addresses"
    assert set(ZIP.findall(text)) <= {FAKE_ZIP}, "state + ZIP"
    assert {domain.lower() for domain in EMAIL.findall(text)} <= {FAKE_EMAIL_DOMAIN}, "email domains"
    assert set(LAST4.findall(text)) <= FAKE_LAST4, "last 4"


def test_no_real_app_files_in_the_repo():
    hits = []
    for path in REPO.rglob("*"):
        rel = path.relative_to(REPO)
        if skipped(rel):
            continue
        if any(fnmatch(path.name, pattern) for pattern in FORBIDDEN_FILE_PATTERNS):
            hits.append(str(rel))
    assert hits == []


def test_wallet_last4_are_fake():
    import json

    wallets = json.loads((REPO / "fixtures" / "wallets.json").read_text(encoding="utf-8"))["wallets"]
    last4 = [card["last4"] for wallet in wallets for card in wallet["cards"]]
    assert last4 and set(last4) <= FAKE_LAST4


OCR_FILES = sorted((REPO / "fixtures" / "ocr").glob("*.txt"))


def test_there_are_ocr_fixtures():
    assert len(OCR_FILES) == 7


@pytest.mark.parametrize("path", OCR_FILES, ids=[p.name for p in OCR_FILES])
def test_ocr_text_is_redacted(path):
    """Expected on-device OCR output after redaction (§15.7 step 8): nothing personal leaves the phone."""
    text = path.read_text(encoding="utf-8")
    assert LONG_DIGIT_RUN.search(text) is None
    assert "@" not in text
    assert "(555)" not in text
    assert FAKE_NAME not in text
    assert "Example St" not in text
    assert FAKE_ZIP not in text
    # The last 4 never leaves the phone (§3 principle 4): cards read "Visa [CARD]".
    assert LAST4.search(text) is None
    assert re.search(r"(?:••|••)\s?\d", text) is None


@pytest.mark.parametrize(
    "text, hit",
    [
        ("Ship to Mary" + " Smith", True),  # split so this file passes its own scan
        ("Ship to Alex Doe", False),
        ("Jordan Sample · 2h", False),
        ("Chase Freedom Unlimited", False),
        ("Virginia Surety Company", False),
    ],
)
def test_name_heuristic(text, hit):
    assert bool(real_looking_names(text)) is hit


@pytest.mark.parametrize(
    "text, allowed",
    [
        ("123 Example St, Seattle, WA 98000", True),
        ("42 Pine" + " Street, Seattle, WA" + " 98101", False),
        ("Ceramic Coffee Mug, 12 oz", True),
        ("alex@example.com", True),
        ("someone" + "@gmail.com", False),
        ("Visa ••4321", True),
        ("Visa ••" + "9876", False),
    ],
)
def test_identity_patterns(text, allowed):
    ok = (
        set(STREET.findall(text)) <= {FAKE_STREET}
        and set(ZIP.findall(text)) <= {FAKE_ZIP}
        and {d.lower() for d in EMAIL.findall(text)} <= {FAKE_EMAIL_DOMAIN}
        and set(LAST4.findall(text)) <= FAKE_LAST4
    )
    assert ok is allowed
