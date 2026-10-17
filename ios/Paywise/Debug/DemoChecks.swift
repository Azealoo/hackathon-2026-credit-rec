#if DEBUG
import Foundation

/// Fake checks for the debug hooks (`-demoActivity`, `-gallery`) and previews. Each is a `/v1/check` decision with
/// SPEC §6.3 copy as the backend sends it: `{last4:<cardId>}` and `{ppCap}` stay as tokens and are filled on the phone
/// from the wallet and the bundled cards.json, through the same code a real press uses (`CopyFill`, `CheckFlow`).
/// Card names come from cards.json `shortName`; cash amounts are the §6.3 examples. No card data is read from here.
enum DemoChecks {
    // MARK: Wallets (SPEC §15.4, last 4 only 1234 / 5678 / 4321)

    /// `discover-fu`: Discover ••4321 (default), Freedom ••1234.
    static let discoverFU = Wallet(cards: [
        .init(cardId: "discover-it-student-cash-back", isDefault: true, last4: "4321"),
        .init(cardId: "chase-freedom-unlimited", isDefault: false, last4: "1234"),
    ])

    /// `fu-default`: Freedom ••1234 (default), Active Cash ••4321, Apple Card ••5678.
    static let fuDefault = Wallet(cards: [
        .init(cardId: "chase-freedom-unlimited", isDefault: true, last4: "1234"),
        .init(cardId: "wf-active-cash", isDefault: false, last4: "4321"),
        .init(cardId: "apple-card", isDefault: false, last4: "5678"),
    ])

    static let appleCard = "apple-card"
    static let activeCash = "wf-active-cash"
    static let freedom = "chase-freedom-unlimited"
    static let discover = "discover-it-student-cash-back"

    // MARK: Island decisions (§6.3)

    /// *Keep, default best* (scenario 6 copy on the demo wallet).
    static func keepDefaultBest(_ catalog: CardCatalog) -> CheckResponse.Decision {
        .init(
            kind: .keep, reason: .defaultBest, presentation: .island,
            recommendedCardId: appleCard, defaultCardId: appleCard,
            copy: .init(line1: "✓ Keep \(name(appleCard, catalog)) ••{last4:\(appleCard)}", line2: "Best of your 3 cards here")
        )
    }

    /// *Keep, method* (scenario 8: Nike $180, Apple Pay visible).
    static func keepMethod(_ catalog: CardCatalog) -> CheckResponse.Decision {
        .init(
            kind: .keep, reason: .method, presentation: .island,
            recommendedCardId: appleCard, defaultCardId: appleCard, paymentPath: .applePay, instruction: .useApplePay,
            copy: .init(line1: "✓ \(name(appleCard, catalog)): use Apple Pay", line2: "3% ($5.40) with Apple Pay vs 1% typed")
        )
    }

    /// *Keep, items unreadable* (scenario 18).
    static func keepItemsUnreadable(_ catalog: CardCatalog) -> CheckResponse.Decision {
        .init(
            kind: .keep, reason: .itemsUnreadable, presentation: .island,
            recommendedCardId: appleCard, defaultCardId: appleCard,
            copy: .init(
                line1: "✓ Keep \(name(appleCard, catalog)) ••{last4:\(appleCard)}",
                line2: "Couldn't read the items, so no switch"
            )
        )
    }

    /// *No checkout, from backend* (text was sent; the screen isn't a checkout).
    static let noCheckoutFromBackend = CheckResponse.Decision(
        kind: .noCheckout, reason: .notCheckout, presentation: .island,
        copy: .init(line1: "No checkout total found", line2: "Scroll to the total and press again")
    )

    /// *No checkout, already paid* (order confirmation screen).
    static let alreadyPaid = CheckResponse.Decision(
        kind: .noCheckout, reason: .alreadyPaid, presentation: .island,
        copy: .init(line1: "Already paid?", line2: "Press on the checkout, before you pay")
    )

    // MARK: Snippet responses (§6.3)

    /// *Switch, protection* on the demo laptop: the bundled replay fixture (fake data).
    static func laptopSwitch() -> CheckResponse? {
        guard let data = ReplayStore().response(for: .init(merchantId: "northbay-electronics", totalCents: 149_900)),
              let json = try? JSONValue(data: data)
        else { return nil }
        return try? json.decode(CheckResponse.self)
    }

    /// *Switch, protection* on the demo earbuds ($249): the bundled replay fixture (fake data), for a longer Saved line 1.
    static func earbudsSwitch() -> CheckResponse? {
        guard let data = ReplayStore().response(for: .init(merchantId: "northbay-electronics", totalCents: 24_900)),
              let json = try? JSONValue(data: data)
        else { return nil }
        return try? json.decode(CheckResponse.self)
    }

    /// *Switch, protection* on long-named headphones ($299, fake data): the earbuds check with a name too long for one
    /// Saved line 1, "Noise-Cancelling Headphones, Black".
    static func headphonesSwitch() -> CheckResponse? {
        guard var response = earbudsSwitch() else { return nil }
        let name = "Noise-Cancelling Headphones, Black"
        response.cart?.items?[0].name = name
        response.cart?.items?[0].priceUsd = 299
        response.cart?.totalUsd = 299
        // Freedom 1.5% = $4.49 vs Active Cash 2% = $5.98 (each rounded to cents first, §6.3).
        response.decision?.copy?.line3 = "$1.49 less cash back than Active Cash"
        response.purchaseDraft?.item = name
        response.purchaseDraft?.priceUsd = 299
        return response
    }

