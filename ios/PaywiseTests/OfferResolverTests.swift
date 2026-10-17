import Foundation
import Testing
@testable import Paywise

/// Offers design D1–D4 on the phone: `OfferMath`, `OfferResolver` against the bundled `cards.json`, the device-only
/// `OfferStore`, the one-tap questions, and the check chain's offer adjustment. All checkouts are fake.
struct OfferMathTests {
    @Test func capLeftIsNeverNegative() {
        #expect(OfferMath.capLeft(cap: 1500, spent: 2000) == 0)
        #expect(OfferMath.capLeft(cap: 1500, spent: 1500) == 0)
        #expect(OfferMath.capLeft(cap: 1500, spent: 400) == 1100)
        #expect(OfferMath.capLeft(cap: 1500, spent: -50) == 1500)
    }

    @Test func waterfallFillsTheBestRateFirst() {
        let offers = [
            OfferMath.RateSegment(id: "three", ratePct: 3, capLeftUsd: 1000, order: 0),
            OfferMath.RateSegment(id: "five", ratePct: 5, capLeftUsd: 100, order: 1),
        ]
        let result = OfferMath.waterfall(amount: 500, publicRate: 1, offers: offers)
        #expect(result.total == 17)  // $100 × 5% + $400 × 3%
        #expect(result.extras.map(\.id) == ["five", "three"])
        #expect(result.extras.map(\.usd) == [4, 8])
    }

    @Test func pastTheCapThePublicRateTakesTheRest() {
        let q4 = OfferMath.RateSegment(id: "q4", ratePct: 5, capLeftUsd: 1500, order: 0)
        #expect(OfferMath.waterfall(amount: 2000, publicRate: 1, offers: [q4]).total == 80)  // $75 + $500 × 1%
        let usedUp = OfferMath.RateSegment(id: "q4", ratePct: 5, capLeftUsd: 0, order: 0)
        let result = OfferMath.waterfall(amount: 200, publicRate: 1, offers: [usedUp])
        #expect(result.total == 2 && result.extras.isEmpty)
    }

    @Test func tiesGoInCatalogOrder() {
        let offers = [
            OfferMath.RateSegment(id: "second", ratePct: 5, capLeftUsd: 50, order: 1),
            OfferMath.RateSegment(id: "first", ratePct: 5, capLeftUsd: 50, order: 0),
        ]
        #expect(OfferMath.waterfall(amount: 80, publicRate: 1, offers: offers).extras.map(\.id) == ["first", "second"])
    }

    @Test func centsRoundHalfUpLikeTheBackend() {
        #expect(OfferMath.cents(Decimal(string: "2.005")!) == Decimal(string: "2.01")!)
        #expect(OfferMath.cents(Decimal(string: "2.004")!) == Decimal(string: "2.00")!)
        #expect(Decimal(wire: 1499.0) == 1499)
        #expect(Decimal(wire: 22.49) == Decimal(string: "22.49")!)
    }

    @Test func monthsAddWithClamping() {
        #expect(OfferMath.day("2026-06-13", plusMonths: 6) == "2026-12-13")
        #expect(OfferMath.day("2026-08-31", plusMonths: 6) == "2027-02-28")
        #expect(OfferMath.day("2026-07-01", plusMonths: 6) == "2027-01-01")
    }
}

/// Builders for a fake checkout's response, as the backend would send it (cash = cents(amount × public rate)).
enum OfferFixtures {
    static let discover = "discover-it-student-cash-back"
    static let rise = "chase-freedom-rise"
    static let apple = "apple-card"
    static let today = "2026-10-17"
    static let catalog = CardCatalog.bundled(.main)

    static func wallet(_ ids: [String]) -> Wallet {
        let fake = ["5678", "4321", "1234"]
        return Wallet(cards: ids.enumerated().map { .init(cardId: $1, isDefault: $0 == 0, last4: fake[$0 % 3]) })
    }

