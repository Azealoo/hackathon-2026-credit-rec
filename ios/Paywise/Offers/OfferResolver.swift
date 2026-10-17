import Foundation

/// Applies the user's catalog offers to a `/v1/check` result on the phone (offers design D1, D4).
///
/// Deterministic and free of I/O: the response's public `offerContext`, the bundled catalog, the device-only
/// `OfferRecords` and today's date in, an `OfferAdjustment` (or nil: the server's answer stands) out. Money is
/// `Decimal`, rounded to cents half-up once per card, as the backend does (SPEC §7.2 rule 1).
///
/// It only ever changes a cash decision (switch/cash, keep/default_best, keep/below_threshold, keep/method), and only
/// to a card in `allowedCashPicks`, the cards that keep every protection the default has. A protection decision,
/// keep/already_protected, items_unreadable, no_checkout or an error stays exactly as the server sent it.
enum OfferResolver {
    /// One card's cash with the user's offers applied.
    struct CardValue: Equatable, Sendable {
        var valueUsd: Decimal
        var applied: [OfferAdjustment.Applied]
        /// A number behind it leans on something unconfirmed (an unknown cap use, a partial offer): copy then states
        /// no dollar figure (§8.2).
        var medium: Bool
        /// The applied offer that added the most, for "With your {display.short}".
        var topOfferShort: String?
    }

    /// The channels a phone checkout can be: never in a store.
    static let checkChannels: Set<String> = ["online", "in_app", "any"]

    static func resolve(
        response: CheckResponse, catalog: CardCatalog, records: OfferRecords, wallet: Wallet, today: String
    ) -> OfferAdjustment? {
        guard let context = response.offerContext, context.deviceMayOverride == true,
              let decision = response.decision, let defaultId = decision.defaultCardId,
              isCashDecision(decision),
              let amountWire = context.amountUsd, let rates = context.publicRates,
              let serverCash = decision.cash?.byCard
        else { return nil }
        let amount = Decimal(wire: amountWire)

        // The public rates must reproduce the server's cash, or the context isn't this response's: apply nothing.
        var publicRates: [String: Decimal] = [:]
        for (cardId, rate) in rates {
            guard let pct = rate.ratePct, let cash = serverCash[cardId],
                  OfferMath.cents(amount * Decimal(wire: pct) / 100) == Decimal(wire: cash)
            else { return nil }
            publicRates[cardId] = Decimal(wire: pct)
        }
        let order = wallet.cards.map(\.cardId).filter { publicRates[$0] != nil }
        guard Set(order) == Set(publicRates.keys), order.contains(defaultId) else { return nil }

        var values: [String: CardValue] = [:]
        for cardId in order {
            values[cardId] = value(
                cardId: cardId, amount: amount, publicRate: publicRates[cardId]!, context: context,
                catalog: catalog, records: records, today: today
            )
        }
        guard values.values.contains(where: { !$0.applied.isEmpty }) else { return nil }

        let allowed = order.filter { (context.allowedCashPicks ?? [defaultId]).contains($0) || $0 == defaultId }
        let pick = best(of: allowed, values: values, defaultId: defaultId)
        let cashBest = best(of: order, values: values, defaultId: defaultId)
        let threshold = Decimal(wire: context.thresholdUsd ?? 5)
        let gain = values[pick]!.valueUsd - values[defaultId]!.valueUsd

        let kind: DecisionKind
        let reason: DecisionReason
        if pick != defaultId, gain >= threshold {
            (kind, reason) = (.switch, .cash)
        } else if decision.reason == .method {
            return nil  // Rule M stands: no offer earns a switch, and the server's Apple Pay advice is still right.
        } else if pick == defaultId {
            (kind, reason) = (.keep, .defaultBest)
        } else {
            (kind, reason) = (.keep, .belowThreshold)
        }
        let recommended = kind == .switch ? pick : defaultId
        let changed = kind != decision.kind || reason != decision.reason || recommended != decision.recommendedCardId
        // Nothing to show: the same decision, and no offer on either card its copy compares.
        guard changed || !values[recommended]!.applied.isEmpty || !values[defaultId]!.applied.isEmpty else { return nil }

        let statedRates = [recommended, defaultId, cashBest].compactMap { rates[$0]?.status }
        let medium = values[recommended]!.medium || values[defaultId]!.medium
            || statedRates.contains { $0 != .verified }
        let path = context.paymentPath ?? decision.paymentPath ?? .unknown
        var adjusted = decision
        adjusted.kind = kind
        adjusted.reason = reason
        adjusted.presentation = kind == .switch ? .snippet : .island
        adjusted.recommendedCardId = recommended
        adjusted.cashBestCardId = cashBest
        adjusted.instruction = kind == .switch ? OfferCopy.instructionKind(path) : InstructionKind.none
        adjusted.cash = CheckResponse.Cash(
            byCard: values.mapValues { $0.valueUsd.double },
            deltaVsCashBest: (values[recommended]!.valueUsd - values[cashBest]!.valueUsd).double,
            deltaVsDefault: (values[recommended]!.valueUsd - values[defaultId]!.valueUsd).double
        )
        adjusted.protectionsGained = []
        adjusted.protectionsLost = []
        adjusted.confidence = medium ? .medium : .high
        adjusted.copy = OfferCopy.copy(
            kind: kind, reason: reason, recommended: recommended, defaultId: defaultId, gain: gain,
            threshold: threshold, walletSize: order.count, path: path, offerShort: values[recommended]!.topOfferShort,
            verified: !medium, catalog: catalog
        )

        var draft: CheckResponse.PurchaseDraft?
        if kind == .switch, var picked = context.purchaseDraftByCard?[recommended] {
            if medium {  // §8.2: a medium answer saves no cap, as its copy shows none.
                picked.coverage = picked.coverage?.map { var entry = $0; entry.limitUsd = nil; return entry }
            }
            draft = picked
        }
        return OfferAdjustment(
            decision: adjusted, purchaseDraft: draft,
            appliedOffers: order.flatMap { values[$0]!.applied }, changedDecision: changed
        )
    }

