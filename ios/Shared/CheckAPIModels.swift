import Foundation

// Codable mirrors of `contracts/check.request.schema.json` and `contracts/check.response.schema.json`
// (SPEC §15.5). The request is exact; the response is decoded tolerantly: every field is optional and
// an enum string the app doesn't know decodes to a fallback case instead of failing.

// MARK: - Request

/// `POST /v1/check` body. No images and no last 4: a wallet card is only `cardId` + `isDefault`.
struct CheckRequest: Codable, Sendable, Equatable {
    struct Client: Codable, Sendable, Equatable {
        var app: String
        var version: String
    }

    struct Screen: Codable, Sendable, Equatable {
        /// Redacted on device, top strip already cropped.
        var ocrText: String
        var redactions: [String]
        var ocrConfidence: Double
    }

    struct WalletCard: Codable, Sendable, Equatable {
        var cardId: String
        var isDefault: Bool
    }

    struct Wallet: Codable, Sendable, Equatable {
        var cards: [WalletCard]
    }

    struct Prefs: Codable, Sendable, Equatable {
        var paysInFull: Bool?

        private enum CodingKeys: String, CodingKey { case paysInFull }

        // The contract requires the key, so `nil` is written as `null` rather than left out.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(paysInFull, forKey: .paysInFull)
        }
    }

    var requestId: String
    var client: Client
    var clientDate: String
    var screen: Screen
    var wallet: Wallet
    var prefs: Prefs
}

// MARK: - Tolerant enums

/// A string enum that decodes an unknown value to `fallback` instead of throwing.
protocol TolerantEnum: RawRepresentable, Codable, Sendable, Hashable where RawValue == String {
    static var fallback: Self { get }
}

extension TolerantEnum {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = Self(rawValue: raw) ?? Self.fallback
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum ScreenType: String, TolerantEnum {
    case checkout, orderConfirmation = "order_confirmation", notCheckout = "not_checkout", unreadable
    case unrecognized
    static let fallback = Self.unrecognized
}

enum DecisionKind: String, TolerantEnum {
    case `switch`, keep, noCheckout = "no_checkout", error
    case unrecognized
    static let fallback = Self.unrecognized
}

enum DecisionReason: String, TolerantEnum {
    case protection, cash, method
    case defaultBest = "default_best", belowThreshold = "below_threshold", itemsUnreadable = "items_unreadable"
    case alreadyProtected = "already_protected", alreadyPaid = "already_paid"
    case notCheckout = "not_checkout", unreadable, error
    case unrecognized
    static let fallback = Self.unrecognized
}

enum Presentation: String, TolerantEnum {
    case snippet, island
    case unrecognized
    static let fallback = Self.unrecognized
}

enum PaymentPath: String, TolerantEnum {
    case applePay = "apple_pay", savedCard = "saved_card", cardForm = "card_form", unknown
    static let fallback = Self.unknown
}

enum InstructionKind: String, TolerantEnum {
    case changeSavedCard = "change_saved_card", enterCard = "enter_card"
    case applePaySwipe = "apple_pay_swipe", useApplePay = "use_apple_pay", none
    case unrecognized
    static let fallback = Self.unrecognized
}

enum DecisionConfidence: String, TolerantEnum {
    case high, medium, low
    case unrecognized
    static let fallback = Self.unrecognized
}

enum ItemCondition: String, TolerantEnum {
    case new, renewed, used, unknown
    static let fallback = Self.unknown
}

enum Seller: String, TolerantEnum {
    case merchant, thirdParty = "third_party", unknown
    static let fallback = Self.unknown
}

enum PaymentOption: String, TolerantEnum {
    case applePay = "apple_pay", savedCard = "saved_card", cardForm = "card_form", bnpl, paypal, other
    static let fallback = Self.other
}

enum SelectedPaymentKind: String, TolerantEnum {
    case savedCard = "saved_card", cardForm = "card_form", applePay = "apple_pay", unknown
    static let fallback = Self.unknown
}

enum CardNetwork: String, TolerantEnum {
    case visa, mastercard, discover, amex, unknown
    static let fallback = Self.unknown
}

enum ProtectionType: String, TolerantEnum {
    case purchaseProtection = "purchase_protection"
    case extendedWarranty = "extended_warranty"
    case cellPhoneProtection = "cell_phone_protection"
    case unrecognized
    static let fallback = Self.unrecognized
}

enum LimitAppliesTo: String, TolerantEnum {
    case item, claim
    case unrecognized
    static let fallback = Self.unrecognized
}

enum VerificationStatus: String, TolerantEnum {
    case verified, partial, unverified
    case unrecognized
    static let fallback = Self.unrecognized
}

enum APIErrorCode: String, TolerantEnum {
    case parseFailed = "parse_failed", timeout, badRequest = "bad_request"
    case privacyRejected = "privacy_rejected", serverError = "server_error"
    case unrecognized
    static let fallback = Self.unrecognized
}

// MARK: - Response

/// `POST /v1/check` response: a result or the error shape. Only fields the phone uses matter,
/// but the whole shape is mirrored so previews and tests can build one.
struct CheckResponse: Codable, Sendable, Equatable {
    struct Merchant: Codable, Sendable, Equatable {
        var name: String?
        var merchantId: String?
    }

