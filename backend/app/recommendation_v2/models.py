"""Structured v2 contracts. Money is strict integer USD cents, rates are basis points."""

from datetime import date
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator
from pydantic.alias_generators import to_camel

Truth = Literal["yes", "no", "unknown"]
Money = Annotated[int, Field(strict=True, ge=0, le=1_000_000_000)]
SignedMoney = Annotated[int, Field(strict=True)]
Identifier = Annotated[str, Field(pattern=r"^[a-zA-Z][a-zA-Z0-9_-]{0,79}$")]
Path = Literal["direct_card", "apple_pay", "paypal", "other"]
BenefitType = Literal["purchase_damage_theft", "extended_warranty", "return_protection", "price_protection"]
Knowledge = Literal["verified_rule", "verified_summary", "unknown", "not_listed", "conflict"]


class Model(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True, extra="forbid")


class CapUsage(Model):
    posted_minor: Money
    pending_minor: Money | None
    reserved_minor: Money
    period_start: date
    period_end: date  # inclusive
    as_of: date
    account_scope_confirmed: bool = False

    @model_validator(mode="after")
    def ordered_period(self):
        if self.period_start > self.period_end:
            raise ValueError("cap period start must not follow its end")
        return self


class ZeroPurchaseApr(Model):
    apr_bps: Annotated[int, Field(strict=True, ge=0, le=100000)]
    valid_from: date
    valid_through: date
    repayment_complete_by: date
    verified: bool = False

    @model_validator(mode="after")
    def ordered_period(self):
        if self.valid_from > self.valid_through or self.repayment_complete_by < self.valid_from:
            raise ValueError("invalid purchase APR period")
        return self


class Purchase(Model):
    total_minor: Money
    currency: Literal["USD"] = "USD"
    channel: Literal["merchant_web", "merchant_app"] = "merchant_web"
    charge_date: date
    accepted_networks: Annotated[list[Literal["visa", "mastercard", "amex", "discover"]], Field(max_length=4)] | None = None


class CardOption(Model):
    wallet_card_id: Identifier
    product_id: Identifier
    payment_path: Path = "direct_card"
    is_default: bool = False
    network: Literal["visa", "mastercard", "amex", "discover"] | None = None
    active: Truth = "unknown"
    available_credit_minor: Money | None = None
    path_eligible: Truth = "unknown"
    # Confirmation applies to this account and payment path, not just a public product page.
    policy_confirmed_through: date | None = None
    issuer_eligible_purchase: Truth = "unknown"
    issuer_category: Annotated[str, Field(max_length=80)] | None = None
    category_confirmed_through: date | None = None
    category_selection: Annotated[str, Field(max_length=80)] | None = None
    selection_effective_at: date | None = None
    # Confirm the issuer's posting/period assignment; do not assume the charge date.
    reward_period_date: date | None = None
    cap_usage: Annotated[dict[str, CapUsage], Field(max_length=16)] = Field(default_factory=dict)
    membership_bonus_bps: Annotated[int, Field(strict=True, ge=0, le=10000)] | None = None
    confirmed_intro_offer_ids: Annotated[list[Identifier], Field(max_length=10)] = Field(default_factory=list)
    expected_full_repayment: Truth = "unknown"
    purchase_grace_period_active: Truth = "unknown"
    purchase_intro_apr: ZeroPurchaseApr | None = None
    eligible_payment_and_tracker_confirmed: Truth = "unknown"
    foreign_fee_applies: Truth = "unknown"
    checkout_fee_minor: Money | None = None


class ProtectionTarget(Model):
    benefit_type: BenefitType
    min_nominal_limit_minor: Money = 0
    min_window_days: Annotated[int, Field(strict=True, ge=0, le=36500)] = 0
    min_extension_months: Annotated[int, Field(strict=True, ge=0, le=1200)] = 0


class Preferences(Model):
    mode: Literal["cash_first", "protection_target"] = "cash_first"
    cash_sacrifice_budget_minor: Money | None = None
    protection_targets: Annotated[list[ProtectionTarget], Field(max_length=10)] = Field(default_factory=list)
    allow_loss_of_existing_protection: bool = False
    switch_threshold_minor: Money = 500  # Product setting, not an issuer term.

    @model_validator(mode="after")
    def targets_required(self):
        if self.mode == "protection_target" and not self.protection_targets:
            raise ValueError("protection_target mode requires at least one target")
        return self


class RecommendRequest(Model):
    request_id: Identifier
    purchase: Purchase
    options: Annotated[list[CardOption], Field(min_length=1, max_length=30)]
    preferences: Preferences = Field(default_factory=Preferences)

    @model_validator(mode="after")
    def unique_options(self):
        keys = [(o.wallet_card_id, o.payment_path) for o in self.options]
        if len(set(keys)) != len(keys):
            raise ValueError("duplicate card and payment path")
        if sum(o.is_default for o in self.options) != 1:
            raise ValueError("exactly one option must be the default")
        for card_id in {o.wallet_card_id for o in self.options}:
            account_states = []
            for o in self.options:
                if o.wallet_card_id == card_id:
                    state = o.model_dump(exclude={"payment_path", "is_default", "path_eligible", "checkout_fee_minor",
                                                   "policy_confirmed_through", "issuer_eligible_purchase", "issuer_category",
                                                   "category_confirmed_through", "foreign_fee_applies"})
                    account_states.append(state)
            if any(s != account_states[0] for s in account_states[1:]):
                raise ValueError("account facts must agree across payment paths")
        return self


class Interval(Model):
    low_minor: SignedMoney
    high_minor: SignedMoney

    @model_validator(mode="after")
    def ordered(self):
        if self.low_minor > self.high_minor:
            raise ValueError("interval is reversed")
        return self


class BenefitSummary(Model):
    benefit_type: BenefitType
    knowledge: Knowledge
    eligibility: Literal["needs_info"] = "needs_info"
    automatic_item_eligibility_enabled: Literal[False] = False
    source_ids: list[str]


class OptionEstimate(Model):
    wallet_card_id: str
    product_id: str
    payment_path: Path
    availability: Literal["eligible", "ineligible", "needs_info"]
    reward: Interval | None = None
    conditional_payment_reward: Interval | None = None
    net: Interval | None = None
    estimated: Literal[True] = True
    missing_fields: list[str] = Field(default_factory=list)
    notes: list[str] = Field(default_factory=list)
    rule_ids: list[str] = Field(default_factory=list)
    source_ids: list[str] = Field(default_factory=list)
    benefits: list[BenefitSummary] = Field(default_factory=list)


class Selection(Model):
    wallet_card_id: str
    payment_path: Path


class Source(Model):
    id: str
    title: str
    url: str
    observed_at: date


class RecommendResponse(Model):
    request_id: str
    policy_version: str
    policy_snapshot_id: str
    decision: Literal["keep", "switch", "recommend", "needs_info", "choice_required"]
    reason: str
    selected: Selection | None = None
    cash_delta: Interval | None = None
    ranking_scope: Literal["supported_ordinary_rewards_only"] = "supported_ordinary_rewards_only"
    options: list[OptionEstimate]
    sources: list[Source]
