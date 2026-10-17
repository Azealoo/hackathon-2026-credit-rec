"""§6.3 copy for every state the backend decides (SPEC.md §6.2, §6.3).

The phone fills `{last4:<cardId>}` from its wallet and drops "••{…}" when it has no last 4.
`{ppCap}` is filled here from the protection's verified limit; an unverified limit drops the
amount ("Adds a warranty year + theft cover", §6.3 and the §8.2 display rule).

§8.2 display rule, applied by the engine through the keyword arguments below:
- `show_cap=False` when the decision's confidence is "medium" (it leans on a partial or unverified
  value): line 2 drops the cap even when the cap itself is verified.
- `cash_verified=False` (`verified=False` for Keep, method) when a rate behind a cash figure isn't
  verified: the line keeps the comparison but states no dollar amount or rate ("Likely less cash
  back than Active Cash"), since a partial value is never stated as fact (§15.8).
- `verified=False` for Keep, default best and Keep, under threshold when any wallet card's rate
  isn't verified, since both compare every card: "Likely best of your 3 cards here".

Card names (`shortName`) and networks come from data/cards.json through the Card objects the
engine passes in; nothing here holds card data. §6.2 lengths: lines 2 and 3 are at most 44
characters and the instruction at most 48, measured with the last 4 filled in.
"""

import re
from decimal import Decimal

from app.catalog import Card, Protection
from app.models import Copy, ErrorCode

CHECK = "✓"  # ✓
DOTS = "••"  # ••

LINE_MAX = 44
INSTRUCTION_MAX = 48

NETWORK_NAMES = {"visa": "Visa", "mastercard": "Mastercard", "discover": "Discover", "amex": "Amex"}

_PLACEHOLDER = re.compile(r"\{last4:[a-z0-9-]+\}")


def last4(card: Card) -> str:
    """The placeholder the phone replaces with this card's last 4."""
    return f"{{last4:{card.id}}}"


def filled_length(text: str) -> int:
    """Length once the phone has put a 4-digit last 4 into every placeholder."""
    return len(_PLACEHOLDER.sub("0000", text))


def usd(amount: Decimal, *, cents: bool = False) -> str:
    """$7.49, $1,499.00 (cents=True, for cash amounts); $500, $5 for whole-dollar caps and thresholds."""
    if cents or amount != amount.to_integral_value():
        return f"${amount:,.2f}"
    return f"${int(amount):,}"


def pct(rate: Decimal) -> str:
    """3 -> "3%", 1.5 -> "1.5%"."""
    return f"{format(rate.normalize(), 'f')}%"


def network(card: Card) -> str:
    return NETWORK_NAMES.get(card.network, card.network.title())


# --- Protection line ("Adds a warranty year + $500 theft cover") ----------------------------


def verified_cap(protection: Protection) -> Decimal | None:
    """The per-item (or per-claim) limit, only when the protection is verified (§8.2)."""
    if protection.verification.status != "verified":
        return None
    limits = protection.limits
    if limits.applies_to == "claim":
        return limits.per_claim_usd
    return limits.per_item_usd if limits.per_item_usd is not None else limits.per_claim_usd


def _warranty_phrase(ew: Protection) -> str:
    months = ew.extends_by_months
    if ew.verification.status != "verified" or not months:
        return "extra warranty"
    if months == 12:
        return "a warranty year"
    if months % 12 == 0:
        return f"{months // 12} warranty years"
    return f"{months} warranty months"


def protection_line(protections: list[Protection], *, show_cap: bool = True) -> str:
    """Line 2 for a protection switch and for Keep, protected (§6.3). `show_cap=False` (a medium-
    confidence decision, §8.2) drops the cap as an unverified one does."""
    ew = next((p for p in protections if p.type == "extended_warranty"), None)
    pp = next((p for p in protections if p.type == "purchase_protection"), None)
    cap = verified_cap(pp) if pp and show_cap else None
    if ew and pp:
        theft = f"{usd(cap)} theft cover" if cap is not None else "theft cover"
        return f"Adds {_warranty_phrase(ew)} + {theft}"
    if pp:  # Ruling: purchase protection alone names both perils it covers.
        return f"Adds {usd(cap)} theft & damage cover" if cap is not None else "Adds theft & damage cover"
    if ew:
        return f"Adds {_warranty_phrase(ew)}"
    return "Adds card protection"


# --- Instructions -----------------------------------------------------------------------------