    struct Item: Codable, Sendable, Equatable {
        var name: String?
        var priceUsd: Double?
        var quantity: Int?
        var category: String?
        var condition: ItemCondition?
        var seller: Seller?
        var isGiftCard: Bool?
        var isServicePlan: Bool?
    }

    struct SelectedPayment: Codable, Sendable, Equatable {
        var kind: SelectedPaymentKind?
        var network: CardNetwork?
    }

    struct Upsells: Codable, Sendable, Equatable {
        var protectionPlanUsd: Double?
    }

    struct CartConfidence: Codable, Sendable, Equatable {
        var merchant: Double?
        var total: Double?
        var items: Double?
    }

    struct Cart: Codable, Sendable, Equatable {
        var merchant: Merchant?
        var items: [Item]?
        var totalUsd: Double?
        var currency: String?
        var paymentOptionsVisible: [PaymentOption]?
        var selectedPayment: SelectedPayment?
        var upsells: Upsells?
        var bnplVisible: Bool?
        var confidence: CartConfidence?
    }

    struct Cash: Codable, Sendable, Equatable {
        var byCard: [String: Double]?
        var deltaVsCashBest: Double?
        var deltaVsDefault: Double?
    }

    struct Limit: Codable, Sendable, Equatable {
        var amountUsd: Double?
        var appliesTo: LimitAppliesTo?
    }

    struct ProtectionChange: Codable, Sendable, Equatable {
        var type: ProtectionType?
        var windowDays: Int?
        var extendsByMonths: Int?
        var limit: Limit?
        var verification: VerificationStatus?
    }

    /// §6.3 copy with `{last4:<cardId>}` and `{ppCap}` placeholders the phone fills.
    struct Copy: Codable, Sendable, Equatable {
        var line1: String?
        var line2: String?
        var line3: String?
        var instruction: String?
        var primaryButton: String?
    }

    struct Decision: Codable, Sendable, Equatable {
        var kind: DecisionKind?
        var reason: DecisionReason?
        var presentation: Presentation?
        var recommendedCardId: String?
        var defaultCardId: String?
        var cashBestCardId: String?
        var paymentPath: PaymentPath?
        var instruction: InstructionKind?
        var cash: Cash?
        var protectionsGained: [ProtectionChange]?
        var protectionsLost: [ProtectionChange]?
        var eligibilityNotes: [String]?
        var confidence: DecisionConfidence?
        var copy: Copy?

        init(
            kind: DecisionKind? = nil, reason: DecisionReason? = nil, presentation: Presentation? = nil,
            recommendedCardId: String? = nil, defaultCardId: String? = nil, cashBestCardId: String? = nil,
            paymentPath: PaymentPath? = nil, instruction: InstructionKind? = nil, cash: Cash? = nil,
            protectionsGained: [ProtectionChange]? = nil, protectionsLost: [ProtectionChange]? = nil,
            eligibilityNotes: [String]? = nil, confidence: DecisionConfidence? = nil, copy: Copy? = nil
        ) {
            self.kind = kind
            self.reason = reason
            self.presentation = presentation
            self.recommendedCardId = recommendedCardId
            self.defaultCardId = defaultCardId
            self.cashBestCardId = cashBestCardId
            self.paymentPath = paymentPath
            self.instruction = instruction
            self.cash = cash
            self.protectionsGained = protectionsGained
            self.protectionsLost = protectionsLost
            self.eligibilityNotes = eligibilityNotes
            self.confidence = confidence
            self.copy = copy
        }

