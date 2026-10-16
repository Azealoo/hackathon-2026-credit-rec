"""Writes the 8 harder parser fixtures (fixtures/ocr-hard, fixtures/carts-hard) for the on-device parser test.

All screens are fictional and obviously fake: redaction markers stand in for card numbers, names and
addresses. They were written before any parser ran on them, so no parser was tuned to them.

    cd backend && uv run python scripts/make_hard_fixtures.py
"""

import json
from decimal import Decimal
from pathlib import Path

FIXTURES = Path(__file__).resolve().parents[2] / "fixtures"
NOTE = "Fictional screen text made for a hackathon parser test. No real order, person or card."


def cart(screen, merchant_name, merchant_id, items, total, options, kind, network, plan=None, bnpl=False):
    blank = screen in ("not_checkout", "unreadable")
    return {
        "screenType": screen,
        "merchant": {"name": merchant_name, "merchantId": merchant_id},
        "items": [
            {"name": n, "priceUsd": p, "quantity": q, "category": c, "condition": cond, "seller": s,
             "isGiftCard": c == "gift_card", "isServicePlan": c == "services"}
            for n, p, q, c, cond, s in items
        ],
        "totalUsd": total,
        "currency": "USD",
        "paymentOptionsVisible": options,
        "selectedPayment": {"kind": kind, "network": network},
        "upsells": {"protectionPlanUsd": plan},
        "bnplVisible": bnpl,
        "confidence": {"merchant": 0.0, "total": 0.0, "items": 0.0} if blank
        else {"merchant": 0.95, "total": 0.95, "items": 0.9},
    }


