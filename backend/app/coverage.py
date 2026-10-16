"""Coverage verdicts for POST /v1/coverage (SPEC v2.1 §5.5, §7.3, §15.5, §15.7 step 12b).

The verdict comes from date and window rules in code. Card terms (windows, caps, covered causes,
notice days, claim contacts, clause citations) come only from data/cards.json via app.catalog.
Every date comes from the request: `asOf` is "today" for the verdict (the date override), so this
module never reads the clock.

The checks run in the §5.5 order:
  1. still under the maker's warranty (failures only, ruling R9) -> route "manufacturer";
  2. the card's extended warranty (failures only), from the maker's end date for
     `extendsByMonths`, never past `maxTotalFromPurchaseMonths` from purchase, and only when the
     maker's warranty is 1..`maxOriginalWarrantyMonths` months;
  3. purchase protection (theft, accidental damage; loss needs more info) within `windowDays`;
  4. not covered.

The LLM is used for one thing only: with COVERAGE_MODE=llm, a null `incident.cause` is classified
by app.llm.classify_cause (owned by the LLM track and imported lazily). It never touches dates or
money.

Every response echoes the cause it used in `incident` (ruling R17): {"cause", "causeSource"}, with
causeSource "llm" when the classifier filled a null cause. A null-cause request is therefore also a
classify call: the claim screen pre-selects the returned chip and the user confirms it (§5.5), even
when the verdict is need_more_info (cause loss, cosmetic or unknown).
"""

import asyncio
import calendar
import datetime as dt
import decimal
import inspect
import logging
import math
import os
import re
from decimal import Decimal

from app import catalog
from app.catalog import Card, Catalog, CardSource, Protection
from app.models import (
    Citation,
    Contact,
    CoverageLimit,
    CoverageRequest,
    CoverageResponse,
    Deadline,
    IncidentCause,
)

log = logging.getLogger(__name__)

DISCLAIMER = "Only the benefit administrator decides claims. Paywise never files for you."

CAUSES = ("failure", "accidental_damage", "theft", "loss", "cosmetic", "unknown")

# The cause chips the user sees (§5.5 input screen step 3), for copy.
CAUSE_LABELS = {
    "failure": "Stopped working",
    "accidental_damage": "Dropped or damaged",
    "theft": "Stolen",
    "loss": "Lost",
    "cosmetic": "Cosmetic damage",
    "unknown": "Not sure",
}

# The `covers[]` entry in data/cards.json that each incident cause needs.
COVER_FOR_CAUSE = {
    "failure": "failure",
    "accidental_damage": "accidental_damage",
    "theft": "theft",
    "loss": "involuntary_parting",
    "cosmetic": "accidental_damage",
}

BENEFIT_NAMES = {"purchase_protection": "Purchase protection", "extended_warranty": "Extended warranty"}
ROUTES = {"purchase_protection": "card_purchase_protection", "extended_warranty": "card_extended_warranty"}

# §5.5 checklists.
CHECKLIST_BASE = ["Itemized receipt", "Card statement showing the purchase"]
CHECKLIST_EW = [*CHECKLIST_BASE, "Original warranty", "Repair estimate"]
POLICE_REPORT = "Police report (made within 48 hours if you can)"
PORCH_THEFT = "Claim with the carrier or store first"
REPAIR_ESTIMATE = "Repair estimate"
PORCH_WORDS = re.compile(r"\b(porch|doorstep|front door|stoop|package|parcel|deliver(?:ed|y)?)\b", re.IGNORECASE)

# Every phone-side wait is bounded; app.llm has its own (shorter) client timeout.
CLASSIFY_TIMEOUT_S = 6.0

_MONTHS = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")


class CoverageInputError(ValueError):
    """The request is well-formed JSON but can't be assessed (unknown card, impossible dates)."""


# --- Formatting and date helpers (pure) ------------------------------------------------------


OUT_OF_RANGE = "A coverage date would fall after Dec 31, 9999: check purchaseDate and manufacturerWarrantyMonths."


def add_months(day: dt.date, months: int) -> dt.date:
    """Calendar months, clamped to the month's last day (Jan 31 + 1 month = Feb 28 or 29).

    A result past year 9999 raises CoverageInputError (a 400, not a server error)."""
    years, month0 = divmod(day.month - 1 + months, 12)
    year, month = day.year + years, month0 + 1
    if not dt.MINYEAR <= year <= dt.MAXYEAR:
        raise CoverageInputError(OUT_OF_RANGE)
    return dt.date(year, month, min(day.day, calendar.monthrange(year, month)[1]))