    static func response(
        wallet: Wallet, amount: Double, rates: [String: Double], merchantId: String? = nil, ruleCategory: String?,
        kind: DecisionKind = .keep, reason: DecisionReason = .defaultBest, mayOverride: Bool = true,
        allowed: [String]? = nil, method: String = "card", path: PaymentPath = .savedCard
    ) -> CheckResponse {
        let ids = wallet.cards.map(\.cardId)
        let cash = rates.mapValues { OfferMath.cents(Decimal(wire: amount) * Decimal(wire: $0) / 100).double }
        let draft = { (card: String) in
            CheckResponse.PurchaseDraft(
                merchant: "Example Store", item: "Example order", category: ruleCategory ?? "general", condition: .new,
                priceUsd: amount, purchaseDate: today, cardId: card,
                coverage: [CoverageEntry(type: .purchaseProtection, until: "2027-02-14", limitUsd: 500)]
            )
        }
        let picks = allowed ?? (mayOverride ? ids : [ids[0]])
        return CheckResponse(
            screenType: .checkout,
            decision: .init(
                kind: kind, reason: reason, presentation: .island, recommendedCardId: ids[0], defaultCardId: ids[0],
                cashBestCardId: ids[0], paymentPath: path, instruction: InstructionKind.none,
                cash: .init(byCard: cash, deltaVsCashBest: 0, deltaVsDefault: 0), protectionsGained: [],
                protectionsLost: [], eligibilityNotes: [], confidence: .high,
                copy: .init(line1: "✓ Keep Apple Card ••{last4:apple-card}", line2: "Best of your 2 cards here")
            ),
            offerContext: .init(
                catalogVersion: "2026-10-16", amountUsd: amount, merchantId: merchantId, ruleCategory: ruleCategory,
                itemCategories: [ruleCategory ?? "general"], paymentPath: path, method: method,
                thresholdUsd: path == .applePay ? 3 : 5,
                publicRates: rates.mapValues { .init(ratePct: $0, status: .verified, ruleId: nil) },
                allowedCashPicks: picks,
                purchaseDraftByCard: mayOverride ? Dictionary(uniqueKeysWithValues: picks.map { ($0, draft($0)) }) : [:],
                deviceMayOverride: mayOverride
            )
        )
    }

    static func records(_ cardId: String, offer: String? = nil, answer: OfferAnswer = .yes, spent: Decimal? = 0,
                        event: String? = nil, openedOn: String? = nil) -> OfferRecords {
        var facts = CardFacts(openedOn: openedOn)
        if let offer {
            facts.offers[offer] = OfferState(answer: answer, answeredOn: "2026-10-02", activatedOn: "2026-10-02",
                                             spentTowardCapUsd: spent)
        }
        if let event { facts.events[event] = OfferState(answer: .yes, answeredOn: "2026-10-20") }
        return OfferRecords(cards: [cardId: facts])
    }

    /// A Discover cardholder at a restaurant: Apple Card default (1%), Discover 1%: a tie, so Keep.
    static func restaurant(amount: Double = 200, merchantId: String? = nil) -> (CheckResponse, Wallet) {
        let wallet = wallet([apple, discover])
        return (response(wallet: wallet, amount: amount, rates: [apple: 1, discover: 1], merchantId: merchantId,
                         ruleCategory: "dining"), wallet)
    }
}

struct OfferResolverTests {
    typealias F = OfferFixtures
    private let q4 = "discover-5pct-2026q4"

    private func resolve(_ response: CheckResponse, _ wallet: Wallet, _ records: OfferRecords,
                         today: String = F.today) -> OfferAdjustment? {
        OfferResolver.resolve(response: response, catalog: F.catalog, records: records, wallet: wallet, today: today)
    }

    @Test func bundledCatalogHasTheOffers() {
        let ids = Set(F.catalog.offers.map(\.id))
        #expect(ids.isSuperset(of: [q4, "rise-dining-3pct-new-account", "capital-one-travel-5pct", "apple-card-booking-3pct"]))
        #expect(F.catalog.events.contains { $0.id == "discover-to-capital-one-2026" })
    }

    @Test func activatedQ4SwitchesCashAtARestaurant() throws {
        let (response, wallet) = F.restaurant()
        let adjustment = try #require(resolve(response, wallet, F.records(F.discover, offer: q4)))
        let decision = adjustment.decision
        #expect(decision.kind == .switch && decision.reason == .cash)
        #expect(decision.recommendedCardId == F.discover)
        #expect(decision.cash?.byCard?[F.discover] == 10 && decision.cash?.byCard?[F.apple] == 2)
        #expect(decision.confidence == .high)
        #expect(decision.copy?.line1 == "Use Discover ••{last4:discover-it-student-cash-back}")
        #expect(decision.copy?.line2 == "$8.00 more cash back than Apple Card")
        #expect(decision.copy?.line3 == "With your Q4 5%")
        #expect(decision.copy?.instruction == "Change card to Discover ••{last4:discover-it-student-cash-back}, then place order")
        #expect(decision.instruction == .changeSavedCard && decision.presentation == .snippet)
        #expect(adjustment.purchaseDraft?.cardId == F.discover)
        #expect(adjustment.purchaseDraft?.coverage?.first?.limitUsd == 500)
        #expect(adjustment.changedDecision)
        #expect(adjustment.appliedOffers == [.init(offerId: q4, cardId: F.discover, extraUsd: 8)])
    }

