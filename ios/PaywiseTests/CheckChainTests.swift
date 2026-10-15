import Foundation
import Testing
@testable import Paywise

/// §6.3 copy fill on the phone.
struct CopyFillTests {
    private let copy = CheckResponse.Copy(
        line1: "Use Freedom ••{last4:chase-freedom-unlimited}",
        line2: "Adds a warranty year + {ppCap} theft cover",
        line3: "$7.49 less cash back than Active Cash",
        instruction: "Change card to Visa ••{last4:chase-freedom-unlimited}, then place order",
        primaryButton: "Paying with Freedom"
    )

    @Test func fillsLast4AndCap() {
        let filled = CopyFill.fill(copy, wallet: .demo3Card, ppCap: 500)
        #expect(filled.line1 == "Use Freedom ••1234")
        #expect(filled.line2 == "Adds a warranty year + $500 theft cover")
        #expect(filled.instruction == "Change card to Visa ••1234, then place order")
    }

    @Test func dropsBulletsWithoutStoredLast4() {
        var wallet = Wallet.demo3Card
        wallet.cards[2].last4 = nil
        let filled = CopyFill.fill(copy, wallet: wallet, ppCap: 500)
        #expect(filled.line1 == "Use Freedom")
        #expect(filled.instruction == "Change card to Visa, then place order")
        #expect(!(filled.line1 + (filled.instruction ?? "")).contains("••"))
    }

    @Test func unverifiedCapReadsTheftCover() {
        let filled = CopyFill.fill(copy, wallet: .demo3Card, ppCap: nil)
        #expect(filled.line2 == "Adds a warranty year + theft cover")
    }

    @Test func capComesFromVerifiedProtectionOnly() {
        let catalog = CardCatalog.bundled()
        var decision = CheckResponse.Decision(
            recommendedCardId: "chase-freedom-unlimited",
            protectionsGained: [.init(type: .purchaseProtection, limit: .init(amountUsd: 500, appliesTo: .item), verification: .verified)]
        )
        #expect(CopyFill.ppCap(decision: decision, catalog: catalog) == 500)
        decision.protectionsGained = [.init(type: .purchaseProtection, limit: .init(amountUsd: 500, appliesTo: .item), verification: .partial)]
        #expect(CopyFill.ppCap(decision: decision, catalog: catalog) == nil)
        // Keep-protected gains nothing: the catalog's verified limit for the card is used.
        decision.protectionsGained = []
        #expect(CopyFill.ppCap(decision: decision, catalog: catalog) == 500)
    }

    @Test func moneyFormatting() {
        #expect(Money.whole(500) == "$500")
        #expect(Money.whole(1499) == "$1,499")
        #expect(Money.whole(7.49) == "$7.49")
    }

    /// §6.4 VoiceOver label for Switch, word for word.
    @Test func voiceOverLabelForSwitch() {
        let filled = CopyFill.fill(copy, wallet: .demo3Card, ppCap: 500)
        #expect(SpokenCopy.label(filled) == "Use Freedom, card ending 1 2 3 4. Adds a warranty year and up to 500 dollars of theft cover. 7 dollars 49 less cash back than Active Cash.")
    }
}

/// §15.7 step 10 replay key.
struct ReplayTests {
    @Test func keyFromSpecExampleText() throws {
        let reading = try Fixtures.laptopReading()
        let key = ReplayStore.key(for: reading.redactedText, catalog: .bundled())
        #expect(key == .init(merchantId: "northbay-electronics", totalCents: 149_900))
    }

    @Test func keyFromDemoStoreOCR() {
        let text = "NORTHBAY Electronics\nCheckout\nWireless Earbuds,  $249.00\nSubtotal  $230.00\nShipping  Free\nTotal  $249.00\nPlace order"
        #expect(ReplayStore.key(for: text, catalog: .bundled()) == .init(merchantId: "northbay-electronics", totalCents: 24_900))
    }

    @Test func totalOnTheNextLine() {
        #expect(ReplayStore.totalCents(in: "Order total\n$18.00\nPlace order") == 1_800)
        #expect(ReplayStore.totalCents(in: "Subtotal $10.00") == nil)
    }
}