    /// The server decisions a phone may change (the same list as `offerContext.deviceMayOverride`).
    static func isCashDecision(_ decision: CheckResponse.Decision) -> Bool {
        switch (decision.kind, decision.reason) {
        case (.switch, .cash), (.keep, .defaultBest), (.keep, .belowThreshold), (.keep, .method): true
        default: false
        }
    }

    /// The card with the most cash; ties go to the default, then to `ids` order (wallet order), as on the server.
    static func best(of ids: [String], values: [String: CardValue], defaultId: String) -> String {
        var pick = ids.contains(defaultId) ? defaultId : ids[0]
        for id in ids where values[id]!.valueUsd > values[pick]!.valueUsd {
            pick = id
        }
        return pick
    }

    // MARK: One card

    /// The card's cash here with the user's applicable offers: the rate offers fill best rate first, each up to its
    /// remaining cap (never below 0), then the next, and the card's public rate takes the rest (D4). Statement
    /// credits add on top.
    static func value(
        cardId: String, amount: Decimal, publicRate: Decimal, context: CheckResponse.OfferContext,
        catalog: CardCatalog, records: OfferRecords, today: String
    ) -> CardValue {
        var rated: [OfferMath.RateSegment] = []
        var credits: [(offer: CardCatalog.Offer, usd: Decimal)] = []
        var medium = false
        var heldGroups: Set<String> = []
        for (index, offer) in catalog.offers.enumerated() {
            guard let offerMedium = applies(offer, cardId: cardId, context: context, records: records, today: today)
            else { continue }
            if let group = offer.exclusiveGroup {
                guard !heldGroups.contains(group) else { continue }
                heldGroups.insert(group)
            }
            switch offer.reward.kind {
            case "rate":
                guard let pct = offer.reward.ratePct.map(Decimal.init(wire:)) else { continue }
                let rate = offer.reward.basis == "extra" ? publicRate + pct : pct
                guard rate > publicRate else { continue }
                var capLeft: Decimal?
                if let cap = offer.limits?.spendCapUsd.map(Decimal.init(wire:)) {
                    let spent = records.state(cardId: cardId, offerId: offer.id)?.spentTowardCapUsd
                    capLeft = OfferMath.capLeft(cap: cap, spent: spent ?? 0)
                    if spent == nil { medium = true }  // cap use unknown: "up to", no dollar figure
                }
                rated.append(.init(id: offer.id, ratePct: rate, capLeftUsd: capLeft, order: index))
                medium = medium || offerMedium
            case "statement_credit":
                guard let usd = offer.reward.amountUsd.map(Decimal.init(wire:)),
                      amount >= (offer.limits?.minSpendUsd.map(Decimal.init(wire:)) ?? 0)
                else { continue }
                credits.append((offer, usd))
                medium = medium || offerMedium
            default:
                continue  // Only rates and statement credits are cash the phone can value.
            }
        }

        let waterfall = OfferMath.waterfall(amount: amount, publicRate: publicRate, offers: rated)
        let creditTotal = credits.reduce(Decimal(0)) { $0 + $1.usd }
        var applied = waterfall.extras.map { OfferAdjustment.Applied(offerId: $0.id, cardId: cardId, extraUsd: $0.usd.double) }
        applied += credits.map { OfferAdjustment.Applied(offerId: $0.offer.id, cardId: cardId, extraUsd: $0.usd.double) }
        let top = applied.max { $0.extraUsd < $1.extraUsd }
        return CardValue(
            valueUsd: OfferMath.cents(waterfall.total + creditTotal),
            applied: applied,
            medium: applied.isEmpty ? false : medium,
            topOfferShort: top.flatMap { top in catalog.offers.first { $0.id == top.offerId }?.display.short }
        )
    }