    @Test func unansweredNoOrNotSureChangesNothing() {
        let (response, wallet) = F.restaurant()
        #expect(resolve(response, wallet, OfferRecords()) == nil)
        #expect(resolve(response, wallet, F.records(F.discover, offer: q4, answer: .no)) == nil)
        #expect(resolve(response, wallet, F.records(F.discover, offer: q4, answer: .notSure)) == nil)
    }

    @Test func unknownCapUseIsMediumWithNoDollarFigure() throws {
        let (response, wallet) = F.restaurant()
        let adjustment = try #require(resolve(response, wallet, F.records(F.discover, offer: q4, spent: nil)))
        #expect(adjustment.decision.confidence == .medium)
        #expect(adjustment.decision.copy?.line2 == "Likely more cash back than Apple Card")
        #expect(adjustment.purchaseDraft?.coverage?.first?.limitUsd == nil)
    }

    @Test func capPastItsLimitFallsBackToThePublicRate() throws {
        let (response, wallet) = F.restaurant(amount: 400)
        // $1,400 of $1,500 used: $100 at 5% + $300 at 1% = $8.00 vs Apple's $4.00 → +$4.00, under the $5 threshold.
        let adjustment = try #require(resolve(response, wallet, F.records(F.discover, offer: q4, spent: 1400)))
        #expect(adjustment.decision.kind == .keep && adjustment.decision.reason == .belowThreshold)
        #expect(adjustment.decision.cash?.byCard?[F.discover] == 8)
        // Past the cap (an entry larger than the cap): nothing left, nothing applied.
        #expect(resolve(response, wallet, F.records(F.discover, offer: q4, spent: 2000)) == nil)
    }

    @Test func protectionDecisionsAreNeverChanged() {
        let wallet = F.wallet([F.apple, F.discover])
        for (kind, reason) in [(DecisionKind.switch, DecisionReason.protection), (.keep, .alreadyProtected), (.keep, .itemsUnreadable)] {
            let response = F.response(wallet: wallet, amount: 200, rates: [F.apple: 1, F.discover: 1],
                                      ruleCategory: "dining", kind: kind, reason: reason, mayOverride: false)
            #expect(resolve(response, wallet, F.records(F.discover, offer: q4)) == nil)
            var lying = response  // even if a context claimed otherwise, the decision kind is checked too
            lying.offerContext?.deviceMayOverride = true
            #expect(resolve(lying, wallet, F.records(F.discover, offer: q4)) == nil)
        }
    }

    @Test func onlyCardsInAllowedCashPicksArePicked() {
        let wallet = F.wallet([F.apple, F.discover])
        let response = F.response(wallet: wallet, amount: 200, rates: [F.apple: 1, F.discover: 1],
                                  ruleCategory: "dining", allowed: [F.apple])
        let adjustment = resolve(response, wallet, F.records(F.discover, offer: q4))
        #expect(adjustment == nil || adjustment?.decision.recommendedCardId == F.apple)
    }

    @Test func doorDashAndUberEatsDontCountAsRestaurants() {
        for merchant in ["doordash", "uber-eats"] {
            let (response, wallet) = F.restaurant(merchantId: merchant)
            #expect(resolve(response, wallet, F.records(F.discover, offer: q4)) == nil, "\(merchant)")
        }
    }

    @Test func outsideTheQuarterNothingApplies() {
        let (response, wallet) = F.restaurant()
        #expect(resolve(response, wallet, F.records(F.discover, offer: q4), today: "2027-01-01") == nil)
        #expect(resolve(response, wallet, F.records(F.discover, offer: q4), today: "2026-09-30") == nil)
    }