/// The tolerant response mirror: unknown enum strings and malformed fields never fail the decode.
struct ResponseDecodingTests {
    @Test func unknownEnumsFallBack() throws {
        let json = Data("""
        {"requestId":"x","screenType":"hologram","decision":{"kind":"maybe","reason":"vibes","presentation":"toast",
         "paymentPath":"crypto","instruction":"dance","confidence":"sure","copy":{"line1":"Hi"},
         "protectionsGained":[{"type":"alien_protection","limit":{"amountUsd":5,"appliesTo":"planet"},"verification":"vibes"}]},
         "cart":{"items":[{"condition":"haunted","seller":"ghost"}],"selectedPayment":{"kind":"barter","network":"telepathy"},
         "paymentOptionsVisible":["carrier_pigeon"]},
         "purchaseDraft":{"condition":"cursed","coverage":[{"type":"magic","until":"2027-01-01"}]},
         "newTopLevelField":{"anything":[1,2,3]}}
        """.utf8)
        let response = try JSONDecoder().decode(CheckResponse.self, from: json)
        #expect(response.screenType == .unrecognized)
        #expect(response.decision?.kind == .unrecognized)
        #expect(response.decision?.reason == .unrecognized)
        #expect(response.decision?.presentation == .unrecognized)
        #expect(response.decision?.paymentPath == .unknown)
        #expect(response.decision?.copy?.line1 == "Hi")
        #expect(response.decision?.protectionsGained?.first?.type == .unrecognized)
        #expect(response.cart?.items?.first?.condition == .unknown)
        #expect(response.cart?.selectedPayment?.network == .unknown)
        #expect(response.cart?.paymentOptionsVisible == [.other])
        #expect(response.purchaseDraft?.coverage?.first?.type == .unrecognized)
    }

    @Test func malformedSectionKeepsTheDecision() throws {
        let json = Data("""
        {"cart":"not an object","sources":7,"decision":{"kind":"keep","cash":"lots","copy":{"line1":"✓ Keep Apple Card ••{last4:apple-card}"}}}
        """.utf8)
        let response = try JSONDecoder().decode(CheckResponse.self, from: json)
        #expect(response.cart == nil)
        #expect(response.decision?.kind == .keep)
        #expect(response.decision?.cash == nil)
    }

    @Test func contractExamplesDecode() throws {
        let response = try JSONDecoder().decode(CheckResponse.self, from: Fixtures.responseExample())
        #expect(response.decision?.kind == .switch)
        #expect(response.purchaseDraft?.coverage?.count == 2)
        let record = try Fixtures.recordExample()
        #expect(record.filledCopy.line1 == "Use Freedom ••1234")
        #expect(record.request?.wallet.cards.count == 3)
    }

    /// The phone's own Couldn't-check response keeps the contract's error shape.
    @Test func couldntCheckResponseHasErrorShape() throws {
        let json = CheckFlow.couldntCheckResponse(checkId: "abc", failure: .timeout)
        guard case .object(let object) = json else {
            Issue.record("not an object")
            return
        }
        #expect(Set(object.keys) == ["requestId", "decision", "error"])
        guard case .object(let decision)? = object["decision"] else {
            Issue.record("no decision")
            return
        }
        #expect(Set(decision.keys) == ["kind", "reason", "presentation", "copy"])
        #expect(object["error"]?["code"] == .string("timeout"))
    }
}

/// `CheckStore` (SPEC §15.5): file per check, 24 h pruning, latest lookup, safe IDs.
struct CheckStoreTests {
    private func record(id: String, createdAt: Date) throws -> CheckRecord {
        var record = try Fixtures.recordExample()
        record.checkId = id
        record.createdAt = CheckRecord.timestamp(createdAt, timeZone: Fixtures.seattle)
        return record
    }

    @Test func writesReadsAndPrunes() throws {
        let store = CheckStore(containerURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        let now = Fixtures.demoNow
        try store.write(record(id: "old-1", createdAt: now.addingTimeInterval(-25 * 3600)), now: now.addingTimeInterval(-25 * 3600))
        try store.write(record(id: "new-1", createdAt: now.addingTimeInterval(-60)), now: now)
        try store.write(record(id: "new-2", createdAt: now), now: now)

        #expect(store.record(id: "old-1") == nil)
        #expect(store.all().count == 2)
        #expect(store.latest(now: now)?.checkId == "new-2")
        #expect(FileManager.default.fileExists(atPath: store.directory.appending(path: "new-2.json").path()))
    }

    @Test func rejectsPathLikeIDs() throws {
        let store = CheckStore(containerURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        #expect(throws: CheckStore.StoreError.invalidCheckId) {
            try store.write(record(id: "../escape", createdAt: Fixtures.demoNow))
        }
        #expect(store.record(id: "../escape") == nil)
    }

    @Test func concurrentUpdatesDontLoseWrites() async throws {
        let store = CheckStore(containerURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        try store.write(record(id: "c-1", createdAt: Fixtures.demoNow), now: Fixtures.demoNow)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    _ = try? store.update(id: "c-1") { $0.filledCopy.line3 = ($0.filledCopy.line3 ?? "") + "\(index % 10)" }
                }
            }
        }
        #expect(store.record(id: "c-1")?.filledCopy.line3?.count == "$7.49 less cash back than Active Cash".count + 20)
    }
}