def instruction_text(card: Card, path: str) -> str:
    """How to pay with the picked card on this checkout (§5.3)."""
    net, l4 = network(card), last4(card)
    if path == "apple_pay":
        options = ["In Apple Pay, swipe to this card"]
    elif path == "saved_card":
        options = [f"Change card to {net} {DOTS}{l4}, then place order",
                   f"Switch to {net} {DOTS}{l4}, then place order",
                   f"Change card to {net} {DOTS}{l4}"]
    elif path == "card_form":  # Ruling: a card-number form needs the card typed in.
        options = [f"Enter your {net} {DOTS}{l4}, then place order",
                   f"Enter your {net} {DOTS}{l4}, then pay"]
    else:  # unknown: no payment control read on screen
        options = [f"Pay with your {net} {DOTS}{l4} instead", f"Pay with {net} {DOTS}{l4}"]
    return next((text for text in options if filled_length(text) <= INSTRUCTION_MAX), options[-1])


# --- States -----------------------------------------------------------------------------------


def _copy(line1: str, line2: str | None = None, line3: str | None = None,
          instruction: str | None = None, primary_button: str | None = None) -> Copy:
    return Copy(line1=line1, line2=line2, line3=line3, instruction=instruction, primary_button=primary_button)


def paying_with(card: Card) -> str:
    return f"Paying with {card.short_name}"


def switch_protection(card: Card, gained: list[Protection], delta_vs_cash_best: Decimal,
                      cash_best: Card, path: str, *, show_cap: bool = True, cash_verified: bool = True) -> Copy:
    """Switch, protection (Rule P). Line 3 compares with the wallet's cash-best card (§6.2)."""
    if delta_vs_cash_best >= 0:
        line3 = "Also earns the most cash back here" if cash_verified else "Likely also earns the most cash back here"
    elif cash_verified:
        line3 = f"{usd(-delta_vs_cash_best, cents=True)} less cash back than {cash_best.short_name}"
    else:
        line3 = f"Likely less cash back than {cash_best.short_name}"
    return _copy(f"Use {card.short_name} {DOTS}{last4(card)}", protection_line(gained, show_cap=show_cap), line3,
                 instruction_text(card, path), paying_with(card))


def switch_cash(card: Card, gain_vs_default: Decimal, default: Card, notes: list[str], path: str,
                *, cash_verified: bool = True) -> Copy:
    """Switch, cash (Rule C), with the first eligibility note as line 3."""
    line3 = next((note for note in notes if len(note) <= LINE_MAX), None)
    if cash_verified:
        line2 = f"{usd(gain_vs_default, cents=True)} more cash back than {default.short_name}"
    else:
        line2 = f"Likely more cash back than {default.short_name}"
    return _copy(f"Use {card.short_name} {DOTS}{last4(card)}", line2, line3,
                 instruction_text(card, path), paying_with(card))


def keep_protected(card: Card, kept: list[Protection], *, show_cap: bool = True) -> Copy:
    return _copy(f"{CHECK} Keep {card.short_name} {DOTS}{last4(card)}", protection_line(kept, show_cap=show_cap),
                 "Save it so you can claim later", None, paying_with(card))


def keep_default_best(card: Card, wallet_size: int, *, verified: bool = True) -> Copy:
    """`verified=False` when any wallet card's rate here isn't verified: "best of" compares them all."""
    if wallet_size <= 1:
        line2 = "Your only card here"
    else:
        best = "Best" if verified else "Likely best"
        line2 = f"{best} of your {wallet_size} cards here"
    return _copy(f"{CHECK} Keep {card.short_name} {DOTS}{last4(card)}", line2)


def keep_below_threshold(card: Card, threshold: Decimal, *, verified: bool = True) -> Copy:
    gains = "gains" if verified else "likely gains"
    return _copy(f"{CHECK} Keep {card.short_name} {DOTS}{last4(card)}",
                 f"Switching {gains} under {usd(threshold)} here")


def keep_method(card: Card, apple_pay_rate: Decimal, apple_pay_cash: Decimal, typed_rate: Decimal,
                *, verified: bool = True) -> Copy:
    line2 = (f"{pct(apple_pay_rate)} ({usd(apple_pay_cash, cents=True)}) with Apple Pay vs {pct(typed_rate)} typed"
             if verified else "Likely more cash back with Apple Pay")
    return _copy(f"{CHECK} {card.short_name}: use Apple Pay", line2)


def keep_items_unreadable(card: Card) -> Copy:
    return _copy(f"{CHECK} Keep {card.short_name} {DOTS}{last4(card)}", "Couldn't read the items, so no switch")


def no_checkout(reason: str) -> Copy:
    if reason == "already_paid":
        return _copy("Already paid?", "Press on the checkout, before you pay")
    return _copy("No checkout total found", "Scroll to the total and press again")


ERROR_LINE2: dict[str, str] = {
    "timeout": "Took too long · press again",
    "privacy_rejected": "Card number found, so nothing was read",
}


def error(code: ErrorCode) -> Copy:
    """Couldn't check (§6.3). The phone shows its own "No connection" copy when the request never lands."""
    return _copy("Couldn't check this time", ERROR_LINE2.get(code, "Something went wrong · press again"))
