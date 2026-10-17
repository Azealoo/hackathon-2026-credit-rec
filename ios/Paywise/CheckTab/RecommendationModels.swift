import Foundation

/// Preferences are saved locally. Account confirmations and credit amounts belong to one comparison only.
struct RecommendationPreferences: Codable, Equatable, Sendable {
    var mode = "cash_first"
    var benefitType = "extended_warranty"
    var cashSacrificeBudgetMinor: Int?
    var allowLossOfExistingProtection = false

    var title: String { mode == "protection_target" ? "Prioritize protection" : "Prioritize savings" }

    var wire: RecommendationRequest.Preferences {
        .init(mode: mode, cashSacrificeBudgetMinor: cashSacrificeBudgetMinor,
              protectionTargets: mode == "protection_target" ? [.init(benefitType: benefitType,
                  minWindowDays: benefitType == "extended_warranty" ? 0 : 1,
                  minExtensionMonths: benefitType == "extended_warranty" ? 12 : 0)] : [],
              allowLossOfExistingProtection: allowLossOfExistingProtection, switchThresholdMinor: 500)
    }
}

enum RecommendationMoney {
    /// USD input: exact cents, no exponents, grouping separators, negatives, fractions of a cent, or overflow.
    static func minor(_ input: String) -> Int? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"^[0-9]+(?:\.[0-9]{1,2})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              value >= 0, value <= 10_000_000 else { return nil }
        return NSDecimalNumber(decimal: value * 100).intValue
    }

    static func text(_ minor: Int) -> String {
        NSDecimalNumber(decimal: Decimal(minor) / 100).stringValue
    }

    static func dollars(_ minor: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSDecimalNumber(decimal: Decimal(minor) / 100)) ?? "$—"
    }
}

struct RecommendationCatalog: Codable, Sendable {
    struct Product: Codable, Identifiable, Sendable {
        var id: String
        var issuer: String
        var product: String
        var categoryOptions: [String]
        var membershipBonusOptionsBps: [Int]
        var termsUrls: [String]
        var observedAt: String
        var name: String { "\(issuer) \(product)" }
    }
    var policyVersion: String
    var products: [Product]
}

struct RecommendationCardDraft: Identifiable, Equatable, Sendable {
    var id: String
    var productId: String
    var network = "unknown"
    var availableCredit = ""
    var termsConfirmed = false
    var category = "unknown"
    var foreignFeeApplies = "unknown"
    var membershipBonusBps: Int?
    var paymentTrackerConfirmed = false

    static func productId(forLegacyId id: String) -> String {
        id == "wf-active-cash" ? "wells-fargo-active-cash" : id
    }
}

struct RecommendationRequest: Codable, Sendable {
    struct Purchase: Codable, Sendable {
        var totalMinor: Int
        var currency = "USD"
        var channel = "merchant_web"
        var chargeDate: String
        var acceptedNetworks: [String]?
    }
    struct Target: Codable, Sendable {
        var benefitType: String
        var minNominalLimitMinor = 1
        var minWindowDays = 0
        var minExtensionMonths = 0
    }
    struct Preferences: Codable, Sendable {
        var mode: String
        var cashSacrificeBudgetMinor: Int?
        var protectionTargets: [Target]
        var allowLossOfExistingProtection: Bool
        var switchThresholdMinor: Int
    }
    struct Option: Codable, Sendable {
        var walletCardId: String
        var productId: String
        var paymentPath: String
        var isDefault: Bool
        var network: String?
        var active: String
        var availableCreditMinor: Int?
        var pathEligible: String
        var policyConfirmedThrough: String?
        var issuerEligiblePurchase: String
        var issuerCategory: String?
        var categoryConfirmedThrough: String?
        var membershipBonusBps: Int?
        var expectedFullRepayment: String
        var purchaseGracePeriodActive: String
        var eligiblePaymentAndTrackerConfirmed: String
        var foreignFeeApplies: String
        var checkoutFeeMinor: Int?
    }

    var requestId: String
    var purchase: Purchase
    var options: [Option]
    var preferences: Preferences