/// Privacy guards on what leaves the phone (SPEC §9.2, §10, §15.7 step 8).
struct PrivacyGuardTests {
    private static let wallet = Wallet.demo3Card
    private static var walletLast4: [String] { wallet.cards.compactMap(\.last4) }
    private static var cardNames: [String] {
        CardCatalog.bundled().cards.flatMap { [$0.shortName, $0.displayName].compactMap { $0 } }
    }

    private func scrub(_ text: String, redactions: [String] = []) -> (text: String, redactions: [String]) {
        PrivacyGuard.scrub(
            ScreenReading(redactedText: text, redactions: redactions, ocrConfidence: 0.9, isCheckout: true),
            walletLast4: Self.walletLast4, cardNames: Self.cardNames
        )
    }

    /// Each ASCII digit as its fullwidth form (U+FF10…U+FF19).
    private func fullwidth(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            guard let value = Character(scalar).wholeNumberValue, scalar.isASCII else { return scalar }
            return Unicode.Scalar(0xFF10 + UInt32(value))!
        }))
    }

    @Test func requestIDsNeverCarryTwelveDigitsOrACardNumber() {
        for _ in 0..<5_000 {
            let id = RequestID.make()
            #expect(PrivacyGuard.longestDigitRun(id) < 12)
            #expect(!PrivacyGuard.containsCardNumber(id))
        }
    }

    @Test func scrubsLongDigitRuns() {
        let scrubbed = scrub("Order ref 123456789012345\nTotal $5.00")
        #expect(scrubbed.text == "Order ref [CARD]\nTotal $5.00")
        #expect(scrubbed.redactions == ["card_number"])
    }

    /// The demo store's card labels (demo-store/store.js) and the other ways a screen shows a card.
    @Test(arguments: [
        ("Pay with  Mastercard ••5678  Change", "Pay with  Mastercard [CARD]  Change"),
        ("Visa ••1234", "Visa [CARD]"),
        ("Visa ••4321", "Visa [CARD]"),
        ("Mastercard •••• 5678", "Mastercard [CARD]"),
        ("Visa **1234", "Visa [CARD]"),
        ("Visa ..1234", "Visa [CARD]"),
        ("XXXX-XXXX-XXXX-1234", "XXXX-XXXX-[CARD]"),
        ("Visa ending in 4321", "Visa [CARD]"),
        ("Card ending with 1234", "Card [CARD]"),
        ("Pay with Visa 4321", "Pay with Visa [CARD]"),
        ("Mastercard: 5678", "Mastercard: [CARD]"),
        ("Freedom Unlimited (1234)", "Freedom Unlimited ([CARD])"),
        ("Apple Card\n5678", "Apple Card\n[CARD]"),
        ("Card 1234 5678 9012 3456 exp 12/29", "Card [CARD] exp 12/29"),
        ("1234-5678-9012-3456", "[CARD]"),
        ("1234 567890 12345", "[CARD]"),
        // Luhn-valid but not card-shaped (8-8): still a card number (§15.7 step 8).
        ("12345678 90123452", "[CARD]"),
    ])
    func scrubsCardNumbersAndLast4(input: String, expected: String) {
        let scrubbed = scrub(input)
        #expect(scrubbed.text == expected)
        #expect(scrubbed.redactions == ["card_number"])
        for last4 in Self.walletLast4 {
            #expect(!scrubbed.text.contains(last4), "\(last4) survived in \(scrubbed.text)")
        }
    }

    /// Order-summary text the backend needs passes through untouched.
    @Test(arguments: [
        "Aero 14 Laptop, 14-inch  $1,499.00",
        "Total  $1,499.00",
        "Total ..1499.00",
        "Order 112-3456789-1234567",
        "Delivery Oct 17, 2026",
        "Card 1 of 2",
        "Gift card balance $1234.00",
        "Qty 1",
        "Pay with  Mastercard [CARD]  Change",
    ])
    func keepsOrderSummaryText(text: String) {
        let scrubbed = scrub(text)
        #expect(scrubbed.text == text)
        #expect(scrubbed.redactions.isEmpty)
    }

    @Test func specExampleTextIsUnchanged() throws {
        let reading = try Fixtures.laptopReading()
        let scrubbed = PrivacyGuard.scrub(reading, walletLast4: Self.walletLast4, cardNames: Self.cardNames)
        #expect(scrubbed.text == reading.redactedText)
        #expect(scrubbed.redactions == reading.redactions)
    }

    /// The backend's `\d` counts any Unicode digit; invisible characters and control escapes can't split or join runs.
    @Test func unicodeDigitsAndInvisibleCharacters() {
        #expect(scrub("Card " + fullwidth("1234 5678 9012 3456")).text == "Card [CARD]")
        #expect(PrivacyGuard.longestDigitRun(fullwidth("123456789012")) == 12)
        #expect(scrub(["1234", "5678", "9012", "3456"].joined(separator: "\u{200B}")).text == "[CARD]")
        let control = scrub("x\u{0001}12345678901")
        #expect(control.text == "x 12345678901")
        #expect(PrivacyGuard.isSendable(Data("{\"t\":\"\(control.text)\"}".utf8)))
    }

    @Test func wireConfidenceAlwaysEncodesShort() throws {
        // Vision confidences are Floats; widened to Double they print with up to 17 digits.
        #expect(PrivacyGuard.longestDigitRun("\(Double(Float(0.93)))") >= 12)
        for n in 0...1_000 {
            let value = Double(Float(n) / 1_000)
            let text = String(decoding: try JSONCoding.encoder.encode([CheckFlow.wireConfidence(value)]), as: UTF8.self)
            #expect(PrivacyGuard.longestDigitRun(text) <= 2, "\(value) encodes as \(text)")
        }
        let mean = Double([Float(0.91), Float(0.88), Float(0.95)].reduce(0, +) / 3)
        #expect(CheckFlow.wireConfidence(mean) == 0.91)
        #expect(CheckFlow.wireConfidence(Double(Float(0.93))) == 0.93)
        #expect(CheckFlow.wireConfidence(.nan) == 0)
        #expect(CheckFlow.wireConfidence(1.7) == 1)
        #expect(CheckFlow.wireConfidence(-0.2) == 0)
    }

    /// The backend's two rules, held on the phone before sending (backend/app/middleware.py `body_is_private`).
    @Test func sendableBodies() throws {
        #expect(PrivacyGuard.isSendable(try Fixtures.data("check.request.example")))
        #expect(!PrivacyGuard.isSendable(Data()))
        #expect(!PrivacyGuard.isSendable(Data(#"{"screen":{"ocrConfidence":0.9300000071525574}}"#.utf8)))
        #expect(!PrivacyGuard.isSendable(Data(#"{"ocrText":"Card 1234 5678 9012 3456"}"#.utf8)))
        #expect(!PrivacyGuard.isSendable(Data(#"{"ocrText":"12345678 90123452"}"#.utf8)))
        #expect(PrivacyGuard.isSendable(Data(#"{"ocrText":"Order 112-3456789-1234567"}"#.utf8)))
    }
}

