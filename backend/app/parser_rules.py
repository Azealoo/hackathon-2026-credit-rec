"""Rules parser: redacted OCR text -> ParsedScreen (SPEC.md §9.2, §15.7 step 4).

Reads the demo store's pages (fixtures/ocr/*.txt) and similar simple checkouts, deterministically.
It is the PARSER_MODE=rules path and the fallback when the LLM parser fails or is slow.

The keyword map below turns item names into catalog item-category ids. It is parser data (what
words mean), not card data: which categories are protection-relevant lives in data/cards.json.
Merchants are matched against the catalog's merchant names and domains (app/catalog.py).
"""

import re
from decimal import ROUND_HALF_UP, Decimal

from app import catalog
from app.models import Cart, CartConfidence, CartMerchant, Item, SelectedPayment, Upsells
from app.parsing import ParsedScreen

# --- Patterns -----------------------------------------------------------------------------------

MONEY = re.compile(r"(?<![\w$])\$\s?(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{2}))?(?![\d,])")
TOTAL_LINE = re.compile(
    r"^(?:order\s+|grand\s+|estimated\s+|your\s+)?total(?:\s+(?:due|today|to pay))?\b(?!\s+(?:savings|saved|discount))",
    re.I)
NON_ITEM_LINE = re.compile(
    r"^(?:sub\s?-?total|total|order total|grand total|estimated|shipping|delivery fee|delivery|handling|"
    r"(?:sales |estimated )?tax(?:es)?|discount|promo|coupon|savings|you save|you saved|fees?|service fee|"
    r"tip|pay with|paid with|paying with|payment|gift card balance|store credit|rewards|balance|amount due|"
    r"was|list price|reg\.?)\b",
    re.I)
STOP_LINE = re.compile(r"^(?:ship to|deliver to|shipping address|billing|contact|pay with|paid with|"
                       r"payment|place order|order summary|summary)\b", re.I)

COND_INLINE = re.compile(r"\s*[(\[](new|brand new|renewed|refurbished|used|pre-?owned)[^)\]]*[)\]]\s*$", re.I)
COND_NEW = re.compile(r"^(?:condition:?\s*)?(?:brand[\s-]new|new)(?:\s*[·•\-–,(]|$)", re.I)
COND_RENEWED = re.compile(r"^(?:condition:?\s*)?(?:certified\s+)?(?:renewed|refurbished|reconditioned|open[\s-]box)\b",
                          re.I)
COND_USED = re.compile(r"^(?:condition:?\s*)?(?:used|pre-?owned|second[\s-]hand)\b", re.I)
QTY = re.compile(r"^(?:qty|quantity)\s*:?\s*(\d{1,3})\b", re.I)
SOLD_BY = re.compile(r"^sold by:?\s+(.+)$", re.I)

CONFIRMATION = re.compile(
    r"\border\s+(?:placed|confirmed|complete|completed|received)\b|\bthank(?:s| you) for (?:your )?(?:order|purchase)\b"
    r"|\bpaid with\b|\border\s*(?:#|number\b|no\.)|\byour order (?:is|has been)\b",
    re.I)
PLACE_ORDER = re.compile(r"\b(?:place (?:your )?order|pay now|complete (?:purchase|order)|submit order|buy now)\b", re.I)

APPLE_PAY = re.compile(r"\bapple\s?pay\b|\s?pay\b", re.I)
NETWORK = re.compile(r"\b(visa|master\s?card|amex|american express|discover)\b", re.I)
CARD_ON_FILE = re.compile(r"\[CARD\]|\bend(?:ing|s) in\b|[•*]{2,}", re.I)
PAY_CONTEXT = re.compile(r"\b(?:pay(?:ing)? with|payment|card)\b", re.I)
CARD_FORM = re.compile(r"\bcard number\b|\bname on card\b|\bexpir(?:ation|y|es)\b|\bMM\s?/\s?YY\b|\bCVV\b|\bCVC\b"
                       r"|\bsecurity code\b", re.I)
BNPL = re.compile(r"\b(?:afterpay|klarna|affirm|sezzle|pay in 4|pay later|zip pay)\b", re.I)
PAYPAL = re.compile(r"\bpay\s?pal\b", re.I)
OTHER_WALLET = re.compile(r"\b(?:google pay|g pay|shop pay|amazon pay|venmo|cash app pay)\b", re.I)
# Phrases that contain a merchant name without naming the store ("Apple Pay" on a Nike checkout).
NOT_A_STORE = re.compile(r"\b(?:apple\s?pay|apple card|amazon pay|walmart pay|target circle card)\b", re.I)
HEADING_SKIP = re.compile(r"^(?:checkout|secure checkout|cart|bag|your cart|your bag|order summary|review(?: order)?|"
                          r"payment|shipping|delivery|sign in|menu|back)$", re.I)
