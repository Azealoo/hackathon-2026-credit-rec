import AppIntents
import Foundation
import Testing
@testable import Paywise

// The app shell (SPEC §5.1, §5.4, §5.5, §9.1, §10, §15.7 steps 11, 12a, 12d, 14).

/// The demo laptop as a saved purchase (from contracts/check-record.example.json's purchaseDraft; fake data).
private func laptopPurchase(status: Purchase.Status = .planned, id: String = "p_test") throws -> PurchaseSnapshot {
    let draft = try #require(try Fixtures.recordExample().parsedResponse.purchaseDraft)
    return PurchaseSnapshot(
        id: id, checkId: "5f0c0000-aaaa-4bbb-8ccc-ddddeeeeffff", status: status,
        merchant: try #require(draft.merchant), item: try #require(draft.item), category: draft.category ?? "general",
        condition: draft.condition?.rawValue ?? "unknown", priceUsd: try #require(draft.priceUsd),
        purchaseDate: try #require(draft.purchaseDate), cardId: try #require(draft.cardId), coverage: draft.coverage ?? []
    )
}

/// §15.7 step 12a: the Purchases row, word for word.
struct PurchaseLineTests {
    @Test func step12aLineWordForWord() throws {
        let line = PurchaseText.line(try laptopPurchase(), wallet: .demo3Card, catalog: .bundled())
        #expect(line == "Aero 14 · Freedom ••1234 · Planned · theft & damage up to $500 to Feb 14, 2027 · warranty year to Oct 17, 2028")
    }

    @Test func confirmedAndNoStoredLast4() throws {
        let wallet = Wallet(cards: [.init(cardId: "chase-freedom-unlimited", isDefault: true, last4: nil)])
        let line = PurchaseText.line(try laptopPurchase(status: .confirmed), wallet: wallet, catalog: .bundled())
        #expect(line == "Aero 14 · Freedom · Confirmed · theft & damage up to $500 to Feb 14, 2027 · warranty year to Oct 17, 2028")
    }

    @Test func noCoverageDropsThoseParts() throws {
        var purchase = try laptopPurchase()
        purchase.coverage = []
        purchase.cardId = "apple-card"
        #expect(PurchaseText.line(purchase, wallet: .demo3Card, catalog: .bundled()) == "Aero 14 · Apple Card ••5678 · Planned")
    }

    @Test func detailLinesUseTheSavedSnippetWords() throws {
        let purchase = try laptopPurchase()
        #expect(PurchaseText.coverageLines(purchase) == [
            "Theft & damage cover up to $500 to Feb 14, 2027",
            "Extra warranty year to Oct 17, 2028*",
        ])
        #expect(PurchaseText.warrantyFootnote(purchase) == "*If the maker's warranty is 1 year.")
        #expect(PurchaseText.price(1499) == "$1,499.00")
    }
}