def add_days(day: dt.date, days: int) -> dt.date:
    """`day + days`; a result past year 9999 raises CoverageInputError."""
    try:
        return day + dt.timedelta(days=days)
    except OverflowError:
        raise CoverageInputError(OUT_OF_RANGE) from None


def fmt_date(day: dt.date) -> str:
    """'Oct 17, 2027' (locale-independent)."""
    return f"{_MONTHS[day.month - 1]} {day.day}, {day.year}"


def to_decimal(value) -> Decimal:
    return value if isinstance(value, Decimal) else Decimal(str(value))


# Enough digits to round any finite float to cents (the largest is ~1.8e308): the default
# 28-digit context raises InvalidOperation for amounts of 1e26 and up.
_CENTS = Decimal("0.01")
_MONEY_CONTEXT = decimal.Context(prec=400)


def to_cents(value) -> Decimal:
    return to_decimal(value).quantize(_CENTS, context=_MONEY_CONTEXT)


def fmt_usd(value) -> str:
    """'$1,499' for whole dollars, '$1,499.50' otherwise."""
    amount = to_cents(value)
    if amount == amount.to_integral_value(context=_MONEY_CONTEXT):
        return f"${int(amount):,}"
    return f"${amount:,.2f}"


def fmt_usd_cents(value) -> str:
    """'$1,499.00': always two decimals (purchase prices)."""
    return f"${to_cents(value):,.2f}"


