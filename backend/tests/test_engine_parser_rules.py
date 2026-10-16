"""app/parser_rules.py: the 7 OCR fixtures reproduce fixtures/carts/*.json, plus simple generic checkouts."""

import json
from pathlib import Path

import pytest

from app import parser_rules

REPO = Path(__file__).resolve().parents[2]
FIXTURES = REPO / "fixtures"
NAMES = sorted(p.stem for p in (FIXTURES / "ocr").glob("*.txt"))
EMPTY_CART = {"merchant": {"name": None, "merchantId": None}, "items": [], "totalUsd": None,
              "paymentOptionsVisible": [], "selectedPayment": {"kind": "unknown", "network": "unknown"}}
ITEM_FIELDS = ("name", "priceUsd", "quantity", "category", "condition", "seller", "isGiftCard", "isServicePlan")


def parsed_fields(parsed) -> dict:
    """The compared fields; a None cart (not a checkout / unreadable) reads as the empty cart."""
    if parsed.cart is None:
        return {"screenType": parsed.screen_type, **EMPTY_CART}
    cart = parsed.cart.model_dump(mode="json", by_alias=True)
    return {"screenType": parsed.screen_type, "merchant": cart["merchant"],
            "items": [{k: item[k] for k in ITEM_FIELDS} for item in cart["items"]],
            "totalUsd": cart["totalUsd"], "paymentOptionsVisible": cart["paymentOptionsVisible"],
            "selectedPayment": cart["selectedPayment"]}


def expected_fields(name: str) -> dict:
    cart = json.loads((FIXTURES / "carts" / f"{name}.json").read_text(encoding="utf-8"))
    return {"screenType": cart["screenType"], "merchant": cart["merchant"],
            "items": [{k: item[k] for k in ITEM_FIELDS} for item in cart["items"]],
            "totalUsd": cart["totalUsd"], "paymentOptionsVisible": cart["paymentOptionsVisible"],
            "selectedPayment": cart["selectedPayment"]}


def parse(text: str):
    return parser_rules.parse(text)


def test_there_are_7_ocr_fixtures():
    assert len(NAMES) == 7


@pytest.mark.parametrize("name", NAMES)
def test_ocr_fixture_reproduces_its_cart(name):
    text = (FIXTURES / "ocr" / f"{name}.txt").read_text(encoding="utf-8")
    assert parsed_fields(parse(text)) == expected_fields(name)


@pytest.mark.parametrize("name", NAMES)
def test_parse_is_deterministic(name):
    text = (FIXTURES / "ocr" / f"{name}.txt").read_text(encoding="utf-8")
    assert parse(text) == parse(text)


def test_spec_request_example_text():
    """§15.5's example ocrText: condition inline as "(New)"."""
    text = ("Northbay Electronics\nCheckout\nAero 14 Laptop, 14-inch (New)  $1,499.00\nTotal  $1,499.00\n"
            "Pay with Mastercard [CARD]\nChange\nShip to [ADDRESS]\nPlace order")
    assert parsed_fields(parse(text)) == expected_fields("laptop-checkout")


def test_generic_checkout_with_apple_pay_and_a_card_form():
    text = ("Nike\nBag\nRunning Shoes  $180.00\nSize 10\nSubtotal  $180.00\nShipping  Free\nTotal  $180.00\n"
            "Apple Pay\nOr pay with card\nCard number [CARD]\nExpiration MM/YY\nSecurity code\nPlace order")
    parsed = parse(text)
    assert parsed.screen_type == "checkout"
    cart = parsed.cart
    assert (cart.merchant.name, cart.merchant.merchant_id) == ("Nike", "nike")
    assert [(i.name, i.price_usd, i.category, i.condition) for i in cart.items] == [
        ("Running Shoes", 180.0, "apparel", "new")]
    assert cart.total_usd == 180.0
    assert cart.payment_options_visible == ["apple_pay", "card_form"]
    assert cart.selected_payment.kind == "card_form"


def test_apple_pay_button_does_not_make_the_store_apple():
    text = "Best Buy\nCheckout\nStudio Headphones  $120.00\nTotal  $120.00\nBuy with Apple Pay"
    cart = parse(text).cart
    assert cart.merchant.merchant_id == "best-buy"
    assert cart.items[0].category == "audio"
    assert cart.payment_options_visible == ["apple_pay"]


def test_domain_names_the_merchant():
    cart = parse("Secure checkout\nwalgreens.com\nMultivitamin, 200 ct  $40.00\nTotal  $40.00").cart
    assert cart.merchant.merchant_id == "walgreens"
    assert cart.items[0].category == "pharmacy"


def test_unknown_store_keeps_its_heading_without_an_id():
    cart = parse("Corner Gadget Shop\nCheckout\nDrone Mini 2  $299.00\nTotal  $299.00").cart
    assert cart.merchant.name == "Corner Gadget Shop" and cart.merchant.merchant_id is None
    assert cart.confidence.merchant < 0.8
    assert cart.items[0].category == "electronics"


@pytest.mark.parametrize(
    "text, store",
    [
        ("Gadget Hut\nCheckout\nApple MacBook Air 13-inch  $999.00\nNew\nQty 1\nPay with  Visa [CARD]  Change\n"
         "Total  $999.00\nPlace order", "Gadget Hut"),
        ("Foot Locker\nCheckout\nNike Air Max 90 Sneakers  $300.00\nQty 1\nApple Pay\nTotal  $300.00\nPlace order",
         "Foot Locker"),
        ("Corner Market\nCheckout\nHoneycrisp Apple Gift Box  $60.00\nTotal  $60.00\nPlace order", "Corner Market"),
    ],
)
def test_a_brand_in_an_item_name_is_not_the_store(text, store):
    """BE-1: a catalog name on an item line (Apple, Nike) doesn't make an unknown store that brand's store."""
    cart = parse(text).cart
    assert (cart.merchant.name, cart.merchant.merchant_id) == (store, None)
    assert cart.confidence.merchant < 0.8