/// R16: the phone maps backend failures to §6.3 *Couldn't check* lines and never shows the server's error copy.
@MainActor
struct BackendErrorCopyTests {
    nonisolated static let privacyRejected = Data("""
    {"requestId":"5f0c0000-aaaa-4bbb-8ccc-ddddeeeeffff","decision":{"kind":"error","reason":"error","presentation":"island",\
    "copy":{"line1":"Couldn't check this time","line2":"Card number found, so nothing was read"}},\
    "error":{"code":"privacy_rejected","message":"The request has a run of 12 or more digits."}}
    """.utf8)
    nonisolated static let badRequest = Data(#"{"error":{"code":"bad_request","message":"Unknown card id(s): x"}}"#.utf8)

    @Test(arguments: [
        (400, BackendErrorCopyTests.privacyRejected, APIErrorCode.privacyRejected),
        (400, BackendErrorCopyTests.badRequest, APIErrorCode.badRequest),
        (429, Data("{}".utf8), APIErrorCode.badRequest),
    ])
    func refusedRequestShowsSomethingWentWrong(status: Int, body: Data, code: APIErrorCode) async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: status, body: body)),
            replayEnabled: true
        )
        try await env.perform(TestEnvironment.screenshot())

        let alert = try #require(await env.island.alerts.first)
        #expect(alert.line1 == "Couldn't check this time")
        #expect(alert.line2 == "Something went wrong · press again")
        #expect(alert.phase == .error)
        let record = try #require(env.deps.checkStore.latest(now: Fixtures.demoNow))
        #expect(record.replayed == false, "a request the server refused is never replayed")
        #expect(record.parsedResponse.error?.code == code)
        #expect(record.filledCopy.line2 == "Something went wrong · press again")
    }

    @Test func serverErrorStillSaysNoConnection() async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 503, body: Data("{}".utf8))),
            replayEnabled: false
        )
        try await env.perform(TestEnvironment.screenshot())
        let alert = try #require(await env.island.alerts.first)
        #expect(alert.line1 == "Couldn't check this time")
        #expect(alert.line2 == "No connection · press again")
    }

    /// The backend's real 500 bodies (main.py `_error(500, …)` → middleware.error_body): the §15.5 error shape with
    /// decision.kind "error". §6.3 lists a 5xx under *Couldn't check* with "No connection · press again", so R16's
    /// "Something went wrong" (4xx only) must not apply.
    nonisolated static func serverErrorShape(_ code: String, _ message: String) -> Data {
        Data("""
        {"requestId":"5f0c0000-aaaa-4bbb-8ccc-ddddeeeeffff","decision":{"kind":"error","reason":"error",\
        "presentation":"island","copy":{"line1":"Couldn't check this time","line2":"Something went wrong · press again",\
        "line3":null,"instruction":null,"primaryButton":null}},"error":{"code":"\(code)","message":"\(message)"}}
        """.utf8)
    }

    @Test(arguments: [
        BackendErrorCopyTests.serverErrorShape("server_error", "Something went wrong on our side."),
        BackendErrorCopyTests.serverErrorShape("parse_failed", "Couldn't read this screen."),
    ])
    func serverErrorShapeOn500SaysNoConnection(body: Data) async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 500, body: body)),
            replayEnabled: false
        )
        try await env.perform(TestEnvironment.screenshot())
        let alert = try #require(await env.island.alerts.first)
        #expect(alert.line1 == "Couldn't check this time")
        #expect(alert.line2 == "No connection · press again")
        let record = try #require(env.deps.checkStore.latest(now: Fixtures.demoNow))
        #expect(record.filledCopy.line2 == "No connection · press again")
        #expect(record.parsedResponse.error?.code == .serverError)
    }

    @Test func serverErrorShapeOn500Replays() async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(
                status: 500, body: Self.serverErrorShape("server_error", "Something went wrong on our side.")
            )),
            replayEnabled: true
        )
        try await env.perform(TestEnvironment.screenshot())
        let record = try #require(env.deps.checkStore.latest(now: Fixtures.demoNow))
        #expect(record.replayed, "a 5xx is a failed check, so the bundled replay answers")
        #expect(record.parsedResponse.decision?.kind == .switch)
    }

    /// "Pretend today is…" moves the purchase date the backend computes coverage from.
    @Test func dateOverrideIsTheClientDate() async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample()))
        )
        env.deps.settings.dateOverrideEnabled = true
        env.deps.settings.dateOverrideValue = "2027-12-18"
        try await env.perform(TestEnvironment.screenshot())
        let body = try #require(env.requests.first)
        #expect(try JSONDecoder().decode(CheckRequest.self, from: body).clientDate == "2027-12-18")
    }
}

