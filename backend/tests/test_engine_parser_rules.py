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
