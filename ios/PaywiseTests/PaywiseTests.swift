import Foundation
import Testing
@testable import Paywise

struct ContentStateTests {
    /// The contract's wire names (snake_case phases, "fp" glyph) round-trip through the Swift model.
    @Test func decodesContractShape() throws {
        let json = Data("""
        {"phase":"no_checkout","glyph":"warning","cardShortName":null,"last4":null,
         "line1":"No checkout total found","line2":"Nothing left your phone",
         "lockScreenText":"Paywise checked this screen"}
        """.utf8)
        let state = try JSONDecoder().decode(PaywiseActivityAttributes.ContentState.self, from: json)
        #expect(state.phase == .noCheckout)
        #expect(state.glyph == .warning)
        #expect(state.line2 == "Nothing left your phone")
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
        #expect(object["glyph"] as? String == "fp")
    }
}

struct BundledCatalogTests {
    /// `data/cards.json` ships in the app bundle (§15.2) and parses.
    @Test func cardsJSONIsBundled() throws {
        let url = try #require(Bundle.main.url(forResource: "cards", withExtension: "json"))
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 1)
        #expect((object["cards"] as? [Any])?.isEmpty == false)
    }
}