/// "Check a screenshot" in the app: the intent's pipeline, shown in the app, saved through the intent's save path.
@MainActor
struct InAppCheckTests {
    @Test func switchResultSavesOncePerDoubleTapAndShowsSent() async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample()))
        )
        let check = InAppCheck(deps: env.deps)
        await check.run(imageData: Data([0x89]))

        let record = try #require(check.record)
        #expect(record.filledCopy.line1 == "Use Freedom ••1234")
        #expect(record.view == .result)
        // The answer shows in the app: no Live Activity for an in-app check.
        #expect(await env.island.events.isEmpty)

        // [Paying with Freedom] twice, racing: one planned purchase, and the view reloads to Saved.
        async let first: Void = check.save()
        async let second: Void = check.save()
        _ = await (first, second)
        let purchases = try await env.deps.purchases.store().all()
        #expect(purchases.count == 1)
        #expect(purchases.first?.status == .planned)
        #expect(check.record?.view == .saved)
        #expect(check.record?.savedPurchaseId == purchases.first?.id)

        await check.showSent()
        #expect(check.record?.view == .sent)
    }

    @Test func noCheckoutOnDeviceShowsTheIslandLines() async throws {
        let env = TestEnvironment(
            reading: .notCheckout,
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample()))
        )
        let check = InAppCheck(deps: env.deps)
        await check.run(imageData: Data([0x89]))
        guard case .message(let state) = check.phase else {
            Issue.record("expected the on-device No checkout lines, got \(check.phase)")
            return
        }
        #expect(state.line1 == "No checkout total found")
        #expect(state.line2 == "Nothing left your phone")
        #expect(state.line3 == "Scroll to the total and press again")
        #expect(env.requests.isEmpty)
    }

    @Test func couldntCheckShowsTheRecordInTheApp() async throws {
        let env = TestEnvironment(reading: try Fixtures.laptopReading(), route: .init(behavior: .fail(.notConnectedToInternet)))
        let check = InAppCheck(deps: env.deps)
        await check.run(imageData: Data([0x89]))
        let record = try #require(check.record)
        #expect(record.filledCopy.line1 == "Couldn't check this time")
        #expect(record.filledCopy.line2 == "No connection · press again")
        #expect(!CheckResultView.showsSaveButton(record, catalog: .bundled()))
    }

    /// Only a Switch or Keep-protected result shows [Paying with …]; then "Check a screenshot" stays secondary.
    @Test func onlyASavableResultShowsThePrimarySave() throws {
        let catalog = CardCatalog.bundled()
        let switchRecord = try #require(CheckRecord.preview(view: .result))
        #expect(CheckResultView.showsSaveButton(switchRecord, catalog: catalog))
        #expect(!CheckResultView.showsSaveButton(try #require(CheckRecord.preview(view: .saved)), catalog: catalog))
        for demo in CheckTabDemo.allCases {
            let phase = try #require(demo.phase(catalog: catalog), "\(demo)")
            if case .record(let record) = phase {
                #expect(!CheckResultView.showsSaveButton(record, catalog: catalog), "\(demo)")
            }
        }
    }

    /// `-checkState` (screenshots) shows the §6.3 lines for each island answer on the demo wallet.
    @Test func checkStatesUseTheSpecCopy() throws {
        let catalog = CardCatalog.bundled()
        let expected: [CheckTabDemo: (String, String)] = [
            .keepDefault: ("✓ Keep Apple Card ••5678", "Best of your 3 cards here"),
            .keepMethod: ("✓ Apple Card: use Apple Pay", "3% ($5.40) with Apple Pay vs 1% typed"),
            .keepItemsUnreadable: ("✓ Keep Apple Card ••5678", "Couldn't read the items, so no switch"),
            .noCheckoutOnDevice: ("No checkout total found", "Nothing left your phone"),
            .noCheckoutFromBackend: ("No checkout total found", "Scroll to the total and press again"),
            .alreadyPaid: ("Already paid?", "Press on the checkout, before you pay"),
            .couldntCheck: ("Couldn't check this time", "No connection · press again"),
            .tookTooLong: ("Couldn't check this time", "Took too long · press again"),
        ]
        #expect(Set(expected.keys) == Set(CheckTabDemo.allCases))
        for (demo, lines) in expected {
            switch try #require(demo.phase(catalog: catalog), "\(demo)") {
            case .record(let record):
                #expect(record.filledCopy.line1 == lines.0, "\(demo)")
                #expect(record.filledCopy.line2 == lines.1, "\(demo)")
            case .message(let state):
                #expect(state.line1 == lines.0, "\(demo)")
                #expect(state.line2 == lines.1, "\(demo)")
            default:
                Issue.record("\(demo): no answer")
            }
        }
    }
}

/// §5.5 claim input (§15.7 step 12d).
@MainActor
struct ClaimModelTests {
    private func model(
        _ env: TestEnvironment, status: Purchase.Status = .planned, purchase: PurchaseSnapshot? = nil
    ) throws -> ClaimModel {
        let model = ClaimModel(purchase: try purchase ?? laptopPurchase(status: status), deps: env.deps, wallet: .demo3Card)
        model.classifyDelay = .zero
        return model
    }

