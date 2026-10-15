import Foundation
import Testing
@testable import Paywise

/// Every Live Activity state's copy against SPEC §6.3, word for word, built the way a press builds it
/// (backend-style copy → `CopyFill` → `CheckFlow.islandState`, or `CheckFlow`'s own on-device states).
struct LiveActivityStateTests {
    typealias State = PaywiseActivityAttributes.ContentState

    struct Expected: CustomTestStringConvertible, Sendable {
        var phase: State.Phase
        var glyph: State.Glyph
        var cardId: String?
        var cardShortName: String?
        var last4: String?
        var line1: String
        var line2: String?
        var line3: String?
        var lockScreenText = "Paywise checked this screen"

        var testDescription: String { line1 }

        func check(_ state: State, sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(state.phase == phase, sourceLocation: sourceLocation)
            #expect(state.glyph == glyph, sourceLocation: sourceLocation)
            #expect(state.cardId == cardId, sourceLocation: sourceLocation)
            #expect(state.cardShortName == cardShortName, sourceLocation: sourceLocation)
            #expect(state.last4 == last4, sourceLocation: sourceLocation)
            #expect(state.line1 == line1, sourceLocation: sourceLocation)
            #expect(state.line2 == line2, sourceLocation: sourceLocation)
            #expect(state.line3 == line3, sourceLocation: sourceLocation)
            #expect(state.lockScreenText == lockScreenText, sourceLocation: sourceLocation)
        }
    }

    static let checking = Expected(
        phase: .checking, glyph: .paywise,
        line1: "Reading this screen…", line2: "Only the order summary leaves your phone",
        lockScreenText: "Paywise is checking"
    )

    /// The `-demoActivity` states on the demo wallet (Apple Card ••5678, Active Cash ••4321, Freedom ••1234).
    static let demoExpectations: [DemoActivity: Expected] = [
        .checking: checking,
        .stale: checking,
        .keep: Expected(
            phase: .keep, glyph: .check, cardId: "apple-card", cardShortName: "Apple Card", last4: "5678",
            line1: "✓ Keep Apple Card ••5678", line2: "Best of your 3 cards here"
        ),
        .keepMethod: Expected(
            phase: .keep, glyph: .check, cardId: "apple-card", cardShortName: "Apple Card", last4: "5678",
            line1: "✓ Apple Card: use Apple Pay", line2: "3% ($5.40) with Apple Pay vs 1% typed"
        ),
        .noCheckout: Expected(
            phase: .noCheckout, glyph: .warning,
            line1: "No checkout total found", line2: "Nothing left your phone", line3: "Scroll to the total and press again"
        ),
        .couldntCheck: Expected(
            phase: .error, glyph: .warning, line1: "Couldn't check this time", line2: "No connection · press again"
        ),
        .switchFallback: Expected(
            phase: .switchFallback, glyph: .card, cardId: "chase-freedom-unlimited", cardShortName: "Freedom",
            last4: "1234", line1: "Use Freedom ••1234", line2: "Adds a warranty year + $500 theft cover",
            line3: "$7.49 less cash back than Active Cash"
        ),
    ]

    private static func deps() -> AppDependencies {
        TestEnvironment(reading: .laptopCheckout).deps
    }

    private static func island(_ decision: CheckResponse.Decision?, wallet: Wallet = .demo3Card) -> State {
        let deps = deps()
        let copy = CopyFill.fill(
            decision?.copy, wallet: wallet, ppCap: CopyFill.ppCap(decision: decision, catalog: deps.catalog)
        )
        return CheckFlow(deps: deps).islandState(decision: decision, copy: copy, wallet: wallet)
    }

    @Test(arguments: DemoActivity.allCases)
    func demoStateMatchesSpecCopy(_ demo: DemoActivity) throws {
        let expected = try #require(Self.demoExpectations[demo])
        expected.check(demo.state(deps: Self.deps()))
    }