    static func build(requestId: String, amount: String, chargeDate: String,
                      cards: [RecommendationCardDraft], defaultId: String, path: String,
                      usableConfirmed: Bool, interestFreeConfirmed: Bool, noCheckoutFeesConfirmed: Bool,
                      preferences: RecommendationPreferences) -> RecommendationRequest? {
        guard let total = RecommendationMoney.minor(amount), (1...30).contains(cards.count),
              Set(cards.map(\.id)).count == cards.count,
              cards.contains(where: { $0.id == defaultId }),
              cards.allSatisfy({ $0.availableCredit.isEmpty || RecommendationMoney.minor($0.availableCredit) != nil })
        else { return nil }
        let networks = Array(Set(cards.compactMap { $0.network == "unknown" ? nil : $0.network })).sorted()
        let options = cards.map { card in
            Option(walletCardId: card.id, productId: card.productId, paymentPath: path,
                   isDefault: card.id == defaultId, network: card.network == "unknown" ? nil : card.network,
                   active: usableConfirmed ? "yes" : "unknown",
                   availableCreditMinor: RecommendationMoney.minor(card.availableCredit),
                   pathEligible: usableConfirmed ? "yes" : "unknown",
                   policyConfirmedThrough: card.termsConfirmed ? chargeDate : nil,
                   issuerEligiblePurchase: card.termsConfirmed ? "yes" : "unknown",
                   issuerCategory: card.category == "unknown" ? nil : card.category,
                   categoryConfirmedThrough: card.category == "unknown" ? nil : chargeDate,
                   membershipBonusBps: card.membershipBonusBps,
                   expectedFullRepayment: interestFreeConfirmed ? "yes" : "unknown",
                   purchaseGracePeriodActive: interestFreeConfirmed ? "yes" : "unknown",
                   eligiblePaymentAndTrackerConfirmed: card.paymentTrackerConfirmed ? "yes" : "unknown",
                   foreignFeeApplies: card.foreignFeeApplies,
                   checkoutFeeMinor: noCheckoutFeesConfirmed ? 0 : nil)
        }
        return .init(requestId: requestId, purchase: .init(totalMinor: total, chargeDate: chargeDate,
                     acceptedNetworks: usableConfirmed ? networks : nil), options: options, preferences: preferences.wire)
    }
}

struct RecommendationResult: Codable, Sendable {
    struct Selection: Codable, Sendable { var walletCardId: String; var paymentPath: String }
    struct Interval: Codable, Sendable {
        var lowMinor: Int
        var highMinor: Int
        var text: String {
            lowMinor == highMinor ? RecommendationMoney.dollars(lowMinor)
            : "\(RecommendationMoney.dollars(lowMinor)) to \(RecommendationMoney.dollars(highMinor))"
        }
    }
    struct Option: Codable, Sendable {
        var walletCardId: String
        var productId: String
        var availability: String
        var reward: Interval?
        var net: Interval?
        var missingFields: [String]
    }
    var decision: String
    var reason: String
    var selected: Selection?
    var cashDelta: Interval?
    var options: [Option]

    var title: String {
        switch decision {
        case "keep": "Keep your comparison card"
        case "switch", "recommend": "Suggested card"
        case "choice_required": "Review the tradeoff"
        default: "More information needed"
        }
    }

    var explanation: String {
        switch reason {
        case "financing_unknown": "Confirm full repayment and an active purchase grace period before comparing net value."
        case "foreign_fee_unknown": "Check whether foreign transaction fees apply to each card."
        case "account_policy_applicability": "Confirm that the linked terms apply to your account and payment method."
        case "protection_target_unverified", "protection_target_unmet": "We cannot yet confirm a card meets your protection target. The estimates below do not promise coverage or a refund."
        case "protection_comparison_incomplete_or_loss": "A higher cash estimate may change or reduce protection. Review it before switching."
        case "ranking_uncertain": "Some estimates overlap. Confirm the missing account or reward details to choose reliably."
        case "quarter_category_unknown": "The current quarterly reward category still needs verification."
        case "offer_stacking_unknown", "intro_offer_not_supported": "Your introductory offer needs a separate review before comparing net rewards."
        case "cash_sacrifice_budget_exceeded": "The protection option exceeds your allowed reduction in rewards."
        case "below_switch_threshold": "The estimated cash improvement is too small to suggest switching."
        case "cash_gain", "default_best", "best_verified_feasible_option": "Based on confirmed ordinary rewards and fees for the cards in this comparison."
        default: "Review the missing details listed with each card. Unknown amounts are not treated as zero."
        }
    }

    static func missingLabel(_ field: String) -> String {
        switch field.split(separator: ":").first.map(String.init) ?? field {
        case "active", "path_eligible", "network_acceptance": "Card and payment method availability"
        case "available_credit": "Available credit"
        case "account_policy_applicability", "issuer_eligible_purchase": "Applicable account and purchase terms"
        case "issuer_category_or_selection": "Issuer reward category or selected category"
        case "membership_bonus": "Membership rewards bonus"
        case "cap_usage", "pending_usage", "reward_period_date": "Account spending cap and posting period"
        case "eligible_payment_and_purchase_tracker": "Eligible payment and Purchase Tracker"
        case "financing_unknown": "Repayment and purchase grace period"
        case "foreign_fee_unknown": "Foreign transaction fee"
        case "checkout_fee_unknown": "Additional checkout fee"
        case "quarter_category_unknown": "Verified quarterly reward category"
        default: "Additional account or policy details"
        }
    }
}

extension PaywiseSettings {
    var recommendationPreferences: RecommendationPreferences {
        get {
            guard let data = defaults.data(forKey: Key.recommendationPreferences),
                  let value = try? JSONDecoder().decode(RecommendationPreferences.self, from: data),
                  ["cash_first", "protection_target"].contains(value.mode),
                  ["extended_warranty", "purchase_damage_theft", "return_protection"].contains(value.benefitType),
                  value.cashSacrificeBudgetMinor.map({ (0...1_000_000_000).contains($0) }) ?? true
            else { return RecommendationPreferences() }
            return value
        }
        nonmutating set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.recommendationPreferences)
        }
    }
}