DOMAIN = re.compile(r"\b(?:[a-z0-9-]+\.)+(?:com|net|org|co|us|store|shop)\b", re.I)

NETWORK_IDS = {"visa": "visa", "mastercard": "mastercard", "master card": "mastercard", "amex": "amex",
               "american express": "amex", "discover": "discover"}

# --- Parser data: item-name keywords -> itemCategories ids (first match in this order wins) ----

CATEGORY_KEYWORDS: list[tuple[str, tuple[str, ...]]] = [
    ("services", ("protection plan", "service plan", "warranty plan", "care plan", "applecare", "extended warranty",
                  "accident protection")),
    ("gift_card", ("gift card", "egift", "e-gift", "gift certificate")),
    ("computers", ("laptop", "laptops", "notebook computer", "macbook", "chromebook", "desktop", "computer", "imac")),
    ("audio", ("earbuds", "earbud", "headphones", "headphone", "earphones", "headset", "speaker", "speakers",
               "soundbar", "airpods", "turntable")),
    ("phones", ("iphone", "smartphone", "phone", "phones", "pixel phone", "galaxy phone")),
    ("cameras", ("camera", "cameras", "lens", "gopro", "dslr", "mirrorless", "camcorder")),
    ("electronics", ("tv", "television", "monitor", "tablet", "ipad", "smartwatch", "game console", "console",
                     "charger", "router", "drone", "e-reader", "kindle", "projector", "keyboard", "mouse")),
    ("appliances", ("blender", "microwave", "vacuum", "toaster", "coffee maker", "espresso machine", "air fryer",
                    "kettle", "refrigerator", "washer", "dryer", "dishwasher", "mixer")),
    ("tools", ("drill", "saw", "wrench", "toolkit", "tool set", "screwdriver", "sander")),
    ("bikes", ("bike", "bicycle", "e-bike", "ebike")),
    ("instruments", ("guitar", "piano", "violin", "drum", "drums", "ukulele", "cello", "saxophone")),
    ("apparel", ("shoes", "shoe", "sneakers", "sneaker", "boots", "shirt", "t-shirt", "tee", "jacket", "hoodie",
                 "sweater", "pants", "jeans", "shorts", "socks", "dress", "leggings", "coat")),
    ("home", ("mug", "mugs", "cup", "cups", "plate", "plates", "bowl", "bowls", "towel", "towels", "pillow",
              "blanket", "candle", "lamp", "storage", "bins", "sheets", "cookware", "frame", "vase")),
    ("pharmacy", ("vitamin", "vitamins", "multivitamin", "medicine", "ibuprofen", "allergy", "prescription",
                  "pain relief")),
    ("grocery", ("snack", "snacks", "cereal", "coffee beans", "ground coffee", "groceries")),
]
_CATEGORY_PATTERNS = [(cat, re.compile(r"\b(?:" + "|".join(re.escape(k) for k in words) + r")\b", re.I))
                      for cat, words in CATEGORY_KEYWORDS]

# Common English and checkout words, for telling a blurry screen ("Chcc kcut") from a readable
# page that simply isn't a checkout (a social feed).
COMMON_WORDS = frozenset("""
a about above after again all also am an and any are as at back be because been before being below best big
book both but buy by can card cart change checkout come comments contact could day days delivery did do does
done down each early even every few find first for free from get go good got great had has have he her here
him his home how i if in into is it its item items just know last like likes made make many me more most move
moves moving my new next no not now of off on one only or order other our out over pay place price qty quantity
really right said same save see shall she ship shipping shop should since so some still store such sunday monday
saturday friday thursday tuesday wednesday take than thank thanks that the their them then there these they
thing think this those through time to today together tonight too top total two under until up us very want was
way we week well were what when where which while who why will with work worth would year yes yet you your
subtotal tax payment summary delivery arrives free continue shopping approved account apply discount gift
promo code review secure sale money nothing here fictional demo hackathon is for and no
""".split())

READABLE_MIN_KNOWN = 0.2
READABLE_MAX_VOWELLESS = 0.3

CONFIDENCE_MERCHANT_CATALOG = 0.97
CONFIDENCE_MERCHANT_HEADING = 0.6
CONFIDENCE_TOTAL = 0.98
CONFIDENCE_ITEMS = 0.92
CONFIDENCE_ITEMS_DOUBTFUL = 0.6


# --- Helpers ------------------------------------------------------------------------------------