def test_a_store_without_a_heading_is_unknown_not_the_item_brand():
    """BE-1: no store line above the items; "Sold by Best Buy" and the item's brand don't name the store."""
    cart = parse("Checkout\nApple MacBook Air 13-inch  $999.00\nNew\nSold by Best Buy\nTotal  $999.00\n"
                 "Place order").cart
    assert (cart.merchant.name, cart.merchant.merchant_id) == (None, None)


def test_a_catalog_name_in_the_heading_still_names_the_store():
    cart = parse("Welcome back to Best Buy\nCheckout\nApple MacBook Air 13-inch  $999.00\nTotal  $999.00").cart
    assert cart.merchant.merchant_id == "best-buy"


@pytest.mark.parametrize(
    "line, condition",
    [("New", "new"), ("Renewed · no warranty", "renewed"), ("Refurbished", "renewed"), ("Used - Good", "used"),
     ("Pre-owned", "used")],
)
def test_condition_lines(line, condition):
    cart = parse(f"Northbay Electronics\nAero 14 Laptop, 14-inch  $999.00\n{line}\nQty 1\nTotal  $999.00").cart
    assert cart.items[0].condition == condition


def test_quantity_gives_a_unit_price():
    cart = parse("Northbay Electronics\nCeramic Coffee Mug, 12 oz  $36.00\nQty 2\nTotal  $36.00").cart
    assert (cart.items[0].quantity, cart.items[0].price_usd) == (2, 18.0)


@pytest.mark.parametrize(
    "tail",
    ["Total  $300.00",
     "Subtotal  $300.00\nEstimated tax  $30.60\nTotal  $330.60",
     "Shipping  $9.99\nTotal  $309.99"],
)
def test_a_unit_price_beside_qty_2_reads_as_the_unit_price(tail):
    """BE-3: "$150.00" + "Qty 2" with $300.00 of items is $150.00 each, not $75.00."""
    cart = parse(f"NORTHBAY Electronics\nCheckout\nWireless Earbuds  $150.00\nNew\nQty 2\n{tail}\nPlace order").cart
    assert (cart.items[0].quantity, cart.items[0].price_usd) == (2, 150.0)
    assert cart.confidence.items >= 0.8


def test_a_line_total_beside_qty_2_still_reads_as_the_line_total_with_a_subtotal():
    cart = parse("Northbay Electronics\nCeramic Coffee Mug, 12 oz  $36.00\nQty 2\nSubtotal  $36.00\n"
                 "Estimated tax  $3.67\nTotal  $39.67").cart
    assert (cart.items[0].quantity, cart.items[0].price_usd) == (2, 18.0)
    assert cart.confidence.items >= 0.8


def test_qty_2_that_fits_both_readings_is_doubtful():
    # The subtotal fits the line-total reading, the total fits the unit-price reading: the screen can't tell.
    cart = parse("Northbay Electronics\nWireless Earbuds  $150.00\nQty 2\nSubtotal  $150.00\nTotal  $300.00").cart
    assert cart.confidence.items < 0.8


def test_gift_cards_and_protection_plans_are_flagged():
    cart = parse("Northbay Electronics\nNorthbay eGift Card  $100.00\n2-Year Protection Plan  $149.00\n"
                 "Total  $249.00").cart
    assert [(i.category, i.is_gift_card, i.is_service_plan) for i in cart.items] == [
        ("gift_card", True, False), ("services", False, True)]


def test_subtotal_tax_and_shipping_are_not_items():
    cart = parse("Northbay Electronics\nAero 14 Laptop, 14-inch  $1,499.00\nSubtotal  $1,499.00\n"
                 "Shipping  $9.99\nEstimated tax  $151.40\nTotal  $1,660.39").cart
    assert [i.name for i in cart.items] == ["Aero 14 Laptop, 14-inch"]
    assert cart.total_usd == 1660.39


def test_bnpl_and_paypal_are_visible_options():
    cart = parse("Northbay Electronics\nAero 14 Laptop, 14-inch  $1,499.00\nTotal  $1,499.00\n"
                 "Pay in 4 with Afterpay\nPayPal").cart
    assert cart.bnpl_visible is True
    assert cart.payment_options_visible == ["bnpl", "paypal"]


def test_checkout_with_unreadable_items_has_low_item_confidence():
    cart = parse("Northbay Electronics\nCheckout\nTotal  $1,499.00\nPlace order").cart
    assert cart.items == [] and cart.confidence.items < 0.8


def test_items_far_from_the_total_are_doubtful():
    cart = parse("Northbay Electronics\nCeramic Coffee Mug, 12 oz  $18.00\nTotal  $1,499.00").cart
    assert cart.confidence.items < 0.8


@pytest.mark.parametrize("text", ["", "   \n\n", "8 3 1 . , ;"])
def test_empty_or_symbol_only_text_is_unreadable(text):
    assert parse(text).screen_type == "unreadable"


def test_page_without_a_total_is_not_a_checkout():
    assert parse("Your cart\nAero 14 Laptop, 14-inch  $1,499.00\nContinue to checkout").screen_type == "not_checkout"