    @Test func aContextThatDoesntMatchTheCashIsIgnored() {
        var (response, wallet) = F.restaurant()
        response.decision?.cash?.byCard?[F.discover] = 2.5
        #expect(resolve(response, wallet, F.records(F.discover, offer: q4)) == nil)
        var other = F.restaurant().0
        other.offerContext = nil  // an old replay file
        #expect(resolve(other, wallet, F.records(F.discover, offer: q4)) == nil)
    }

    @Test func capitalOneTravelWaitsForTheMove() throws {
        let wallet = F.wallet([F.apple, F.discover])
        let response = F.response(wallet: wallet, amount: 300, rates: [F.apple: 1, F.discover: 1],
                                  merchantId: "capital-one-travel", ruleCategory: "travel")
        #expect(resolve(response, wallet, OfferRecords()) == nil)
        let moved = F.records(F.discover, event: "discover-to-capital-one-2026")
        let adjustment = try #require(resolve(response, wallet, moved))
        #expect(adjustment.decision.recommendedCardId == F.discover && adjustment.decision.kind == .switch)
        #expect(adjustment.decision.confidence == .medium)  // the offer is partial
    }

    @Test func riseDiningCountsFromTheEarliestOpeningWhenTheMonthIsUnknown() throws {
        let wallet = F.wallet([F.apple, F.rise])
        let response = F.response(wallet: wallet, amount: 400, rates: [F.apple: 1, F.rise: 1.5], ruleCategory: "dining")
        let offer = "rise-dining-3pct-new-account"
        let answered = F.records(F.rise, offer: offer, spent: 0)
        let adjustment = try #require(resolve(response, wallet, answered))
        #expect(adjustment.decision.cash?.byCard?[F.rise] == 12)  // $400 × 3%
        // Unknown month: from Jun 13, 2026 (the offer's earliest), so it ends Dec 13, 2026.
        #expect(resolve(response, wallet, answered, today: "2026-12-13") == nil)
        // Opened in September: from Sep 1, so it runs to Mar 1, 2027 (and the offer itself to Mar 22).
        let september = F.records(F.rise, offer: offer, spent: 0, openedOn: "2026-09")
        #expect(resolve(response, wallet, september, today: "2026-12-13") != nil)
        #expect(resolve(response, wallet, september, today: "2027-03-01") == nil)
    }

    @Test func linkOnlyOffersAreHintsNeverCash() {
        let wallet = F.wallet([F.discover, F.apple])
        let response = F.response(wallet: wallet, amount: 500, rates: [F.discover: 1, F.apple: 2],
                                  merchantId: "booking-com", ruleCategory: "travel", reason: .belowThreshold,
                                  method: "apple_pay", path: .applePay)
        var records = OfferRecords()
        records.cards[F.apple] = CardFacts(offers: ["apple-card-booking-3pct": .init(answer: .yes, answeredOn: F.today)])
        #expect(resolve(response, wallet, records) == nil)
    }

    @Test func theDefaultsOwnOfferKeepsItWithAttribution() throws {
        let wallet = F.wallet([F.discover, F.apple])
        let response = F.response(wallet: wallet, amount: 600, rates: [F.discover: 1, F.apple: 2], ruleCategory: "dining",
                                  kind: .switch, reason: .cash)
        let adjustment = try #require(resolve(response, wallet, F.records(F.discover, offer: q4)))
        #expect(adjustment.decision.kind == .keep && adjustment.decision.reason == .defaultBest)
        #expect(adjustment.decision.copy?.line3 == "With your Q4 5%")
        #expect(adjustment.purchaseDraft == nil)
    }

    @Test func anOfferOnTheDefaultRestatesTheSameSwitchsGain() throws {
        let cfu = "chase-freedom-unlimited"
        let wallet = F.wallet([F.discover, cfu])
        let response = F.response(wallet: wallet, amount: 1000, rates: [F.discover: 1, cfu: 3], ruleCategory: "dining",
                                  kind: .switch, reason: .cash)
        var server = response
        server.decision?.recommendedCardId = cfu
        // $1,450 of the cap used: $50 at 5% + $950 at 1% = $12.00 vs Freedom's $30.00.
        let adjustment = try #require(resolve(server, wallet, F.records(F.discover, offer: q4, spent: 1450)))
        #expect(!adjustment.changedDecision && adjustment.decision.recommendedCardId == cfu)
        #expect(adjustment.decision.copy?.line2 == "$18.00 more cash back than Discover")
        #expect(adjustment.decision.copy?.line3 == nil)
    }

