import Foundation
import Testing
@testable import Paywise

struct ContentStateTests {
    /// The contract's wire names (snake_case phases, "paywise" glyph) round-trip through the Swift model.
    @Test func decodesContractShape() throws {
        let json = Data("""
        {"phase":"no_checkout","glyph":"warning","cardShortName":null,"last4":null,
         "line1":"No checkout total found","line2":"Nothing left your phone",
         "line3":"Scroll to the total and press again",
         "lockScreenText":"Paywise checked this screen"}
        """.utf8)
        let state = try JSONDecoder().decode(PaywiseActivityAttributes.ContentState.self, from: json)
        #expect(state.phase == .noCheckout)
        #expect(state.glyph == .warning)
        #expect(state.line2 == "Nothing left your phone")
        #expect(state.line3 == "Scroll to the total and press again")
    }

    /// contracts/live-activity-content-state.example.json, with and without the optional line3 (R4).
    @Test func decodesWithoutLine3() throws {
        let json = Data("""
        {"phase":"keep","glyph":"check","cardShortName":"Apple Card","last4":"5678",
         "line1":"✓ Keep Apple Card ••5678","line2":"Best of your 3 cards here",
         "lockScreenText":"Paywise checked this screen"}
        """.utf8)
        let state = try JSONDecoder().decode(PaywiseActivityAttributes.ContentState.self, from: json)
        #expect(state.line3 == nil)
        #expect(state.glyph == .check)
    }

    @Test func checkingStateMatchesSpecCopy() throws {
        let state = PaywiseActivityAttributes.ContentState.checking
        #expect(state.phase == .checking)
        #expect(state.line1 == "Reading this screen…")
        #expect(state.line2 == "Only the order summary leaves your phone")
        #expect(state.lockScreenText == "Paywise is checking")

        let encoded = try JSONEncoder().encode(state)
        #expect(encoded.count < 4096)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["glyph"] as? String == "paywise")
        // Required-but-nullable keys are present; the optional line3 is left out when nil.
        #expect(object["cardShortName"] is NSNull)
        #expect(object["last4"] is NSNull)
        #expect(object["line3"] == nil)
    }

    @Test func threeLineStateEncodesLine3() throws {
        let encoded = try JSONEncoder().encode(CheckFlow.noCheckoutOnDevice)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["line3"] as? String == "Scroll to the total and press again")
        #expect(object["phase"] as? String == "no_checkout")
    }
}

struct BundledCatalogTests {
    /// `data/cards.json` ships in the app bundle (§15.2) and parses.
    @Test func cardsJSONIsBundled() throws {
        let url = try #require(Bundle.main.url(forResource: "cards", withExtension: "json"))
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 2)
        #expect((object["cards"] as? [Any])?.isEmpty == false)
    }

    @Test func catalogModelReadsDemoCards() throws {
        let catalog = CardCatalog.bundled()
        #expect(catalog.shortName("chase-freedom-unlimited") == "Freedom")
        #expect(catalog.shortName("wf-active-cash") == "Active Cash")
        #expect(catalog.shortName("apple-card") == "Apple Card")
        #expect(catalog.card("chase-freedom-unlimited")?.art?.assetName != nil)
        #expect(catalog.verifiedPurchaseProtectionCap(cardId: "chase-freedom-unlimited") == 500)
        #expect(catalog.verifiedPurchaseProtectionCap(cardId: "apple-card") == nil)
    }

    @Test func merchantFoundCaseInsensitivelyEarliestFirst() {
        let catalog = CardCatalog.bundled()
        #expect(catalog.merchantId(in: "NORTHBAY Electronics\nCheckout\nPay with Apple Pay") == "northbay-electronics")
        #expect(catalog.merchantId(in: "Checkout\nTotal $5.00") == nil)
        // Whole words only: "Targeted" isn't Target.
        #expect(catalog.merchantId(in: "Targeted offers") == nil)
    }

    @Test func replayFixtureIsBundled() {
        let key = ReplayStore.Key(merchantId: "northbay-electronics", totalCents: 149_900)
        #expect(ReplayStore().response(for: key) != nil)
    }
}