    @Test func keepItemsUnreadable() {
        Expected(
            phase: .keep, glyph: .check, cardId: "apple-card", cardShortName: "Apple Card", last4: "5678",
            line1: "✓ Keep Apple Card ••5678", line2: "Couldn't read the items, so no switch"
        ).check(Self.island(DemoChecks.keepItemsUnreadable(.bundled())))
    }

    /// §6.3: with no stored last 4 the phone drops "••{…}"; the card art still shows.
    @Test func keepWithoutLast4DropsTheDigits() {
        let wallet = Wallet(cards: [.init(cardId: "apple-card", isDefault: true, last4: nil)])
        Expected(
            phase: .keep, glyph: .check, cardId: "apple-card", cardShortName: "Apple Card", last4: nil,
            line1: "✓ Keep Apple Card", line2: "Best of your 3 cards here"
        ).check(Self.island(DemoChecks.keepDefaultBest(.bundled()), wallet: wallet))
    }

    @Test func noCheckoutFromBackend() {
        Expected(
            phase: .noCheckout, glyph: .warning,
            line1: "No checkout total found", line2: "Scroll to the total and press again"
        ).check(Self.island(DemoChecks.noCheckoutFromBackend))
    }

    @Test func noCheckoutAlreadyPaid() {
        Expected(
            phase: .noCheckout, glyph: .warning, line1: "Already paid?", line2: "Press on the checkout, before you pay"
        ).check(Self.island(DemoChecks.alreadyPaid))
    }

    @Test(arguments: [
        (PaywiseAPI.Failure.offline, "No connection · press again"),
        (.server(status: 503), "No connection · press again"),
        (.timeout, "Took too long · press again"),
    ])
    func couldntCheck(_ failure: PaywiseAPI.Failure, _ line2: String) throws {
        let response = CheckFlow.couldntCheckResponse(checkId: "c", failure: failure)
        let decision = try response.decode(CheckResponse.self).decision
        Expected(phase: .error, glyph: .warning, line1: "Couldn't check this time", line2: line2)
            .check(Self.island(decision))
    }

    /// §6.4: the Lock Screen names no card, amount or store, in any state.
    @Test func lockScreenNamesNoCardAmountOrStore() {
        let catalog = CardCatalog.bundled()
        let deps = Self.deps()
        var states = DemoActivity.allCases.map { $0.state(deps: deps) }
        states.append(Self.island(DemoChecks.keepItemsUnreadable(catalog)))
        states.append(Self.island(DemoChecks.alreadyPaid))
        let forbidden = catalog.cards.compactMap(\.shortName) + catalog.merchants.flatMap { $0.names ?? [] } + ["$", "••"]
        for state in states {
            #expect(["Paywise is checking", "Paywise checked this screen"].contains(state.lockScreenText))
            #expect(!state.lockScreenText.contains { $0.isNumber })
            for word in forbidden {
                #expect(!state.lockScreenText.localizedCaseInsensitiveContains(word), "\(state.lockScreenText) names \(word)")
            }
        }
    }

    /// ActivityKit's 4 KB limit, and the contract shape (cardId optional, round-trips).
    @Test(arguments: DemoActivity.allCases)
    func stateEncodesUnder4KBAndRoundTrips(_ demo: DemoActivity) throws {
        let state = demo.state(deps: Self.deps())
        let data = try JSONEncoder().encode(state)
        #expect(data.count < 4096)
        #expect(try JSONDecoder().decode(State.self, from: data) == state)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["cardId"] as? String == state.cardId)
        #expect(object.keys.contains("cardShortName"))
    }

    /// contracts/live-activity-content-state.example.json, now with the optional cardId.
    @Test func decodesContractExampleWithCardId() throws {
        let json = Data("""
        {"phase":"keep","glyph":"check","cardId":"apple-card","cardShortName":"Apple Card","last4":"5678",
         "line1":"✓ Keep Apple Card ••5678","line2":"Best of your 3 cards here","line3":null,
         "lockScreenText":"Paywise checked this screen"}
        """.utf8)
        let state = try JSONDecoder().decode(State.self, from: json)
        #expect(state == Self.island(DemoChecks.keepDefaultBest(.bundled())))
    }
}
