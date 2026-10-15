"""Pydantic models mirroring contracts/ (SPEC.md §15.5).

Python fields are snake_case; the JSON is camelCase, as in contracts/. Change a contract's
schema, its example and the model here together: tests/test_contracts.py checks that they agree.

Money is float on the wire. The engine converts to Decimal before any math (§7.2 rule 1).
"""

import datetime as dt
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator
from pydantic.alias_generators import to_camel

# --- Shared types (contracts/common.schema.json) -------------------------------------------

Uuid = Annotated[
    str, Field(pattern=r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
]
CardId = Annotated[str, Field(pattern=r"^[a-z0-9]+(-[a-z0-9]+)*$")]
MerchantId = Annotated[str, Field(pattern=r"^[a-z0-9]+(-[a-z0-9]+)*$")]
ItemCategoryId = Annotated[str, Field(pattern=r"^[a-z0-9]+(_[a-z0-9]+)*$")]
PurchaseId = Annotated[str, Field(pattern=r"^p_[A-Za-z0-9-]+$")]
Usd = Annotated[float, Field(ge=0)]
Probability = Annotated[float, Field(ge=0, le=1)]

ItemCondition = Literal["new", "renewed", "used", "unknown"]
ProtectionType = Literal["purchase_protection", "extended_warranty", "cell_phone_protection"]
LimitAppliesTo = Literal["item", "claim"]
Verification = Literal["verified", "partial", "unverified"]
PurchaseStatus = Literal["planned", "confirmed"]

# --- /v1/check enums --------------------------------------------------------------------------

ScreenType = Literal["checkout", "order_confirmation", "not_checkout", "unreadable"]
DecisionKind = Literal["switch", "keep", "no_checkout", "error"]
DecisionReason = Literal[
    "protection", "cash", "method", "default_best", "below_threshold", "items_unreadable",
    "already_protected", "already_paid", "not_checkout", "unreadable", "error",
]
Presentation = Literal["snippet", "island"]
PaymentPath = Literal["apple_pay", "saved_card", "card_form", "unknown"]
Instruction = Literal["change_saved_card", "enter_card", "apple_pay_swipe", "use_apple_pay", "none"]
Confidence = Literal["high", "medium", "low"]
Seller = Literal["merchant", "third_party", "unknown"]
PaymentOption = Literal["apple_pay", "saved_card", "card_form", "bnpl", "paypal", "other"]
SelectedPaymentKind = Literal["saved_card", "card_form", "apple_pay", "unknown"]
Network = Literal["visa", "mastercard", "discover", "amex", "unknown"]
ErrorCode = Literal["parse_failed", "timeout", "bad_request", "privacy_rejected", "server_error"]


class Contract(BaseModel):
    """Base for every contract model: camelCase JSON, unknown fields rejected."""

    model_config = ConfigDict(
        alias_generator=to_camel,
        validate_by_name=True,
        validate_by_alias=True,
        serialize_by_alias=True,
        extra="forbid",
    )


class CoverageEntry(Contract):
    type: ProtectionType
    until: dt.date
    limit_usd: Usd | None = None
    assumes_manufacturer_warranty_months: Annotated[int, Field(ge=0)] | None = None


# --- POST /v1/check request ------------------------------------------------------------------


class Client(Contract):
    app: str
    version: str


class Screen(Contract):
    ocr_text: str
    redactions: list[str]
    ocr_confidence: Probability


class WalletCard(Contract):
    card_id: CardId
    is_default: bool


class Wallet(Contract):
    cards: Annotated[list[WalletCard], Field(min_length=1)]

    @model_validator(mode="after")
    def one_default(self) -> "Wallet":
        if sum(card.is_default for card in self.cards) != 1:
            raise ValueError("exactly one wallet card must be the default")
        return self


class Prefs(Contract):
    pays_in_full: bool | None


class CheckRequest(Contract):
    request_id: Uuid
    client: Client
    client_date: dt.date
    screen: Screen
    wallet: Wallet
    prefs: Prefs


# --- POST /v1/check response -----------------------------------------------------------------


class CartMerchant(Contract):
    name: str | None
    merchant_id: MerchantId | None


class Item(Contract):
    name: str
    price_usd: Usd
    quantity: Annotated[int, Field(ge=1)]
    category: ItemCategoryId
    condition: ItemCondition
    seller: Seller
    is_gift_card: bool
    is_service_plan: bool


class SelectedPayment(Contract):
    kind: SelectedPaymentKind
    network: Network


class Upsells(Contract):
    protection_plan_usd: Usd | None


class CartConfidence(Contract):
    merchant: Probability
    total: Probability
    items: Probability


class Cart(Contract):
    merchant: CartMerchant
    items: list[Item]
    total_usd: Usd | None
    currency: Annotated[str, Field(pattern=r"^[A-Z]{3}$")]
    payment_options_visible: list[PaymentOption]
    selected_payment: SelectedPayment
    upsells: Upsells
    bnpl_visible: bool
    confidence: CartConfidence


class Cash(Contract):
    by_card: dict[CardId, float]
    delta_vs_cash_best: float | None
    delta_vs_default: float | None


class ProtectionLimit(Contract):
    amount_usd: Usd | None
    applies_to: LimitAppliesTo


class ProtectionChange(Contract):
    type: ProtectionType
    window_days: Annotated[int, Field(ge=1)] | None = None
    extends_by_months: Annotated[int, Field(ge=1)] | None = None
    limit: ProtectionLimit
    verification: Verification


class Copy(Contract):
    """§6.3 copy, with {last4:<cardId>} and {ppCap} placeholders the phone fills."""

    line1: str
    line2: str | None = None
    line3: str | None = None
    instruction: str | None = None
    primary_button: str | None = None


class Decision(Contract):
    kind: DecisionKind
    reason: DecisionReason
    presentation: Presentation
    recommended_card_id: CardId | None
    default_card_id: CardId | None
    cash_best_card_id: CardId | None
    payment_path: PaymentPath
    instruction: Instruction
    cash: Cash | None
    protections_gained: list[ProtectionChange]
    protections_lost: list[ProtectionChange]
    eligibility_notes: list[str]
    confidence: Confidence
    # "copy" would shadow BaseModel.copy, so the Python name differs from the JSON key.
    copy_: Copy = Field(alias="copy")


class PurchaseDraft(Contract):
    merchant: str
    item: str
    category: ItemCategoryId
    condition: ItemCondition
    price_usd: Usd
    purchase_date: dt.date
    card_id: CardId
    coverage: list[CoverageEntry]


class Source(Contract):
    card_id: CardId
    document: str
    section: str | None
    version_date: dt.date | None
    verification: Verification


class TimingMs(Contract):
    parse: Annotated[int, Field(ge=0)]
    engine: Annotated[int, Field(ge=0)]


class CheckResult(Contract):
    request_id: Uuid
    screen_type: ScreenType
    cart: Cart | None
    decision: Decision
    purchase_draft: PurchaseDraft | None
    sources: list[Source]
    timing_ms: TimingMs


class ErrorDecision(Contract):
    kind: Literal["error"]
    reason: Literal["error"]
    presentation: Literal["island"]
    copy_: Copy = Field(alias="copy")


class ErrorDetail(Contract):
    code: ErrorCode
    message: str


class CheckError(Contract):
    request_id: Uuid | None
    decision: ErrorDecision
    error: ErrorDetail


CheckResponse = CheckResult | CheckError


# --- On-device records -----------------------------------------------------------------------


class FilledCopy(Contract):
    line1: str
    line2: str | None = None
    line3: str | None = None
    instruction: str | None = None


class CheckRecord(Contract):
    check_id: Uuid
    created_at: dt.datetime
    sent_payload: CheckRequest
    response: CheckResponse
    filled_copy: FilledCopy
    replayed: bool
    saved_purchase_id: PurchaseId | None
    view: Literal["result", "saved", "sent"]


class Purchase(Contract):
    id: PurchaseId
    check_id: Uuid | None
    status: PurchaseStatus
    merchant: str
    item: str
    category: ItemCategoryId
    condition: ItemCondition
    price_usd: Usd
    purchase_date: dt.date
    card_id: CardId
    coverage: list[CoverageEntry]
    manufacturer_warranty_months: Annotated[int, Field(ge=0)] | None
    order_number: str | None
    transaction_id: str | None


class LiveActivityContentState(Contract):
    phase: Literal["checking", "keep", "no_checkout", "error", "switch_fallback"]
    glyph: Literal["fp", "check", "warning", "card"]
    card_short_name: str | None
    last4: Annotated[str, Field(pattern=r"^[0-9]{4}$")] | None
    line1: str
    line2: str | None
    lock_screen_text: str


# --- POST /v1/coverage -----------------------------------------------------------------------


class CoveragePurchase(Contract):
    card_id: CardId
    merchant: str
    item: str
    category: ItemCategoryId
    condition: ItemCondition
    price_usd: Usd
    purchase_date: dt.date
    status: PurchaseStatus
    manufacturer_warranty_months: Annotated[int, Field(ge=0)] | None
    manufacturer_warranty_source: Literal["user", "assumed"]
    paid_with: Literal["card_full", "card_partial", "bnpl", "unknown"]


class Incident(Contract):
    date: dt.date
    description: str
    cause: Literal["failure", "accidental_damage", "theft", "loss", "cosmetic", "unknown"] | None
    cause_source: Literal["user_confirmed", "llm"] | None


class CoverageRequest(Contract):
    purchase: CoveragePurchase
    incident: Incident
    as_of: dt.date


class CoverageLimit(Contract):
    per_item_usd: Usd | None = None
    per_claim_usd: Usd | None = None
    per_account_usd: Usd | None = None
    payout_cap_usd: Usd | None = None
    applies_to: LimitAppliesTo | None


class Citation(Contract):
    document: str
    section: str | None
    version_date: dt.date | None
    quote: str | None
    verification: Verification


class Deadline(Contract):
    type: Literal["notify_by", "file_by", "unknown"]
    date: dt.date | None
    note: str | None


class Contact(Contract):
    administrator: str | None
    url: str | None


class CoverageResponse(Contract):
    verdict: Literal["may_be_eligible", "not_covered", "need_more_info"]
    benefit: Literal["purchase_protection", "extended_warranty", "none"]
    route: Literal["card_extended_warranty", "card_purchase_protection", "manufacturer", "none"]
    headline: str
    why: str
    limit: CoverageLimit
    assumptions: list[str]
    citations: list[Citation]
    checklist: list[str]
    deadline: Deadline
    contact: Contact
    disclaimer: str


# --- POST /v1/store/pay ----------------------------------------------------------------------


class StorePayRequest(Contract):
    order_id: Annotated[str, Field(min_length=1)]
    saved_card_id: Annotated[str, Field(pattern=r"^demo-[a-z]+-[0-9]{4}$")]
    amount_usd: Annotated[float, Field(gt=0)]


class StorePayResponse(Contract):
    status: Literal["approved", "declined", "error"]
    processor: Literal["visa_acceptance_sandbox", "mock"]
    transaction_id: str | None
    card_label: str | None


# Contract name (contracts/<name>.schema.json) -> the type that mirrors it.
CONTRACTS: dict[str, object] = {
    "check.request": CheckRequest,
    "check.response": CheckResponse,
    "coverage.request": CoverageRequest,
    "coverage.response": CoverageResponse,
    "store-pay.request": StorePayRequest,
    "store-pay.response": StorePayResponse,
    "live-activity-content-state": LiveActivityContentState,
    "check-record": CheckRecord,
    "purchase": Purchase,
}