def _money(match: re.Match) -> Decimal:
    return Decimal(match.group(1).replace(",", "") + "." + (match.group(2) or "00"))


def _lines(text: str) -> list[str]:
    out = []
    for raw in text.replace(" ", " ").splitlines():
        line = raw.strip()
        if line:
            out.append(line)
    return out


def _clean_name(name: str) -> str:
    name = " ".join(name.split())
    return name.strip(" \t·•-–—:|")


def readable(text: str) -> bool:
    """Mostly real words? (unreadable = blurry OCR, not merely a page that isn't a checkout)."""
    tokens = re.findall(r"[A-Za-z]{2,}", text)
    if len(tokens) < 3:
        return False
    known = sum(t.lower() in COMMON_WORDS for t in tokens) / len(tokens)
    long_tokens = [t for t in tokens if len(t) >= 3]
    vowelless = (sum(not re.search(r"[aeiouyAEIOUY]", t) for t in long_tokens) / len(long_tokens)
                 if long_tokens else 1.0)
    return known >= READABLE_MIN_KNOWN and vowelless < READABLE_MAX_VOWELLESS


def _total(lines: list[str]) -> tuple[int | None, Decimal | None]:
    found: tuple[int | None, Decimal | None] = (None, None)
    for index, line in enumerate(lines):
        if TOTAL_LINE.match(line):
            amounts = list(MONEY.finditer(line))
            if amounts:
                found = (index, _money(amounts[-1]))
    return found


def _merchant(lines: list[str], text: str) -> tuple[CartMerchant, float]:
    for line in lines:  # 1. a line that is exactly a catalog merchant name ("NORTHBAY Electronics")
        merchant = catalog.merchant_by_name(line)
        if merchant:
            return CartMerchant(name=merchant.names[0], merchant_id=merchant.id), CONFIDENCE_MERCHANT_CATALOG
    for domain in DOMAIN.findall(text):  # 2. a catalog domain ("nike.com/checkout")
        merchant = catalog.merchant_by_domain(domain)
        if merchant:
            return CartMerchant(name=merchant.names[0], merchant_id=merchant.id), CONFIDENCE_MERCHANT_CATALOG
    scrubbed = NOT_A_STORE.sub(" ", text)  # 3. a catalog name inside the text, earliest first
    hits = []
    for merchant in catalog.CATALOG.merchants:
        for name in merchant.names:
            match = re.search(r"(?<![\w-])" + re.escape(name) + r"(?![\w-])", scrubbed, re.I)
            if match:
                hits.append((match.start(), -len(name), merchant))
    if hits:
        merchant = min(hits, key=lambda h: h[:2])[2]
        return CartMerchant(name=merchant.names[0], merchant_id=merchant.id), CONFIDENCE_MERCHANT_CATALOG
    for line in lines[:3]:  # 4. the page heading, for a store the catalog doesn't know
        if (re.search(r"[A-Za-z]{2}", line) and len(line) <= 40 and not MONEY.search(line)
                and not HEADING_SKIP.match(line) and "[" not in line):
            return CartMerchant(name=_clean_name(line), merchant_id=None), CONFIDENCE_MERCHANT_HEADING
    return CartMerchant(name=None, merchant_id=None), 0.0


def category_for(name: str, merchant_category: str | None) -> str:
    for category, pattern in _CATEGORY_PATTERNS:
        if pattern.search(name):
            return category
    return merchant_category or "general"


def _condition_of(line: str) -> str | None:
    if len(line) > 40:
        return None
    if COND_RENEWED.match(line):
        return "renewed"
    if COND_USED.match(line):
        return "used"
    if COND_NEW.match(line):
        return "new"
    return None


def _is_attribute(line: str) -> bool:
    return bool(_condition_of(line) or QTY.match(line) or SOLD_BY.match(line))