    @Test func sameInputsSameAnswer() {
        let (response, wallet) = F.restaurant(amount: 1234.56)
        let records = F.records(F.discover, offer: q4, spent: 321.09)
        #expect(resolve(response, wallet, records) == resolve(response, wallet, records))
    }

    @Test func deviceCopyFitsTheSnippet() throws {
        let wallet = F.wallet([F.apple, F.discover])
        for merchant in ["capital-one-entertainment", "capital-one-travel"] {
            let response = F.response(wallet: wallet, amount: 9_999.99, rates: [F.apple: 1, F.discover: 1],
                                      merchantId: merchant, ruleCategory: merchant.hasSuffix("travel") ? "travel" : "entertainment")
            let adjustment = try #require(resolve(response, wallet, F.records(F.discover, event: "discover-to-capital-one-2026")))
            let filled = CopyFill.fill(adjustment.decision.copy, wallet: wallet, ppCap: nil)
            for line in [filled.line1, filled.line2, filled.line3].compactMap({ $0 }) {
                #expect(line.count <= OfferCopy.lineMax, "\(line)")
            }
            #expect((filled.instruction ?? "").count <= OfferCopy.instructionMax)
        }
    }
}

struct OfferStoreTests {
    private func store() -> OfferStore {
        OfferStore(containerURL: FileManager.default.temporaryDirectory.appending(path: "offers-\(UUID().uuidString)"))
    }

    @Test func answersRoundTripOnTheDevice() throws {
        let store = store()
        #expect(store.load() == OfferRecords())
        let question = try #require(OfferQuestions.questions(
            wallet: OfferFixtures.wallet([OfferFixtures.apple, OfferFixtures.discover]), catalog: OfferFixtures.catalog,
            records: OfferRecords(), today: "2026-10-17"
        ).first { $0.subject == .offer(id: "discover-5pct-2026q4") })
        try OfferQuestions.answer(.yes, to: question, today: "2026-10-17", in: store)
        let state = try #require(store.load().state(cardId: OfferFixtures.discover, offerId: "discover-5pct-2026q4"))
        #expect(state.answer == .yes && state.activatedOn == "2026-10-17" && state.spentTowardCapUsd == nil)
        try OfferQuestions.setSpent(Decimal(string: "250.50"), cardId: OfferFixtures.discover,
                                    offerId: "discover-5pct-2026q4", in: store)
        #expect(store.load().state(cardId: OfferFixtures.discover, offerId: "discover-5pct-2026q4")?.spentTowardCapUsd
                == Decimal(string: "250.50"))
        try OfferQuestions.answer(.no, to: question, today: "2026-10-18", in: store)
        #expect(store.load().state(cardId: OfferFixtures.discover, offerId: "discover-5pct-2026q4")?.activatedOn == nil)
        store.removeAll()
        #expect(store.load() == OfferRecords())
    }

    @Test func questionsFollowTheWalletAndTheCalendar() {
        let wallet = OfferFixtures.wallet([OfferFixtures.apple, OfferFixtures.discover, OfferFixtures.rise])
        let before = OfferQuestions.questions(wallet: wallet, catalog: OfferFixtures.catalog, records: OfferRecords(),
                                              today: "2026-10-17")
        #expect(before.map(\.text) == ["Activated your Q4 5%?", "Opened Rise with the 3% dining offer?"])
        let rise = before[1]
        #expect(rise.openingMonths == ["2026-06", "2026-07", "2026-08", "2026-09"])
        #expect(OfferQuestions.monthLabel("2026-07") == "Jul 2026")
        let after = OfferQuestions.questions(wallet: wallet, catalog: OfferFixtures.catalog, records: OfferRecords(),
                                             today: "2026-10-19")
        #expect(after.contains { $0.text == "Is your Discover card in the Capital One app?" })
        let newYear = OfferQuestions.questions(wallet: wallet, catalog: OfferFixtures.catalog, records: OfferRecords(),
                                               today: "2027-01-01")
        #expect(!newYear.contains { $0.subject == .offer(id: "discover-5pct-2026q4") })
        #expect(OfferQuestions.questions(wallet: OfferFixtures.wallet([OfferFixtures.apple]), catalog: OfferFixtures.catalog,
                                         records: OfferRecords(), today: "2026-10-17").isEmpty)
    }
}