    /// *Switch, protection, pick also cash-best* (scenario 16, `discover-fu`).
    static func laptopSwitchAlsoCashBest(_ catalog: CardCatalog) -> CheckResponse? {
        guard var response = laptopSwitch(), var decision = response.decision else { return nil }
        decision.defaultCardId = discover
        decision.cashBestCardId = freedom
        decision.cash = nil
        decision.copy?.line3 = "Also earns the most cash back here"
        decision.copy?.instruction = changeCard(freedom, catalog)
        response.decision = decision
        return response
    }

    /// *Switch, cash* (scenario 2: the renewed laptop, $1,099, no maker's warranty).
    static func renewedSwitchCash(_ catalog: CardCatalog) -> CheckResponse? {
        guard var response = laptopSwitch() else { return nil }
        response.cart?.items?[0].condition = .renewed
        response.cart?.items?[0].priceUsd = 1099
        response.cart?.totalUsd = 1099
        response.decision = .init(
            kind: .switch, reason: .cash, presentation: .snippet,
            recommendedCardId: activeCash, defaultCardId: appleCard, cashBestCardId: activeCash,
            paymentPath: .savedCard, instruction: .changeSavedCard,
            protectionsGained: [], protectionsLost: [],
            eligibilityNotes: ["Renewed: no card cover counted"],
            confidence: .high,
            copy: .init(
                line1: "Use \(name(activeCash, catalog)) ••{last4:\(activeCash)}",
                line2: "$10.99 more cash back than \(name(appleCard, catalog))",
                instruction: changeCard(activeCash, catalog),
                primaryButton: "Paying with \(name(activeCash, catalog))"
            )
        )
        response.purchaseDraft?.condition = .renewed
        response.purchaseDraft?.priceUsd = 1099
        response.purchaseDraft?.cardId = activeCash
        response.purchaseDraft?.coverage = []
        return response
    }

    /// *Keep, protected* (scenario 23, `fu-default` with a Visa selected: the guard keeps the protected default).
    static func laptopKeepProtected(_ catalog: CardCatalog) -> CheckResponse? {
        guard var response = laptopSwitch() else { return nil }
        response.decision = .init(
            kind: .keep, reason: .alreadyProtected, presentation: .snippet,
            recommendedCardId: freedom, defaultCardId: freedom, cashBestCardId: activeCash,
            paymentPath: .savedCard, instruction: InstructionKind.none,
            protectionsGained: [], protectionsLost: [], eligibilityNotes: [], confidence: .high,
            copy: .init(
                line1: "✓ Keep \(name(freedom, catalog)) ••{last4:\(freedom)}",
                line2: "Adds a warranty year + {ppCap} theft cover",
                line3: "Save it so you can claim later",
                primaryButton: "Paying with \(name(freedom, catalog))"
            )
        )
        return response
    }

    // MARK: Records

    /// A `CheckRecord` as the intent writes it, with the copy filled for `wallet`.
    static func record(
        _ response: CheckResponse, wallet: Wallet, catalog: CardCatalog, ocrText: String,
        view: CheckRecord.Screen = .result, replayed: Bool = false
    ) -> CheckRecord? {
        guard let json = try? JSONValue(data: JSONCoding.encoder.encode(response)) else { return nil }
        let reading = ScreenReading.laptopCheckout
        let request = CheckRequest(
            requestId: "5f0c0000-aaaa-4bbb-8ccc-ddddeeeeffff",
            client: .init(app: "paywise-ios", version: "0.1.0"),
            clientDate: "2026-10-17",
            screen: .init(ocrText: ocrText, redactions: reading.redactions, ocrConfidence: reading.ocrConfidence),
            wallet: .init(cards: wallet.requestCards),
            prefs: .init(paysInFull: nil)
        )
        return CheckRecord(
            checkId: request.requestId,
            createdAt: "2026-10-17T14:02:11-07:00",
            sentPayload: (try? JSONValue(data: JSONCoding.encoder.encode(request))) ?? .null,
            response: json,
            filledCopy: CopyFill.fill(
                response.decision?.copy, wallet: wallet,
                ppCap: CopyFill.ppCap(decision: response.decision, catalog: catalog)
            ),
            replayed: replayed,
            savedPurchaseId: view == .result ? nil : "p_demo",
            view: view
        )
    }

    /// The renewed laptop's screen text, as on-device reading would send it (fake data).
    static let renewedOCRText = """
    Northbay Electronics
    Checkout
    Aero 14 Laptop, 14-inch (Renewed · no warranty)  $1,099.00
    Total  $1,099.00
    Pay with Mastercard [CARD]
    Change
    Ship to [ADDRESS]
    Place order
    """

    /// The demo earbuds' screen text, as on-device reading would send it (fake data, fixtures/ocr/earbuds-checkout.txt).
    static let earbudsOCRText = """
    NORTHBAY Electronics
    Checkout
    Wireless Earbuds,  $249.00
    Noise-Cancelling
    Pay with  Mastercard [CARD]  Change
    Total  $249.00
    Place order
    """

    /// The long-named headphones' screen text (fake data), as on-device reading would send it.
    static let headphonesOCRText = """
    NORTHBAY Electronics
    Checkout
    Noise-Cancelling Headphones,  $299.00
    Black
    Pay with  Mastercard [CARD]  Change
    Total  $299.00
    Place order
    """

    // MARK: Helpers

    static func name(_ cardId: String, _ catalog: CardCatalog) -> String {
        catalog.shortName(cardId) ?? cardId
    }

    /// "Change card to Visa ••{last4:<id>}, then place order", the network from cards.json.
    static func changeCard(_ cardId: String, _ catalog: CardCatalog) -> String {
        let network = switch catalog.card(cardId)?.network {
        case .visa: "Visa"
        case .mastercard: "Mastercard"
        case .discover: "Discover"
        case .amex: "Amex"
        default: "this card"
        }
        return "Change card to \(network) ••{last4:\(cardId)}, then place order"
    }
}
#endif