    /// nil: the offer doesn't apply to this card at this checkout. Otherwise whether it applies at medium confidence
    /// (an unanswered question on a `whenUnknown: medium` offer, or an offer that isn't verified).
    static func applies(
        _ offer: CardCatalog.Offer, cardId: String, context: CheckResponse.OfferContext, records: OfferRecords,
        today: String
    ) -> Bool? {
        guard offer.evaluation == "device", offer.cardIds.contains(cardId), offer.reward.countsAsCash != false,
              offer.window?.contains(today) ?? true
        else { return nil }

        let match = offer.match
        if let ids = match.merchantIds {
            guard let merchantId = context.merchantId, ids.contains(merchantId) else { return nil }
        }
        if let merchantId = context.merchantId, match.excludeMerchantIds?.contains(merchantId) == true { return nil }
        if let categories = match.categories {
            if match.categoryBasis == "items" {
                let items = context.itemCategories ?? []
                guard !items.isEmpty, items.allSatisfy(categories.contains) else { return nil }
            } else {
                guard let category = context.ruleCategory, categories.contains(category) else { return nil }
            }
        }
        let methods = match.paymentMethods ?? ["any"]
        guard methods.contains("any") || methods.contains(context.method ?? "card") else { return nil }
        guard !checkChannels.isDisjoint(with: match.channels ?? ["any"]) else { return nil }

        let facts = records.facts(cardId)
        let state = facts.offers[offer.id]
        var unanswered = false
        for requirement in offer.requires {
            switch requirement.kind {
            case "activation":
                guard let state else {
                    if let deadline = requirement.deadline, today > deadline { return nil }  // too late to activate
                    unanswered = true
                    continue
                }
                guard state.answer == .yes else { return nil }
                if requirement.retroactive == false, let activatedOn = state.activatedOn, activatedOn > today {
                    return nil
                }
            case "enrollment", "targeted", "acquisition_offer":
                guard let state else { unanswered = true; continue }
                guard state.answer == .yes else { return nil }
            case "account_age":
                // Opened in a known month: from its 1st. Unknown: the earliest day the offer allows, so the window
                // ends early, never late. Neither: it can't be told, so it doesn't apply.
                let acquisition = offer.requires.first { $0.kind == "acquisition_offer" }
                guard let months = requirement.months,
                      let opened = facts.openedOn.map({ "\($0)-01" }) ?? acquisition?.openedFrom,
                      let ends = OfferMath.day(opened, plusMonths: months),
                      today < ends
                else { return nil }
            case "event":
                guard let eventId = requirement.eventId, facts.events[eventId]?.answer == .yes else { return nil }
            default:
                return nil  // link_or_portal (a hint) or a kind this build doesn't know: never applied
            }
        }
        if unanswered && offer.whenUnknown != "medium" { return nil }
        return unanswered || offer.status != .verified
    }
}

/// The money math, separate so it can be tested on its own.
enum OfferMath {
    struct RateSegment: Equatable, Sendable {
        var id: String
        /// The total rate on the spend this offer covers.
        var ratePct: Decimal
        /// nil: no cap.
        var capLeftUsd: Decimal?
        /// Catalog order, for ties.
        var order: Int
    }

    /// Spend left under a cap: never below 0, even when the user's entry is past the cap.
    static func capLeft(cap: Decimal, spent: Decimal) -> Decimal {
        max(0, cap - max(0, spent))
    }

    /// Best rate first (ties in catalog order): each offer earns its rate on up to its cap left of what remains,
    /// then the next; the public rate earns on the rest. `total` is unrounded; `extras` is what each offer added over
    /// the public rate, in cents.
    static func waterfall(amount: Decimal, publicRate: Decimal, offers: [RateSegment])
        -> (total: Decimal, extras: [(id: String, usd: Decimal)]) {
        var remaining = max(0, amount)
        var total = Decimal(0)
        var extras: [(id: String, usd: Decimal)] = []
        for offer in offers.sorted(by: { ($0.ratePct, -$0.order) > ($1.ratePct, -$1.order) }) {
            guard remaining > 0 else { break }
            let take = min(remaining, offer.capLeftUsd ?? remaining)
            guard take > 0 else { continue }
            total += take * offer.ratePct / 100
            extras.append((offer.id, cents(take * (offer.ratePct - publicRate) / 100)))
            remaining -= take
        }
        total += remaining * publicRate / 100
        return (total, extras)
    }

    /// Half-up to cents (the backend's ROUND_HALF_UP).
    static func cents(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }

    /// yyyy-MM-dd plus whole months, clamped to the month's last day (Jan 31 + 1 month = Feb 28).
    static func day(_ day: String, plusMonths months: Int) -> String? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let index = parts[0] * 12 + (parts[1] - 1) + months
        let (year, month) = (index / 12, index % 12 + 1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let length = calendar.range(of: .day, in: .month, for: first)?.count
        else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, min(parts[2], length))
    }
}

extension Decimal {
    /// A wire number through its shortest form (1499.0 → 1499, 1.5 → 1.5), as the backend's `dec()` does, so binary
    /// floating point never leaks into money.
    init(wire value: Double) {
        self = Decimal(string: "\(value)", locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(value)
    }

    var double: Double { NSDecimalNumber(decimal: self).doubleValue }
}

/// Device copy for the decisions the resolver makes, in the backend's words (backend/app/copy.py, SPEC §6.3), with
/// `{last4:<cardId>}` placeholders `CopyFill` fills. Line 3 names the offer ("With your Q4 5%"), so Paywise never
/// claims more than the user told it.
enum OfferCopy {
    static let lineMax = 44
    static let instructionMax = 48

    static func copy(
        kind: DecisionKind, reason: DecisionReason, recommended: String, defaultId: String, gain: Decimal,
        threshold: Decimal, walletSize: Int, path: PaymentPath, offerShort: String?, verified: Bool,
        catalog: CardCatalog
    ) -> CheckResponse.Copy {
        let name = catalog.shortName(recommended) ?? recommended
        let attribution: String? = offerShort.map { "With your \($0)" }
        let line3: String? = attribution.flatMap { $0.count <= lineMax ? $0 : nil }
        switch (kind, reason) {
        case (.switch, _):
            let defaultName = catalog.shortName(defaultId) ?? defaultId
            let line2 = verified
                ? "\(usd(gain, cents: true)) more cash back than \(defaultName)"
                : "Likely more cash back than \(defaultName)"
            return .init(
                line1: "Use \(name) ••{last4:\(recommended)}", line2: line2, line3: line3,
                instruction: instruction(card: catalog.card(recommended), cardId: recommended, path: path),
                primaryButton: "Paying with \(name)"
            )
        case (_, .defaultBest):
            return .init(
                line1: "✓ Keep \(name) ••{last4:\(recommended)}",
                line2: walletSize > 1 ? "Best of your \(walletSize) cards here" : "Your only card here",
                line3: line3
            )
        default:
            return .init(
                line1: "✓ Keep \(name) ••{last4:\(recommended)}", line2: "Switching gains under \(usd(threshold)) here"
            )
        }
    }

    static func instructionKind(_ path: PaymentPath) -> InstructionKind {
        switch path {
        case .applePay: .applePaySwipe
        case .savedCard: .changeSavedCard
        case .cardForm: .enterCard
        case .unknown: InstructionKind.none
        }
    }

    /// How to pay with the picked card on this checkout (§5.3), the first option that fits 48 characters.
    static func instruction(card: CardCatalog.Card?, cardId: String, path: PaymentPath) -> String {
        let net = networkName(card?.network)
        let l4 = "{last4:\(cardId)}"
        let options: [String] = switch path {
        case .applePay: ["In Apple Pay, swipe to this card"]
        case .savedCard: ["Change card to \(net) ••\(l4), then place order", "Switch to \(net) ••\(l4), then place order",
                          "Change card to \(net) ••\(l4)"]
        case .cardForm: ["Enter your \(net) ••\(l4), then place order", "Enter your \(net) ••\(l4), then pay"]
        case .unknown: ["Pay with your \(net) ••\(l4) instead", "Pay with \(net) ••\(l4)"]
        }
        return options.first { filledLength($0) <= instructionMax } ?? options[options.count - 1]
    }

    static func networkName(_ network: CardNetwork?) -> String {
        switch network {
        case .visa: "Visa"
        case .mastercard: "Mastercard"
        case .discover: "Discover"
        case .amex: "Amex"
        default: "card"
        }
    }

    /// Length once a 4-digit last 4 fills every placeholder.
    static func filledLength(_ text: String) -> Int {
        text.replacingOccurrences(of: #"\{last4:[a-z0-9-]+\}"#, with: "0000", options: .regularExpression).count
    }

    /// "$8.00" with `cents`, else "$5" for whole dollars (backend `usd`).
    static func usd(_ amount: Decimal, cents: Bool = false) -> String {
        let digits = cents || amount != amount.rounded0 ? 2 : 0
        return amount.double.formatted(
            .currency(code: "USD").locale(Locale(identifier: "en_US")).precision(.fractionLength(digits))
        )
    }
}

private extension Decimal {
    var rounded0: Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .plain)
        return result
    }
}