    /// A purchase saved through `SavePurchaseIntent`'s path, as the app has it.
    private func savedPurchase(_ env: TestEnvironment) async throws -> (PurchasesModel, PurchaseSnapshot) {
        try env.deps.checkStore.write(try Fixtures.recordExample(), now: Fixtures.demoNow)
        _ = try await env.deps.purchases.store().savePlanned(
            checkId: "5f0c0000-aaaa-4bbb-8ccc-ddddeeeeffff", checkStore: env.deps.checkStore
        )
        let purchases = PurchasesModel(deps: env.deps)
        await purchases.reload()
        return (purchases, try #require(purchases.purchases.first))
    }

    @Test func questionNamesTheCardAndDay() throws {
        let env = TestEnvironment(reading: .laptopCheckout)
        #expect(try model(env).paidQuestion == "Did you pay with Freedom ••1234 on Oct 17?")
    }

    @Test func yesConfirmsThePurchase() async throws {
        let env = TestEnvironment(reading: .laptopCheckout)
        let (purchases, purchase) = try await savedPurchase(env)
        #expect(purchase.status == .planned)
        let model = try model(env, purchase: purchase)
        await model.answerYes(purchases)
        #expect(try await env.deps.purchases.store().purchase(id: purchase.id)?.status == .confirmed)
        #expect(model.verdictRequest().purchase.status == "confirmed")
    }

    @Test func anotherCardConfirmsWithThatCard() async throws {
        let env = TestEnvironment(reading: .laptopCheckout)
        let (purchases, purchase) = try await savedPurchase(env)
        let model = try model(env, purchase: purchase)
        #expect(model.otherCards == ["apple-card", "wf-active-cash"])
        model.answerOtherCard("wf-active-cash")
        // Nothing is saved until [Check].
        #expect(try await env.deps.purchases.store().purchase(id: purchase.id)?.cardId == "chase-freedom-unlimited")
        model.warranty = .oneYear
        model.description = "It stopped turning on"
        model.pick(.failure)
        #expect(await model.prepareVerdict(purchases) != nil)
        let stored = try #require(try await env.deps.purchases.store().purchase(id: purchase.id))
        #expect(stored.status == .confirmed)
        #expect(stored.cardId == "wf-active-cash")
        #expect(stored.coverage.isEmpty)
        #expect(stored.manufacturerWarrantyMonths == 12)
        #expect(model.verdictRequest().purchase.cardId == "wf-active-cash")
    }

    @Test(arguments: [
        (WarrantyAnswer.oneYear, 12, "user"),
        (WarrantyAnswer.twoYears, 24, "user"),
        (WarrantyAnswer.unknown, 12, "assumed"),
    ])
    func makersWarranty(answer: WarrantyAnswer, months: Int, source: String) throws {
        let env = TestEnvironment(reading: .laptopCheckout)
        let model = try model(env)
        model.warranty = answer
        let request = model.verdictRequest()
        #expect(request.purchase.manufacturerWarrantyMonths == months)
        #expect(request.purchase.manufacturerWarrantySource == source)
    }

    /// The [Check] body: every contract key, the user's chip as user_confirmed, asOf and the incident on "today".
    @Test func verdictRequestMatchesTheContract() throws {
        let env = TestEnvironment(reading: .laptopCheckout)
        env.deps.settings.dateOverrideEnabled = true
        env.deps.settings.dateOverrideValue = "2027-12-18"
        let model = try model(env, status: .confirmed)
        model.paidWith = .full
        model.warranty = .oneYear
        model.description = "Lines across the screen. Never dropped."
        model.pick(.failure)
        #expect(model.canCheck)

        let body = try model.verdictRequest().body()
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(object.keys) == ["purchase", "incident", "asOf"])
        #expect(object["asOf"] as? String == "2027-12-18")
        let purchase = try #require(object["purchase"] as? [String: Any])
        #expect(Set(purchase.keys) == [
            "cardId", "merchant", "item", "category", "condition", "priceUsd", "purchaseDate", "status",
            "manufacturerWarrantyMonths", "manufacturerWarrantySource", "paidWith",
        ])
        #expect(purchase["paidWith"] as? String == "card_full")
        #expect(purchase["status"] as? String == "confirmed")
        #expect(purchase["purchaseDate"] as? String == "2026-10-17")
        let incident = try #require(object["incident"] as? [String: Any])
        #expect(incident["date"] as? String == "2027-12-18", "the incident date defaults to today (the override)")
        #expect(incident["description"] as? String == "Lines across the screen. Never dropped.")
        #expect(incident["cause"] as? String == "failure")
        #expect(incident["causeSource"] as? String == "user_confirmed")
        #expect(PrivacyGuard.isSendable(body))
    }

    // MARK: Whole price on the card (§5.5 payout cap)

    /// (answer, amount typed, paidWith, amountOnCardUsd)
    nonisolated static let paidWithCases: [(PaidWithAnswer?, String, String, Double?)] = [
        (nil, "", "unknown", nil),
        (.full, "", "card_full", nil),
        (.unknown, "", "unknown", nil),
        (.partial, "", "card_partial", nil),
        (.partial, "1000", "card_partial", 1000.0),
        (.partial, "$1,000.50", "card_partial", 1000.5),
        (.partial, " 999.9 ", "card_partial", 999.9),
        // An amount the field refuses is never sent; Check stays off (below).
        (.partial, "0", "card_partial", nil),
        (.partial, "1499", "card_partial", nil),
        (.partial, "abc", "card_partial", nil),
        // Typed, then the answer changed: the amount isn't sent.
        (.full, "1000", "card_full", nil),
        (.unknown, "1000", "unknown", nil),
    ]

    @Test(arguments: paidWithCases)
    func paidWithMapping(answer: PaidWithAnswer?, amount: String, paidWith: String, amountOnCard: Double?) throws {
        let env = TestEnvironment(reading: .laptopCheckout)
        let model = try model(env, status: .confirmed)
        model.paidWith = answer
        model.amountOnCardText = amount
        let purchase = model.verdictRequest().purchase
        #expect(purchase.paidWith == paidWith)
        #expect(purchase.amountOnCardUsd == amountOnCard)
    }

    @Test(arguments: [
        ("", true), ("1000", true), ("1,498.99", true), ("0.01", true),
        ("0", false), ("1499", false), ("1,499.00", false), ("2000", false), ("12.345", false), ("1.2.3", false), ("abc", false),
    ])
    func partialAmountGatesCheck(amount: String, canCheck: Bool) throws {
        let env = TestEnvironment(reading: .laptopCheckout)
        let model = try model(env, status: .confirmed)
        model.warranty = .oneYear
        model.description = "Lines across the screen. Never dropped."
        model.pick(.failure)
        #expect(!model.canCheck, "the question needs an answer")
        model.paidWith = .partial
        model.amountOnCardText = amount
        #expect(model.canCheck == canCheck)
        #expect(model.amountOnCardIsValid == canCheck)
        #expect((model.amountOnCardHint == nil) == canCheck)
        if !canCheck { #expect(model.amountOnCardHint == "Enter an amount less than $1,499.00.") }
        // The other answers ignore what was typed.
        model.paidWith = .full
        #expect(model.canCheck)
        #expect(model.amountOnCardHint == nil)
    }

    @Test(arguments: [
        ("1000", 100_000), ("$1,000.50", 100_050), ("999.9", 99_990), ("1.", 100), ("0.05", 5), (" 18 ", 1_800),
    ])
    func amountParses(text: String, cents: Int) {
        #expect(PaidWithAnswer.cents(text) == cents)
    }

    @Test(arguments: ["", " ", "$", ".", ".5", "abc", "12.345", "1.2.3", "-5", "1e3", "1234567890"])
    func amountRejects(text: String) {
        #expect(PaidWithAnswer.cents(text) == nil)
    }

    /// Case 12's purchase on the wire: card_partial with the part on the card; the other answers leave the key out.
    @Test func partialPaymentBodyMatchesCase12() throws {
        let env = TestEnvironment(reading: .laptopCheckout)
        env.deps.settings.dateOverrideEnabled = true
        env.deps.settings.dateOverrideValue = "2027-12-18"
        let model = try model(env, status: .confirmed)
        model.paidWith = .partial
        model.amountOnCardText = "1000"
        model.warranty = .oneYear
        model.description = "Lines across the screen. Never dropped."
        model.pick(.failure)
        #expect(model.canCheck)

        let body = try model.verdictRequest().body()
        #expect(PrivacyGuard.isSendable(body))
        let purchase = try #require(
            (try JSONSerialization.jsonObject(with: body) as? [String: Any])?["purchase"] as? [String: Any]
        )
        #expect(purchase["paidWith"] as? String == "card_partial")
        #expect(purchase["amountOnCardUsd"] as? Double == 1000)

        let case12 = try #require(try Self.coverageCase(12)["purchase"] as? [String: Any])
        for key in ["cardId", "category", "condition", "priceUsd", "purchaseDate", "status",
                    "manufacturerWarrantyMonths", "manufacturerWarrantySource", "paidWith", "amountOnCardUsd"] {
            #expect("\(purchase[key] ?? "missing")" == "\(case12[key] ?? "missing")", "\(key)")
        }
        #expect(Set(purchase.keys) == Set(case12.keys))

        for answer in [PaidWithAnswer.full, .unknown] {
            model.paidWith = answer
            let other = try #require(
                (try JSONSerialization.jsonObject(with: try model.verdictRequest().body()) as? [String: Any])?["purchase"]
                    as? [String: Any]
            )
            #expect(other["paidWith"] as? String == answer.rawValue)
            #expect(other["amountOnCardUsd"] == nil, "\(answer): no amountOnCardUsd key")
        }
    }

    /// The classification request carries the answer too (unanswered: unknown).
    @Test func classificationSendsTheAnswer() async throws {
        let reply = Data(#"{"incident":{"cause":"failure","causeSource":"llm"}}"#.utf8)
        let env = TestEnvironment(reading: .laptopCheckout, route: .init(behavior: .respond(status: 200, body: reply)))
        let model = try model(env)
        model.description = "Lines across the screen. Never dropped."
        await model.classify(model.trimmedDescription)
        model.paidWith = .partial
        model.amountOnCardText = "1000"
        model.description = "Lines across the screen, never dropped."
        await model.classify(model.trimmedDescription)
        #expect(env.requests.count == 2)
        let purchases = try env.requests.map {
            try #require((try JSONSerialization.jsonObject(with: $0) as? [String: Any])?["purchase"] as? [String: Any])
        }
        #expect(purchases[0]["paidWith"] as? String == "unknown")
        #expect(purchases[0]["amountOnCardUsd"] == nil)
        #expect(purchases[1]["paidWith"] as? String == "card_partial")
        #expect(purchases[1]["amountOnCardUsd"] as? Double == 1000)
    }

    /// `fixtures/coverage_cases.json` by id.
    private static func coverageCase(_ id: Int) throws -> [String: Any] {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "fixtures/coverage_cases.json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let cases = (json as? [[String: Any]]) ?? ((json as? [String: Any])?["cases"] as? [[String: Any]]) ?? []
        return try #require(cases.first { $0["id"] as? Int == id })
    }

    /// A purchase dated after today (saved while "Pretend today is…" was later, then turned off or moved back): the
    /// claim's today and incident date start at the purchase date, so the body is one the backend accepts
    /// (purchaseDate ≤ incident.date ≤ asOf) instead of a 400 on every check.
    @Test func aPurchaseDatedAfterTodayStillGivesAValidRequest() throws {
        let env = TestEnvironment(reading: .laptopCheckout)
        env.deps.settings.dateOverrideEnabled = true
        env.deps.settings.dateOverrideValue = "2026-01-05"
        let purchase = try laptopPurchase(status: .confirmed)
        #expect(purchase.purchaseDate == "2026-10-17")
        let model = try model(env, purchase: purchase)
        #expect(model.today == "2026-10-17")
        #expect(model.incidentRange.lowerBound == model.incidentRange.upperBound)
        #expect(Day.string(model.incidentRange.upperBound, timeZone: env.deps.timeZone) == "2026-10-17")
        let request = model.verdictRequest()
        #expect(request.asOf == "2026-10-17")
        #expect(request.incident.date == "2026-10-17")
        #expect(request.purchase.purchaseDate <= request.incident.date && request.incident.date <= request.asOf)
    }

    @Test func todayBeforeAnOverrideIsUnchangedForAnEarlierPurchase() throws {
        let env = TestEnvironment(reading: .laptopCheckout)
        env.deps.settings.dateOverrideEnabled = true
        env.deps.settings.dateOverrideValue = "2027-12-18"
        let model = try model(env, status: .confirmed)
        #expect(model.today == "2027-12-18")
        #expect(Day.string(model.incidentRange.lowerBound, timeZone: env.deps.timeZone) == "2026-10-17")
    }

    @Test func classificationPreselectsTheChip() async throws {
        let reply = Data(#"{"verdict":"may_be_eligible","incident":{"cause":"accidental_damage","causeSource":"llm"}}"#.utf8)
        let env = TestEnvironment(reading: .laptopCheckout, route: .init(behavior: .respond(status: 200, body: reply)))
        let model = try model(env)
        model.description = "Cracked it when I dropped it"
        await model.classify(model.trimmedDescription)
        #expect(model.cause == .accidentalDamage)
        #expect(model.suggestedCause == .accidentalDamage)

        // The classification request leaves the cause to the server.
        let body = try #require(env.requests.first)
        let incident = try #require((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["incident"] as? [String: Any])
        #expect(incident["cause"] is NSNull)
        #expect(incident["causeSource"] is NSNull)
    }

    @Test func classificationWithoutACauseLeavesTheChips() async throws {
        let reply = Data(#"{"verdict":"may_be_eligible","benefit":"extended_warranty"}"#.utf8)
        let env = TestEnvironment(reading: .laptopCheckout, route: .init(behavior: .respond(status: 200, body: reply)))
        let model = try model(env)
        model.description = "Lines across the screen. Never dropped."
        await model.classify(model.trimmedDescription)
        #expect(model.cause == nil)
        #expect(!model.canCheck)
    }

    @Test func theUsersChipWins() async throws {
        let reply = Data(#"{"incident":{"cause":"theft"}}"#.utf8)
        let env = TestEnvironment(reading: .laptopCheckout, route: .init(behavior: .respond(status: 200, body: reply)))
        let model = try model(env)
        model.description = "It stopped turning on"
        model.pick(.failure)
        await model.classify(model.trimmedDescription)
        #expect(model.cause == .failure)
    }

    @Test func aLongNumberIsNeverSent() async throws {
        let env = TestEnvironment(reading: .laptopCheckout, route: .init(behavior: .respond(status: 200, body: Data("{}".utf8))))
        let (purchases, purchase) = try await savedPurchase(env)
        let model = try model(env, purchase: purchase)
        await model.answerYes(purchases)
        model.warranty = .oneYear
        model.description = "Serial 123456789012 stopped working"
        await model.classify(model.trimmedDescription)
        model.pick(.failure)
        #expect(await model.prepareVerdict(purchases) == nil)
        #expect(model.hasLongNumber)
        #expect(env.requests.isEmpty)
    }

    @Test func classificationReadsIncidentCauseTolerantly() {
        #expect(CoverageClassification.cause(in: Data(#"{"incident":{"cause":"loss"}}"#.utf8)) == .loss)
        #expect(CoverageClassification.cause(in: Data(#"{"incident":{"cause":"cosmetic"}}"#.utf8)) == nil)
        #expect(CoverageClassification.cause(in: Data(#"{"incident":{}}"#.utf8)) == nil)
        #expect(CoverageClassification.cause(in: Data("not json".utf8)) == nil)
    }
}

/// The HTML verdict in the web view.
@MainActor
struct VerdictModelTests {
    private func request() throws -> CoverageRequest {
        let env = TestEnvironment(reading: .laptopCheckout)
        let model = ClaimModel(purchase: try laptopPurchase(status: .confirmed), deps: env.deps, wallet: .demo3Card)
        model.warranty = .oneYear
        model.description = "Lines across the screen. Never dropped."
        model.pick(.failure)
        return model.verdictRequest()
    }

    @Test func loadsTheHTML() async throws {
        let html = "<!doctype html><title>Verdict</title><h1>May be eligible</h1>"
        let env = TestEnvironment(reading: .laptopCheckout, route: .init(behavior: .respond(status: 200, body: Data(html.utf8))))
        let verdict = VerdictModel(request: try request(), api: env.deps.coverage)
        await verdict.load()
        #expect(verdict.state == .loaded(html: html))
        #expect(env.requests.count == 1)
        #expect(env.deps.coverage.url(.html).absoluteString.hasSuffix("/v1/coverage?format=html"))
        #expect(verdict.baseURL == env.deps.coverage.baseURL)
    }

    @Test func refusedShowsThePhonesOwnWords() async throws {
        let env = TestEnvironment(
            reading: .laptopCheckout,
            route: .init(behavior: .respond(status: 400, body: Data(#"{"error":{"code":"bad_request","message":"x"}}"#.utf8)))
        )
        let verdict = VerdictModel(request: try request(), api: env.deps.coverage)
        await verdict.load()
        #expect(verdict.state == .failed(line2: "Something went wrong · press again"))
    }

    @Test func offlineSaysNoConnection() async throws {
        let env = TestEnvironment(reading: .laptopCheckout, route: .init(behavior: .fail(.notConnectedToInternet)))
        let verdict = VerdictModel(request: try request(), api: env.deps.coverage)
        await verdict.load()
        #expect(verdict.state == .failed(line2: "No connection · press again"))
    }
}

/// "Add my cards" (§5.1 step 1).
struct WalletDraftTests {
    private let order = CardCatalog.bundled().cards.map(\.id)

    @Test func catalogHasTheFiveCards() {
        #expect(order == ["apple-card", "wf-active-cash", "chase-freedom-unlimited", "chase-freedom-rise", "discover-it-student-cash-back"])
    }

    @Test func firstPickIsTheDefaultAndDeselectingMovesIt() {
        var draft = WalletDraft()
        draft.toggle("chase-freedom-unlimited", order: order)
        draft.toggle("apple-card", order: order)
        #expect(draft.defaultId == "chase-freedom-unlimited")
        draft.setDefault("apple-card")
        #expect(draft.defaultId == "apple-card")
        draft.toggle("apple-card", order: order)
        #expect(draft.defaultId == "chase-freedom-unlimited")
        draft.toggle("chase-freedom-unlimited", order: order)
        #expect(draft.defaultId == nil)
        #expect(!draft.isValid)
    }

    @Test func last4IsExactlyFourDigitsOrEmpty() {
        var draft = WalletDraft()
        draft.toggle("apple-card", order: order)
        draft.setLast4("56", for: "apple-card")
        #expect(!draft.isValid)
        draft.setLast4("5x6 78 9", for: "apple-card")
        #expect(draft.last4["apple-card"] == "5678")
        #expect(draft.isValid)
        draft.setLast4("", for: "apple-card")
        #expect(draft.last4["apple-card"] == nil)
        #expect(draft.isValid)
    }

    @Test func walletFollowsCatalogOrder() {
        var draft = WalletDraft()
        draft.toggle("chase-freedom-unlimited", order: order)
        draft.toggle("apple-card", order: order)
        draft.setLast4("1234", for: "chase-freedom-unlimited")
        let wallet = draft.wallet(order: order)
        #expect(wallet.cards == [
            .init(cardId: "apple-card", isDefault: false, last4: nil),
            .init(cardId: "chase-freedom-unlimited", isDefault: true, last4: "1234"),
        ])
    }

    @Test func demoWalletRoundTrips() {
        #expect(WalletDraft(.demo3Card).wallet(order: order) == .demo3Card)
    }
}

/// Debug launch arguments for UI tests.
@MainActor
struct LaunchOptionsTests {
    @Test func parsesEveryFlag() {
        let options = LaunchOptions.parse([
            "Paywise", "-resetState", "-skipOnboarding", "-dateOverride", "2027-12-18", "-tab", "purchases",
        ])
        #expect(options == LaunchOptions(resetState: true, skipOnboarding: true, dateOverride: "2027-12-18", tab: .purchases))
        #expect(LaunchOptions.parse(["Paywise", "-dateOverride", "2027-02-30", "-tab", "nope"]) == LaunchOptions())
        #expect(LaunchOptions.parse(["Paywise"]) == LaunchOptions())
    }

    @Test func resetThenSeed() async throws {
        let env = TestEnvironment(reading: .laptopCheckout)
        let settings = env.deps.settings
        try env.deps.checkStore.write(try Fixtures.recordExample(), now: Fixtures.demoNow)
        _ = try await env.deps.purchases.store().savePlanned(
            checkId: "5f0c0000-aaaa-4bbb-8ccc-ddddeeeeffff", checkStore: env.deps.checkStore
        )
        settings.onboarded = true
        settings.inAppCheckCount = 3

        LaunchOptions(resetState: true).apply(deps: env.deps)
        #expect(env.deps.checkStore.all().isEmpty)
        #expect(try await env.deps.purchases.store().all().isEmpty)
        #expect(settings.defaults.data(forKey: PaywiseSettings.Key.wallet) == nil)
        #expect(!settings.onboarded)
        #expect(settings.inAppCheckCount == 0)

        LaunchOptions(skipOnboarding: true, dateOverride: "2027-12-18").apply(deps: env.deps)
        #expect(settings.onboarded)
        #expect(env.deps.walletStore.load() == .demo3Card)
        #expect(settings.dateOverrideDay == "2027-12-18")
        #expect(Day.today(settings: settings, now: Fixtures.demoNow, timeZone: Fixtures.seattle) == "2027-12-18")
    }

    @Test func dateOverrideIsOffByDefault() {
        let settings = PaywiseSettings(suiteName: "paywise.tests.\(UUID().uuidString)")
        #expect(settings.dateOverrideDay == nil)
        settings.dateOverrideEnabled = true
        #expect(settings.dateOverrideDay == PaywiseSettings.defaultDateOverride)
        #expect(Day.today(settings: PaywiseSettings(suiteName: "paywise.tests.\(UUID().uuidString)"), now: Fixtures.demoNow, timeZone: Fixtures.seattle) == "2026-10-17")
    }
}

/// §10 copy, "What we sent", days and the bundled Shortcut steps.
struct AppCopyTests {
    @Test func privacyCopyIsVerbatim() {
        #expect(PrivacyCopy.onboardingLines.count == 3)
        #expect(PrivacyCopy.onboardingLines[0] == "We only look when you press. Never in the background.")
        #expect(PrivacyCopy.consent.hasPrefix("Paywise sends only a redacted order summary, such as \"Northbay Electronics, Aero 14 Laptop (New), $1,499.00, Mastercard\", to Anthropic's Claude API"))
        #expect(PrivacyCopy.consent.hasSuffix("Tap \"What we sent\" any time to see exactly what was sent."))
        #expect(!PrivacyCopy.consent.contains("\n"))
        #expect(PrivacyCopy.retention == "Screenshots are processed in memory and never saved. Purchases you save stay until you delete them. Our AI provider, Anthropic, may keep the redacted order text for up to 30 days, and longer if its safety systems flag it. It isn't used for model training.")
        let disclaimer = PrivacyCopy.disclaimer(catalog: .bundled())
        #expect(disclaimer.contains("(last checked Oct 15, 2026)"))
        #expect(!disclaimer.contains("[date]"))
        #expect(disclaimer.hasSuffix("Not affiliated with or paid by any issuer."))
    }

    @Test func sentRowTitle() throws {
        let record = try Fixtures.recordExample()
        #expect(SentText.title(record, catalog: .bundled()) == "Northbay Electronics · $1,499.00")
    }

    @Test func days() {
        #expect(Day.monthDay("2026-10-17") == "Oct 17")
        #expect(Day.medium("2027-02-14") == "Feb 14, 2027")
        #expect(PaywiseSettings.isDay("2027-12-18"))
        #expect(!PaywiseSettings.isDay("2027-02-30"))
        #expect(!PaywiseSettings.isDay("27-12-18"))
        let noon = Day.date("2027-12-18", timeZone: Fixtures.seattle)
        #expect(noon.map { Day.string($0, timeZone: Fixtures.seattle) } == "2027-12-18")
    }

    @Test func shortcutGuideShowsTheStepsOnly() {
        let text = ShortcutSteps.allText
        #expect(ShortcutSteps.sections.flatMap(\.steps).map(\.number) == Array(1...15), "numbered as in ios/Shortcut/README.md")
        #expect(text.contains("Settings › Action Button"))
        #expect(text.contains("Back Tap"))
        #expect(text.contains("Check Checkout"))
        #expect(text.contains("has any value"))
        // User-facing words only: no developer notes, spec references, file paths or untested-on-phone marks.
        for developerOnly in ["(u)", "§", "SPEC", "docs/", ".md", "README", "shortcuts sign", "Copy iCloud Link", "TODO", "stopwatch"] {
            #expect(!text.contains(developerOnly), "\(developerOnly)")
        }
    }

    @Test func sampleScreenshotIsBundledInTheApp() {
        #expect(Bundle.main.url(forResource: "laptop-checkout", withExtension: "png") != nil)
        // The developer README isn't shipped: the setup screen has its own steps (`ShortcutSteps`).
        #expect(Bundle.main.url(forResource: "README", withExtension: "md") == nil)
    }
}
