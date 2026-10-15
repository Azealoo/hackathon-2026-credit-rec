"""Engine thresholds (SPEC.md §7.2). Policy, not card data: card rates and benefits live only in
data/cards.json (read through app/catalog.py)."""

from decimal import Decimal

# An item must cost at least this much for a protection switch (§7.2 rule 3).
PROTECTION_MIN_ITEM_USD = Decimal("100")

# Smallest cash gain over the default that is worth a switch, by payment path (§7.2 rule 6).
CASH_SWITCH_MIN_USD: dict[str, Decimal] = {
    "apple_pay": Decimal("3"),
    "saved_card": Decimal("5"),
    "card_form": Decimal("5"),
    "unknown": Decimal("5"),
}

# Below this item confidence the items count as unreadable (§7.2 rule 2).
ITEM_CONFIDENCE_MIN = 0.8

# Maker's warranty assumed when the screen doesn't say (§5.5 "Don't know" uses 12 months).
ASSUMED_MANUFACTURER_WARRANTY_MONTHS = 12