def months_phrase(months: int, adjective: bool = False) -> str:
    """12 -> '1 year' / '1-year'; 18 -> '18 months' / '18-month'."""
    count, unit = (months // 12, "year") if months % 12 == 0 else (months, "month")
    if adjective:
        return f"{count}-{unit}"
    return f"{count} {unit}{'' if count == 1 else 's'}"


def extra_phrase(months: int) -> str:
    """The card's added warranty: 'extra year' for 12 months, else 'extra 6 months'."""
    return "extra year" if months == 12 else f"extra {months_phrase(months)}"


def card_name(card: Card) -> str:
    """The card's name without leading issuer words: 'Chase Freedom Unlimited' -> 'Freedom Unlimited'.

    Leading words of displayName that also appear in `issuer` are dropped, as long as at least one
    capitalised word is left ('Discover it Student Cash Back' stays whole).
    """
    words = card.display_name.split()
    issuer_words = set(re.findall(r"[A-Za-z]+", card.issuer or ""))
    i = 0
    while i < len(words) - 1 and words[i] in issuer_words:
        i += 1
    if i and words[i][:1].isupper():
        return " ".join(words[i:])
    return card.display_name


def pp_days_phrase(pp: Protection) -> str:
    """'120 days (90 in NY)' (§5.5 New York note: the engine doesn't know the user's state)."""
    phrase = f"{pp.window_days} days"
    if pp.window_days_by_state:
        phrase += " (" + ", ".join(f"{days} in {state}" for state, days in sorted(pp.window_days_by_state.items())) + ")"
    return phrase


# --- Windows ---------------------------------------------------------------------------------


class Windows:
    """Every coverage window for one purchase, computed from the request and cards.json only."""

    def __init__(self, purchase_date: dt.date, maker_months: int, pp: Protection | None, ew: Protection | None):
        self.purchase_date = purchase_date
        self.maker_months = maker_months
        self.maker_end = add_months(purchase_date, maker_months) if maker_months > 0 else None

        self.pp_end = add_days(purchase_date, pp.window_days) if pp and pp.window_days else None

        # Why the card's extended warranty can't run for this purchase (None when it can).
        self.ew_block: str | None = None
        self.ew_end: dt.date | None = None
        if ew is None:
            self.ew_block = "none_on_card"
        elif self.maker_end is None:
            self.ew_block = "no_maker_warranty"
        elif ew.max_original_warranty_months is not None and maker_months > ew.max_original_warranty_months:
            self.ew_block = "maker_too_long"
        elif not ew.extends_by_months:
            self.ew_block = "none_on_card"
        else:
            end = add_months(self.maker_end, ew.extends_by_months)
            if ew.max_total_from_purchase_months is not None:
                end = min(end, add_months(purchase_date, ew.max_total_from_purchase_months))
            if end <= self.maker_end:
                self.ew_block = "maker_too_long"
            else:
                self.ew_end = end

    def under_maker(self, day: dt.date) -> bool:
        return self.maker_end is not None and day <= self.maker_end

    def in_ew(self, day: dt.date) -> bool:
        return self.ew_end is not None and self.maker_end < day <= self.ew_end

    def in_pp(self, day: dt.date) -> bool:
        return self.pp_end is not None and day <= self.pp_end


# --- Assessment ------------------------------------------------------------------------------


class _Assessment:
    """One request being assessed: the card, its windows, and the assumptions collected so far."""

    def __init__(self, req: CoverageRequest, cards: Catalog, classifier_failed: bool):
        self.req = req
        self.purchase = req.purchase
        self.incident = req.incident
        self.as_of = req.as_of
        self.classifier_failed = classifier_failed
        try:
            self.card = cards.card(self.purchase.card_id)
        except KeyError:
            raise CoverageInputError("unknown cardId") from None
        try:
            cards.item_category(self.purchase.category)
        except KeyError:
            raise CoverageInputError("unknown category") from None
        if self.incident.date < self.purchase.purchase_date:
            raise CoverageInputError("incident.date is before purchase.purchaseDate")
        if self.incident.date > self.as_of:
            raise CoverageInputError("incident.date is after asOf")
        # JSON can carry 1e400, which parses as infinity and passes `ge=0`.
        for name, amount in (("priceUsd", self.purchase.price_usd), ("amountOnCardUsd", self.purchase.amount_on_card_usd)):
            if amount is not None and not math.isfinite(amount):
                raise CoverageInputError(f"purchase.{name} must be a finite number")

        self.name = card_name(self.card)
        self.pp = self.card.protection("purchase_protection")
        self.ew = self.card.protection("extended_warranty")
        self.cpp = self.card.protection("cell_phone_protection")
        self.assumptions: list[str] = []

        maker_months = self.purchase.manufacturer_warranty_months
        if maker_months is None:
            self.assume("No maker's warranty length was given, so Paywise treats it as none.")
            maker_months = 0
        elif self.purchase.manufacturer_warranty_source == "assumed":
            self.assume(f"Assumes a {months_phrase(maker_months, adjective=True)} maker's warranty (you chose Don't know).")
        self.w = Windows(self.purchase.purchase_date, maker_months, self.pp, self.ew)

        if self.purchase.status == "planned":
            self.assume(f"Assumes you paid with {self.name}: the purchase isn't confirmed yet.")
        if self.incident.cause is not None and self.incident.cause_source == "llm":
            label = CAUSE_LABELS[self.incident.cause]
            self.assume(f"Paywise read the cause as “{label}” from your description. If that's wrong, pick what happened.")

    def assume(self, text: str) -> None:
        if text not in self.assumptions:
            self.assumptions.append(text)

    # --- Citations, deadlines, money ---------------------------------------------------------

    @staticmethod
    def cite(protection: Protection) -> Citation:
        source = protection.source
        return Citation(
            document=source.document or "Card terms",
            section=source.section,
            version_date=source.version_date,
            quote=source.quote,
            verification=protection.verification.status,
        )

    def cite_absence(self) -> Citation:
        """For a card without the benefit: the dated card source that covers the whole document."""
        sources: tuple[CardSource, ...] = self.card.sources
        whole = [s for s in sources if (s.section or "").casefold().startswith("whole")]
        dated = [s for s in whole if s.version_date is not None]
        chosen = (dated or whole or list(sources) or [None])[0]
        if chosen is None:
            return Citation(document=f"{self.card.display_name} terms", section=None, version_date=None,
                            quote=None, verification="unverified")
        return Citation(
            document=chosen.document or f"{self.card.display_name} terms",
            section=chosen.section,
            version_date=chosen.version_date,
            quote=chosen.quote,
            verification="verified" if chosen.version_date is not None else "partial",
        )

    def charged_usd(self) -> Decimal:
        """The amount charged to the card: the part paid on it for card_partial, else the price."""
        price = to_decimal(self.purchase.price_usd)
        if self.purchase.paid_with == "card_partial":
            if self.purchase.amount_on_card_usd is None:
                self.assume("You paid part of the price on the card; the payout is at most that part.")
                return price
            return min(price, to_decimal(self.purchase.amount_on_card_usd))
        return price

    def payout_cap(self, protection: Protection) -> Decimal:
        """§5.5: the lesser of the benefit's per-item cap and the amount charged to the card."""
        limits = protection.limits
        cap = limits.per_item_usd if limits.per_item_usd is not None else limits.per_claim_usd
        charged = self.charged_usd()
        return charged if cap is None else min(to_decimal(cap), charged)

    def deadline(self, protection: Protection) -> Deadline:
        notice = protection.notice
        if notice.notify_within_days is None and notice.submit_docs_within_days is None:
            return Deadline(type="unknown", date=None, note="Check the notice deadline in your Guide to Benefits")
        parts, first_date, kind = [], None, None
        if notice.notify_within_days is not None:
            first_date = add_days(self.incident.date, notice.notify_within_days)
            kind = "notify_by"
            parts.append(f"Notify by {fmt_date(first_date)}")
        if notice.submit_docs_within_days is not None:
            docs = add_days(self.incident.date, notice.submit_docs_within_days)
            if first_date is None:
                first_date, kind = docs, "file_by"
                parts.append(f"Send documents by {fmt_date(docs)}")
            else:
                parts.append(f"send documents by {fmt_date(docs)}")
        note = "; ".join(parts) + ", or as soon as reasonably possible."
        if self.as_of > first_date:
            note += " That date has passed, so act as soon as you can."
        return Deadline(type=kind, date=first_date, note=note)

    @staticmethod
    def no_deadline() -> Deadline:
        return Deadline(type="unknown", date=None, note=None)

    # --- Response builders -------------------------------------------------------------------

    def respond(self, *, verdict: str, benefit: str, route: str, headline: str, why: str,
                citations: list[Citation], protection: Protection | None = None,
                payout: Decimal | None = None, checklist: list[str] | None = None,
                with_deadline: bool = False) -> CoverageResponse:
        if protection is not None and verdict != "not_covered":
            limits = protection.limits
            limit = CoverageLimit(
                per_item_usd=_float(limits.per_item_usd),
                per_claim_usd=_float(limits.per_claim_usd),
                per_account_usd=_float(limits.per_account_usd),
                payout_cap_usd=_float(payout),
                applies_to=limits.applies_to,
            )
            claim = protection.claim
            contact = Contact(administrator=claim.administrator, url=claim.url)
        else:
            limit = CoverageLimit(applies_to=None)
            contact = Contact(administrator=None, url=None)
        deadline = self.deadline(protection) if with_deadline and protection is not None else self.no_deadline()
        cause = self.incident.cause
        return CoverageResponse(
            verdict=verdict,
            benefit=benefit,
            route=route,
            headline=headline,
            why=why,
            limit=limit,
            assumptions=list(self.assumptions),
            citations=citations,
            checklist=list(checklist or []),
            deadline=deadline,
            contact=contact,
            disclaimer=DISCLAIMER,
            # The cause actually used (after classify_if_needed) and its source as sent or set; no
            # source without a cause.
            incident=IncidentCause(cause=cause, cause_source=self.incident.cause_source if cause is not None else None),
        )

    # §5.5 headlines end with a period ("Not covered.", "Need more info.").
    def not_covered(self, why: str, citation: Citation, headline: str = "Not covered.",
                    route: str = "none") -> CoverageResponse:
        return self.respond(verdict="not_covered", benefit="none", route=route, headline=headline,
                            why=why, citations=[citation])

    def need_more_info(self, why: str, protection: Protection | None, citations: list[Citation] | None = None,
                       checklist: list[str] | None = None) -> CoverageResponse:
        benefit = protection.type if protection is not None and protection.type in ROUTES else "none"
        return self.respond(
            verdict="need_more_info",
            benefit=benefit,
            route=ROUTES.get(benefit, "none"),
            headline="Need more info.",
            why=why,
            citations=citations or ([self.cite(protection)] if protection is not None else [self.cite_absence()]),
            protection=protection if benefit != "none" else None,
            checklist=checklist,
            with_deadline=benefit != "none",
        )

    def may_be_eligible(self, protection: Protection, why: str, checklist: list[str]) -> CoverageResponse:
        """A benefit fits on dates and cause; the purchase's own terms (category, condition,
        payment) can still turn it into need_more_info or not_covered."""
        blocked = self.terms_block(protection)
        if blocked is not None:
            verdict, reason = blocked
            if verdict == "not_covered":
                return self.not_covered(reason, self.cite(protection))
            return self.need_more_info(f"{why} {reason}", protection, checklist=CHECKLIST_BASE)

        benefit = protection.type
        cap = self.payout_cap(protection)
        price = to_decimal(self.purchase.price_usd)
        if self.purchase.paid_with == "card_partial" and self.purchase.amount_on_card_usd is not None:
            why += (f" Charging part of the price qualifies; the payout is at most the "
                    f"{fmt_usd(self.charged_usd())} paid on the card.")
        verified = protection.verification.status == "verified"
        if not verified:
            self.assume("Paywise hasn't fully verified these terms yet; check the cited clause.")
        if verified and cap < price:
            headline = f"May be eligible: {BENEFIT_NAMES[benefit]}, up to {fmt_usd(cap)} of the {fmt_usd(price)}."
        else:
            headline = f"May be eligible: {BENEFIT_NAMES[benefit]} ({self.name})."
        return self.respond(
            verdict="may_be_eligible",
            benefit=benefit,
            route=ROUTES[benefit],
            headline=headline,
            why=why,
            citations=[self.cite(protection)],
            protection=protection,
            payout=cap,
            checklist=checklist,
            with_deadline=True,
        )

    def terms_block(self, protection: Protection) -> tuple[str, str] | None:
        """(verdict, reason) when the purchase doesn't meet the benefit's terms; None when it does."""
        purchase, eligibility = self.purchase, protection.eligibility
        benefit = BENEFIT_NAMES.get(protection.type, "This benefit")
        if purchase.category in eligibility.excluded_categories:
            return "not_covered", f"{benefit} doesn't cover {purchase.category.replace('_', ' ')} items."
        allowed = eligibility.conditions_allowed
        if allowed is not None and purchase.condition not in allowed:
            if purchase.condition != "unknown":
                return "need_more_info", (
                    f"Paywise's rules for this benefit cover {' or '.join(allowed)} items; "
                    f"for a {purchase.condition} item, check the cited clause."
                )
            self.assume(f"Assumes the item was {' or '.join(allowed)} when you bought it.")
        if purchase.paid_with == "bnpl":
            return "need_more_info", (
                "This benefit needs the purchase charged to the card. If you paid with buy now, "
                "pay later, check the cited clause."
            )
        if eligibility.payment_requirement == "full" and purchase.paid_with == "card_partial":
            return "not_covered", f"{benefit} needs the full price charged to the card."
        if purchase.paid_with == "unknown":
            self.assume(f"Assumes you paid the full price with {self.name}.")
        return None

    # --- The §5.5 checks ---------------------------------------------------------------------

    def run(self) -> CoverageResponse:
        cause = self.incident.cause
        if cause is None or cause == "unknown":
            return self.need_cause()
        if cause == "failure":
            return self.failure()
        return self.theft_damage_loss(cause)

    def need_cause(self) -> CoverageResponse:
        why = (
            "Pick what happened: Stopped working, Dropped or damaged, Stolen or Lost. "
            "Which benefit applies depends on the cause."
        )
        if self.classifier_failed:
            why = "Paywise couldn't tell what happened from your description. " + why
        counted = [p for p in (self.ew, self.pp) if p is not None]
        citations = [self.cite(p) for p in counted] or [self.cite_absence()]
        return self.need_more_info(why, None, citations=citations)

    def failure(self) -> CoverageResponse:
        w, day, ew = self.w, self.incident.date, self.ew
        maker = months_phrase(w.maker_months, adjective=True) if w.maker_months else None

        # 1. Still under the maker's warranty (R9: this route is for failures only).
        if w.under_maker(day):
            if w.ew_end is not None:
                # §5.5 copy: "starts {maker end}". On the maker's last day itself the card's year
                # isn't in effect yet (it is from the next day), so that day says "starts after".
                starts = "starts after" if day == w.maker_end else "starts"
                return self.not_covered(
                    f"Contact the manufacturer first. The card's {extra_phrase(ew.extends_by_months)} "
                    f"{starts} {fmt_date(w.maker_end)}.",
                    self.cite(ew),
                    headline="Not covered by your card yet: it's still under the maker's warranty.",
                    route="manufacturer",
                )
            if ew is None:
                why = f"Contact the manufacturer first. {self.name} has no extended warranty."
                citation = self.cite_absence()
            else:
                why = f"Contact the manufacturer first. {self.ew_block_reason()}"
                citation = self.cite(ew)
            return self.not_covered(why, citation, headline="Not covered by your card: it's still under the maker's warranty.",
                                    route="manufacturer")

        # 2. The card's extended warranty.
        if ew is None:
            ended = f"The maker's {maker} warranty ended {fmt_date(w.maker_end)}. " if w.maker_end else ""
            what = "purchase protection or extended warranty" if self.pp is None else "extended warranty"
            pp_note = " Its purchase protection covers theft and damage, not failures." if self.pp else ""
            return self.not_covered(f"{ended}{self.name} has no {what}.{pp_note}",
                                    self.cite_absence() if self.pp is None else self.cite(self.pp))
        if w.ew_block is not None:
            return self.not_covered(self.ew_block_reason(), self.cite(ew))
        extra = extra_phrase(ew.extends_by_months)
        if w.in_ew(day):
            return self.may_be_eligible(
                ew,
                # §5.5 copy, verbatim: "The maker's 1-year warranty ended Oct 17, 2027; the extra year runs to
                # Oct 17, 2028."
                f"The maker's {maker} warranty ended {fmt_date(w.maker_end)}; the {extra} runs to "
                f"{fmt_date(w.ew_end)}.",
                CHECKLIST_EW,
            )
        return self.not_covered(
            f"The maker's {maker} warranty ended {fmt_date(w.maker_end)}, and the {extra} ended {fmt_date(w.ew_end)}.",
            self.cite(ew),
        )

    def ew_block_reason(self) -> str:
        """Why the card's extended warranty can't run for this purchase (Windows.ew_block)."""
        limit = self.ew.max_original_warranty_months if self.ew is not None else None
        if self.w.ew_block == "no_maker_warranty":
            return "There's no maker's warranty, so the extended warranty has nothing to extend."
        if self.w.ew_block == "maker_too_long" and limit is not None and self.w.maker_months > limit:
            return f"The extended warranty only extends maker's warranties of {months_phrase(limit)} or less."
        return f"{self.name}'s extended warranty doesn't apply here."

    def theft_damage_loss(self, cause: str) -> CoverageResponse:
        w, day, pp, ew = self.w, self.incident.date, self.pp, self.ew
        needs = COVER_FOR_CAUSE[cause]

        if pp is None:
            if self.cpp is not None and self.purchase.category == "phones" and needs in self.cpp.covers:
                return self.need_more_info(
                    f"{self.name} has cell phone protection, which may cover a phone when you pay the monthly "
                    "phone bill with the card. Paywise doesn't check that benefit yet; see the cited clause.",
                    None,
                    citations=[self.cite(self.cpp)],
                )
            in_effect = ew is not None and w.in_ew(day)
            return self.not_covered(
                f"{self.name} has no purchase protection."
                + (" The extended warranty covers failures only." if in_effect else ""),
                self.cite(ew) if in_effect else self.cite_absence(),
            )

        if w.pp_end is None:  # a purchase protection without a window in cards.json
            return self.need_more_info("Paywise doesn't have this benefit's time window; see the cited clause.", pp)
        days = pp_days_phrase(pp)
        if w.in_pp(day):
            if needs not in pp.covers:
                return self.not_covered(
                    f"{self.name}'s purchase protection doesn't cover this cause ({CAUSE_LABELS[cause]}).",
                    self.cite(pp))
            self.note_state_windows(pp)
            window = f"within {days}, to {fmt_date(w.pp_end)}"
            if cause == "loss":
                # §5.5's need_more_info copy has no end date: "within 120 days (90 in NY)" only.
                return self.need_more_info(
                    f"Theft and “involuntary and accidental parting” may be covered within {days}; "
                    "simply losing something may not be. See the cited clause.",
                    pp,
                    checklist=CHECKLIST_BASE,
                )
            if cause == "cosmetic":
                return self.need_more_info(
                    f"Damage is covered {window}, but cosmetic damage that doesn't affect how it works may "
                    "not be. If it was dropped or damaged, pick that instead. See the cited clause.",
                    pp,
                    checklist=[*CHECKLIST_BASE, REPAIR_ESTIMATE],
                )
            if cause == "theft":
                checklist = [*CHECKLIST_BASE, POLICE_REPORT]
                if PORCH_WORDS.search(self.incident.description):
                    checklist.append(PORCH_THEFT)
                return self.may_be_eligible(pp, f"Theft is covered {window}.", checklist)
            return self.may_be_eligible(pp, f"Accidental damage is covered {window}.",
                                        [*CHECKLIST_BASE, REPAIR_ESTIMATE])

        # After the purchase protection window. Cite the benefit in effect on the incident date
        # (the extended warranty, which doesn't cover this cause), else purchase protection.
        if cause == "loss":
            why = f"Purchase protection ran for {days}, to {fmt_date(w.pp_end)}."
        else:
            noun = "Theft" if cause == "theft" else "Damage"
            why = f"{noun} was covered for {days}, to {fmt_date(w.pp_end)}."
        if ew is not None:
            not_what = {"theft": "theft", "loss": "losses"}.get(cause, "drops")
            why += f" The extended warranty covers failures, not {not_what}."
        return self.not_covered(why, self.cite(ew) if ew is not None and w.in_ew(day) else self.cite(pp))

    def note_state_windows(self, pp: Protection) -> None:
        """§5.5 New York note: say so when a shorter state window has already ended."""
        for state, days in sorted(pp.window_days_by_state.items()):
            state_end = add_days(self.purchase.purchase_date, days)
            if self.incident.date > state_end:
                self.assume(f"In {state}, purchase protection lasts {days} days, so there it ended {fmt_date(state_end)}.")


def _float(value) -> float | None:
    return None if value is None else float(value)


def assess(req: CoverageRequest, *, cards: Catalog | None = None, classifier_failed: bool = False) -> CoverageResponse:
    """The verdict for one request. Pure: same request, same answer (no clock, no network)."""
    return _Assessment(req, cards or catalog.CATALOG, classifier_failed).run()


# --- COVERAGE_MODE=llm: cause classification -------------------------------------------------


def coverage_mode() -> str:
    """'llm' or 'rules' (the default; anything else, e.g. the .env.example placeholder, is rules)."""
    return "llm" if os.environ.get("COVERAGE_MODE", "rules").strip().lower() == "llm" else "rules"


async def _classify(description: str) -> str | None:
    """app.llm.classify_cause(description) -> one of CAUSES, or None if it can't help.

    Accepts a sync or async classifier returning a cause string, a dict with "cause", or an
    object with a .cause attribute. Errors are logged by type only (never the description).
    """
    try:
        from app.llm import classify_cause  # lazy: the LLM track owns app/llm.py

        if inspect.iscoroutinefunction(classify_cause):
            result = await asyncio.wait_for(classify_cause(description), CLASSIFY_TIMEOUT_S)
        else:
            result = await asyncio.wait_for(asyncio.to_thread(classify_cause, description), CLASSIFY_TIMEOUT_S)
        if inspect.isawaitable(result):
            result = await asyncio.wait_for(result, CLASSIFY_TIMEOUT_S)
    except Exception as exc:  # noqa: BLE001  any classifier failure -> ask the user to pick
        log.warning("coverage: cause classification failed (%s)", type(exc).__name__)
        return None
    if isinstance(result, dict):
        result = result.get("cause")
    else:
        result = getattr(result, "cause", result)
    return result if isinstance(result, str) and result in CAUSES else None


async def classify_if_needed(req: CoverageRequest) -> tuple[CoverageRequest, bool]:
    """With COVERAGE_MODE=llm and a null cause, fill the cause from the description
    (causeSource "llm"; assess echoes it in the response's `incident`). Returns
    (request, classifier_failed)."""
    if req.incident.cause is not None or coverage_mode() != "llm":
        return req, False
    cause = await _classify(req.incident.description)
    if cause is None:
        return req, True
    incident = req.incident.model_copy(update={"cause": cause, "cause_source": "llm"})
    return req.model_copy(update={"incident": incident}), False


async def check(req: CoverageRequest, *, cards: Catalog | None = None) -> CoverageResponse:
    """classify_if_needed, then assess."""
    req, failed = await classify_if_needed(req)
    return assess(req, cards=cards, classifier_failed=failed)