def _items(lines: list[str], end: int, merchant: CartMerchant) -> list[Item]:
    merchant_category = None
    if merchant.merchant_id:
        merchant_category = catalog.merchant(merchant.merchant_id).category
    items: list[Item] = []
    index = 0
    while index < end:
        line = lines[index]
        amounts = list(MONEY.finditer(line))
        name = _clean_name(line[: amounts[0].start()]) if amounts else ""
        if not amounts or NON_ITEM_LINE.match(line) or TOTAL_LINE.match(line) or len(re.findall(r"[A-Za-z]", name)) < 2:
            index += 1
            continue
        line_amount = _money(amounts[-1])
        index += 1
        condition = None
        inline = COND_INLINE.search(name)
        if inline:
            condition = _condition_of(inline.group(1))
            name = _clean_name(name[: inline.start()])
        # "Wireless Earbuds,  $249.00" + "Noise-Cancelling": a trailing comma continues the name.
        if name.endswith(",") and index < end:
            follow = lines[index]
            if not (MONEY.search(follow) or STOP_LINE.match(follow) or _is_attribute(follow) or TOTAL_LINE.match(follow)):
                name = _clean_name(f"{name} {follow}")
                index += 1
        name = name.rstrip(",").strip()
        quantity, seller = 1, "merchant"
        for follow in lines[index: min(end, index + 4)]:
            if MONEY.search(follow) or STOP_LINE.match(follow) or TOTAL_LINE.match(follow):
                break
            condition = condition or _condition_of(follow)
            if qty := QTY.match(follow):
                quantity = max(1, int(qty.group(1)))
            if sold := SOLD_BY.match(follow):
                seller_name = sold.group(1).strip().casefold()
                seller = "merchant" if merchant.name and seller_name == merchant.name.casefold() else "third_party"
        category = category_for(name, merchant_category)
        unit_price = (line_amount / quantity).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        items.append(Item(
            name=name, price_usd=float(unit_price), quantity=quantity, category=category,
            # No condition on the page: retail default is new (a renewed or used listing says so).
            condition=condition or "new", seller=seller,
            is_gift_card=category == "gift_card", is_service_plan=category == "services"))
    return items


def _payment(lines: list[str], text: str, confirmation: bool) -> tuple[list[str], SelectedPayment, bool]:
    bnpl = bool(BNPL.search(text))
    saved_network = None
    paid_network = None
    card_form = False
    for line in lines:
        if CARD_FORM.search(line):
            card_form = True
            continue
        if CARD_ON_FILE.search(line) and (NETWORK.search(line) or PAY_CONTEXT.search(line)):
            network = NETWORK.search(line)
            net = NETWORK_IDS[" ".join(network.group(1).lower().split())] if network else "unknown"
            if re.search(r"\bpaid with\b", line, re.I):
                paid_network = paid_network or net
            else:
                saved_network = saved_network or net
    if confirmation:
        if paid_network or saved_network:
            return [], SelectedPayment(kind="saved_card", network=paid_network or saved_network), False
        return [], SelectedPayment(kind="unknown", network="unknown"), False
    options = []
    if APPLE_PAY.search(text):
        options.append("apple_pay")
    if saved_network:
        options.append("saved_card")
    if card_form:
        options.append("card_form")
    if bnpl:
        options.append("bnpl")
    if PAYPAL.search(text):
        options.append("paypal")
    if OTHER_WALLET.search(text):
        options.append("other")
    if saved_network:
        selected = SelectedPayment(kind="saved_card", network=saved_network)
    elif card_form:
        selected = SelectedPayment(kind="card_form", network="unknown")
    elif "apple_pay" in options:
        selected = SelectedPayment(kind="apple_pay", network="unknown")
    else:
        selected = SelectedPayment(kind="unknown", network="unknown")
    return options, selected, bnpl


# --- Entry point --------------------------------------------------------------------------------


def parse(ocr_text: str) -> ParsedScreen:
    lines = _lines(ocr_text)
    if not lines:
        return ParsedScreen(screen_type="unreadable", cart=None)
    text = "\n".join(lines)
    total_index, total = _total(lines)
    if CONFIRMATION.search(text) and not PLACE_ORDER.search(text):
        screen_type = "order_confirmation"
    elif total is None:
        return ParsedScreen(screen_type="not_checkout" if readable(text) else "unreadable", cart=None)
    else:
        screen_type = "checkout"

    merchant, merchant_confidence = _merchant(lines, text)
    items = _items(lines, total_index if total_index is not None else len(lines), merchant)
    options, selected, bnpl = _payment(lines, text, screen_type == "order_confirmation")

    items_confidence = CONFIDENCE_ITEMS if items else 0.0
    if items and total is not None:
        items_sum = sum((Decimal(str(i.price_usd)) * i.quantity for i in items), Decimal("0"))
        if not (total * Decimal("0.5") <= items_sum <= total * Decimal("1.5")):
            items_confidence = CONFIDENCE_ITEMS_DOUBTFUL
    cart = Cart(
        merchant=merchant, items=items, total_usd=None if total is None else float(total), currency="USD",
        payment_options_visible=options, selected_payment=selected, upsells=Upsells(protection_plan_usd=None),
        bnpl_visible=bnpl,
        confidence=CartConfidence(merchant=merchant_confidence, total=CONFIDENCE_TOTAL if total is not None else 0.0,
                                  items=items_confidence))
    return ParsedScreen(screen_type=screen_type, cart=cart)