CASES = {
    "bestbuy-tv-plan-offer": ("""BEST BUY
Checkout
Lumina 65-inch 4K Smart TV  $899.99
New
Qty 1
Add 3-Year Protection Plan  $149.99
Add
Pickup at
[ADDRESS]
Payment
Visa [CARD]  Change
Or pay with
Apple Pay
As low as $75.00/mo with Affirm
Subtotal  $899.99
Estimated tax  $91.80
Total  $991.79
Place Your Order""", cart(
        "checkout", "Best Buy", "best-buy",
        [("Lumina 65-inch 4K Smart TV", 899.99, 1, "electronics", "new", "merchant")],
        991.79, ["saved_card", "apple_pay", "bnpl"], "saved_card", "visa", plan=149.99, bnpl=True)),
    "amazon-two-items-third-party": ("""amazon.com
Review your order
Delivering to [NAME]
[ADDRESS]
Paying with Visa ending in [CARD]  Change
Arriving Oct 20
USB-C Charging Cable, 6 ft
$12.99
Qty: 2
Sold by: Amazon.com
SoundBox Mini Bluetooth Speaker (Renewed)
$94.99
Qty: 1
Sold by: ReadMore Outlet
Items:  $120.97
Shipping & handling:  $0.00
Estimated tax to be collected:  $12.10
Order total:  $133.07
Place your order""", cart(
        "checkout", "Amazon", "amazon",
        [("USB-C Charging Cable, 6 ft", 12.99, 2, "electronics", "new", "merchant"),
         ("SoundBox Mini Bluetooth Speaker", 94.99, 1, "audio", "renewed", "third_party")],
        133.07, ["saved_card"], "saved_card", "visa")),
    "target-card-form-applepay": ("""Target
Checkout
Order summary
Stoneware Dinner Plates, Set of 4  $24.00
Qty 1
Cotton Bath Towel  $8.00
Qty 3
Subtotal (4 items)  $48.00
Estimated tax  $4.32
Total  $52.32
Payment
Apple Pay
Credit or debit card
Card number  [CARD]
Expiration  [CARD]
CVV  [CARD]
Name on card  [NAME]
Place your order""", cart(
        "checkout", "Target", "target",
        [("Stoneware Dinner Plates, Set of 4", 24.00, 1, "home", "new", "merchant"),
         ("Cotton Bath Towel", 8.00, 3, "home", "new", "merchant")],
        52.32, ["apple_pay", "card_form"], "card_form", "unknown")),
    "doordash-line-totals": ("""DoorDash
Checkout
Spice Route Kitchen
Chicken Tikka Masala  $16.50
1x
Garlic Naan  $7.00
2x
Subtotal  $23.50
Delivery Fee  $2.99
Service Fee  $3.53
Estimated Tax  $2.12
Dasher Tip  $5.00
Total  $37.14
Payment
Amex [CARD]
Apple Pay
Place Order""", cart(
        "checkout", "DoorDash", "doordash",
        [("Chicken Tikka Masala", 16.50, 1, "dining", "new", "merchant"),
         ("Garlic Naan", 3.50, 2, "dining", "new", "merchant")],
        37.14, ["saved_card", "apple_pay"], "saved_card", "amex")),
    "unknown-store-open-box-bike": ("""Ridgeline Cycle Co.
Secure checkout
Trail 29er Mountain Bike, Medium  $1,150.00
Open box
Qty 1
Subtotal  $1,150.00
Shipping  $45.00
Sales tax  $103.50
Total  $1,298.50
Express checkout
PayPal
Pay in 4 interest-free installments with Klarna
Card number
MM / YY
Security code
Pay now""", cart(
        "checkout", "Ridgeline Cycle Co.", None,
        [("Trail 29er Mountain Bike, Medium", 1150.00, 1, "bikes", "used", "merchant")],
        1298.50, ["paypal", "bnpl", "card_form"], "card_form", "unknown", bnpl=True)),
    "walmart-gift-card-blender": ("""Walmart
Review order
Walmart eGift Card  $50.00
Delivered by email
Qty 1
6-Speed Countertop Blender  $39.88
Qty 1
Subtotal  $89.88
Estimated taxes  $3.19
Total  $93.07
Payment method
Discover [CARD]  Change
Place order""", cart(
        "checkout", "Walmart", "walmart",
        [("Walmart eGift Card", 50.00, 1, "gift_card", "new", "merchant"),
         ("6-Speed Countertop Blender", 39.88, 1, "appliances", "new", "merchant")],
        93.07, ["saved_card"], "saved_card", "discover")),
    "nike-order-confirmation": ("""Nike
Thanks for your order
Order number  C00198765
Pegasus Running Shoes, Men's Size 10  $140.00
Qty 1
Subtotal  $140.00
Shipping  Free
Tax  $12.25
Total  $152.25
Paid with Apple Pay
Shipping to [ADDRESS]""", cart(
        "order_confirmation", "Nike", "nike",
        [("Pegasus Running Shoes, Men's Size 10", 140.00, 1, "apparel", "new", "merchant")],
        152.25, [], "apple_pay", "unknown")),
    "bestbuy-product-page": ("""BEST BUY
Lumina 65-inch 4K Smart TV
Model: LM65QX  SKU: 6500123
4.6 (2,314 reviews)
$899.99
Was $1,099.99
Save $200
Pickup today at [ADDRESS]
Add to Cart
Get it with 3-Year Protection  $149.99
Pay as low as $75.00/mo with Affirm""", cart(
        "not_checkout", None, None, [], None, [], "unknown", "unknown")),
}


def main() -> None:
    (FIXTURES / "ocr-hard").mkdir(exist_ok=True)
    (FIXTURES / "carts-hard").mkdir(exist_ok=True)
    for stem, (text, expected) in CASES.items():
        (FIXTURES / "ocr-hard" / f"{stem}.txt").write_text(text + "\n", encoding="utf-8")
        (FIXTURES / "carts-hard" / f"{stem}.json").write_text(json.dumps(expected, indent=2) + "\n", encoding="utf-8")
        items_sum = sum(Decimal(str(i["priceUsd"])) * i["quantity"] for i in expected["items"])
        print(f"{stem:32} items_sum={items_sum} total={expected['totalUsd']}")
    (FIXTURES / "ocr-hard" / "README.md").write_text(
        f"# Harder parser fixtures\n\n{NOTE} Written for the on-device parser feasibility test before any parser "
        "ran on them. Expected carts are in `../carts-hard/`. Made by `backend/scripts/make_hard_fixtures.py`.\n",
        encoding="utf-8")


if __name__ == "__main__":
    main()