        /// Field by field, so one malformed field never hides the rest of the decision.
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = c.tolerant(DecisionKind.self, .kind)
            reason = c.tolerant(DecisionReason.self, .reason)
            presentation = c.tolerant(Presentation.self, .presentation)
            recommendedCardId = c.tolerant(String.self, .recommendedCardId)
            defaultCardId = c.tolerant(String.self, .defaultCardId)
            cashBestCardId = c.tolerant(String.self, .cashBestCardId)
            paymentPath = c.tolerant(PaymentPath.self, .paymentPath)
            instruction = c.tolerant(InstructionKind.self, .instruction)
            cash = c.tolerant(Cash.self, .cash)
            protectionsGained = c.tolerant([ProtectionChange].self, .protectionsGained)
            protectionsLost = c.tolerant([ProtectionChange].self, .protectionsLost)
            eligibilityNotes = c.tolerant([String].self, .eligibilityNotes)
            confidence = c.tolerant(DecisionConfidence.self, .confidence)
            copy = c.tolerant(Copy.self, .copy)
        }
    }

    struct PurchaseDraft: Codable, Sendable, Equatable {
        var merchant: String?
        var item: String?
        var category: String?
        var condition: ItemCondition?
        var priceUsd: Double?
        var purchaseDate: String?
        var cardId: String?
        var coverage: [CoverageEntry]?
    }

    struct Source: Codable, Sendable, Equatable {
        var cardId: String?
        var document: String?
        var section: String?
        var versionDate: String?
        var verification: VerificationStatus?
    }

    struct TimingMs: Codable, Sendable, Equatable {
        var parse: Int?
        var engine: Int?
    }

    struct ErrorBody: Codable, Sendable, Equatable {
        var code: APIErrorCode?
        var message: String?
    }

    var requestId: String?
    var screenType: ScreenType?
    var cart: Cart?
    var decision: Decision?
    var purchaseDraft: PurchaseDraft?
    var sources: [Source]?
    var timingMs: TimingMs?
    var error: ErrorBody?

    init(
        requestId: String? = nil, screenType: ScreenType? = nil, cart: Cart? = nil, decision: Decision? = nil,
        purchaseDraft: PurchaseDraft? = nil, sources: [Source]? = nil, timingMs: TimingMs? = nil,
        error: ErrorBody? = nil
    ) {
        self.requestId = requestId
        self.screenType = screenType
        self.cart = cart
        self.decision = decision
        self.purchaseDraft = purchaseDraft
        self.sources = sources
        self.timingMs = timingMs
        self.error = error
    }

    /// Field by field: a malformed cart or sources list still leaves the decision readable.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requestId = c.tolerant(String.self, .requestId)
        screenType = c.tolerant(ScreenType.self, .screenType)
        cart = c.tolerant(Cart.self, .cart)
        decision = c.tolerant(Decision.self, .decision)
        purchaseDraft = c.tolerant(PurchaseDraft.self, .purchaseDraft)
        sources = c.tolerant([Source].self, .sources)
        timingMs = c.tolerant(TimingMs.self, .timingMs)
        error = c.tolerant(ErrorBody.self, .error)
    }
}

extension KeyedDecodingContainer {
    /// The value, or nil when it is missing, null or the wrong shape.
    func tolerant<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

/// `common.schema.json#/$defs/coverageEntry`; also stored on `Purchase`.
struct CoverageEntry: Codable, Sendable, Equatable, Hashable {
    var type: ProtectionType
    /// yyyy-MM-dd
    var until: String
    var limitUsd: Double?
    var assumesManufacturerWarrantyMonths: Int?

    init(type: ProtectionType, until: String, limitUsd: Double? = nil, assumesManufacturerWarrantyMonths: Int? = nil) {
        self.type = type
        self.until = until
        self.limitUsd = limitUsd
        self.assumesManufacturerWarrantyMonths = assumesManufacturerWarrantyMonths
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = c.tolerant(ProtectionType.self, .type) ?? .unrecognized
        until = c.tolerant(String.self, .until) ?? ""
        limitUsd = c.tolerant(Double.self, .limitUsd)
        assumesManufacturerWarrantyMonths = c.tolerant(Int.self, .assumesManufacturerWarrantyMonths)
    }
}