/// Snippet text that isn't backend copy (SPEC §6.3).
struct ResultTextTests {
    @Test func noCardNameMeansNoButton() {
        let catalog = CardCatalog.bundled()
        let unknown = CheckResponse.Decision(kind: .switch, recommendedCardId: "unknown-card", copy: .init(line1: "Use it"))
        #expect(ResultText.primaryButtonTitle(decision: unknown, catalog: catalog) == nil)
        let fromCopy = CheckResponse.Decision(
            kind: .switch, recommendedCardId: "unknown-card", copy: .init(primaryButton: "Paying with Freedom")
        )
        #expect(ResultText.primaryButtonTitle(decision: fromCopy, catalog: catalog) == "Paying with Freedom")
        let known = CheckResponse.Decision(kind: .switch, recommendedCardId: "chase-freedom-unlimited")
        #expect(ResultText.primaryButtonTitle(decision: known, catalog: catalog) == "Paying with Freedom")
    }

    @Test func savedWithoutItemNameDropsIt() {
        #expect(ResultText.saved(.init(priceUsd: 1_499)).line1 == "✓ Saved · $1,499")
        #expect(ResultText.saved(.init(item: "Aero 14 Laptop, 14-inch", priceUsd: 1_499)).line1 == "✓ Saved: Aero 14 · $1,499")
    }
}