/// The record keeps the server's response as received; the app shows the phone's adjustment.
struct OfferAdjustmentRecordTests {
    @Test func recordOverlaysTheAdjustmentAndRoundTrips() throws {
        let (response, wallet) = OfferFixtures.restaurant()
        let adjustment = try #require(OfferResolver.resolve(
            response: response, catalog: OfferFixtures.catalog,
            records: OfferFixtures.records(OfferFixtures.discover, offer: "discover-5pct-2026q4"), wallet: wallet,
            today: OfferFixtures.today
        ))
        let json = try JSONValue(data: JSONCoding.encoder.encode(response))
        let record = CheckRecord(checkId: "5f0c0000-aaaa-4bbb-8ccc-ddddeeeeffff", createdAt: "2026-10-17T14:02:11-07:00",
                                 sentPayload: .null, response: json, filledCopy: .init(line1: "x"), replayed: false,
                                 offerAdjustment: adjustment)
        #expect(record.serverResponse.decision?.kind == .keep)
        #expect(record.parsedResponse.decision?.kind == .switch)
        #expect(record.parsedResponse.purchaseDraft?.cardId == OfferFixtures.discover)
        let decoded = try JSONDecoder().decode(CheckRecord.self, from: JSONCoding.encoder.encode(record))
        #expect(decoded == record)
        // No adjustment: the key is left out, as before offers.
        var plain = record
        plain.offerAdjustment = nil
        #expect(!String(decoding: try JSONCoding.encoder.encode(plain), as: UTF8.self).contains("offerAdjustment"))
    }

    @Test func theResponseExampleDecodesItsOfferContext() throws {
        let response = try JSONDecoder().decode(CheckResponse.self, from: Fixtures.responseExample())
        let context = try #require(response.offerContext)
        #expect(context.deviceMayOverride == false && context.allowedCashPicks == ["apple-card"])
        #expect(context.publicRates?["chase-freedom-unlimited"]?.ratePct == 1.5)
    }
}

/// The press chain with an answered offer: the request is unchanged (D1), the record keeps the server's response and
/// adds the phone's adjustment, and the snippet copy is the device's.
@MainActor
struct OfferCheckChainTests {
    @Test func anActivatedOfferChangesTheResultButNotTheRequest() async throws {
        let wallet = OfferFixtures.wallet([OfferFixtures.apple, OfferFixtures.discover])
        var response = OfferFixtures.restaurant().0
        response.requestId = "5f0c0000-aaaa-4bbb-8ccc-ddddeeeeffff"
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 200, body: try JSONCoding.encoder.encode(response))),
            wallet: wallet
        )
        try env.deps.offers.update { records in
            records = OfferFixtures.records(OfferFixtures.discover, offer: "discover-5pct-2026q4")
        }
        try await env.perform(TestEnvironment.screenshot())

        let body = String(decoding: try #require(env.requests.first), as: UTF8.self)
        for word in ["offer", "activat", "discover-5pct", "spent", "openedOn", "answer"] {
            #expect(!body.lowercased().contains(word.lowercased()), "\(word) left the phone")
        }
        let record = try #require(env.deps.checkStore.latest(now: Fixtures.demoNow))
        #expect(record.serverResponse.decision?.kind == .keep)
        #expect(record.offerAdjustment?.changedDecision == true)
        #expect(record.parsedResponse.decision?.recommendedCardId == OfferFixtures.discover)
        #expect(record.filledCopy.line1 == "Use Discover ••4321")
        #expect(record.filledCopy.line2 == "$8.00 more cash back than Apple Card")
        #expect(record.filledCopy.line3 == "With your Q4 5%")
    }

    @Test func withoutAnswersTheServerResultStands() async throws {
        let wallet = OfferFixtures.wallet([OfferFixtures.apple, OfferFixtures.discover])
        var response = OfferFixtures.restaurant().0
        response.requestId = "5f0c0000-aaaa-4bbb-8ccc-ddddeeeeffff"
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 200, body: try JSONCoding.encoder.encode(response))),
            wallet: wallet
        )
        try await env.perform(TestEnvironment.screenshot())
        let record = try #require(env.deps.checkStore.latest(now: Fixtures.demoNow))
        #expect(record.offerAdjustment == nil)
        #expect(record.filledCopy.line1 == "✓ Keep Apple Card ••5678")
    }
}
