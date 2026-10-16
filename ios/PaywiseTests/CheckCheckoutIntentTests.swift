import AppIntents
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Paywise

/// `CheckCheckoutIntent.perform()` end to end with a fixture reader and a stubbed backend (SPEC §15.5 steps 1–7).
@MainActor
struct CheckCheckoutIntentTests {
    @Test func laptopCheckoutWritesSwitchProtectionRecord() async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample()))
        )
        try await env.perform(TestEnvironment.screenshot())

        let record = try #require(env.deps.checkStore.latest(now: Fixtures.demoNow))
        let decision = try #require(record.parsedResponse.decision)
        #expect(decision.kind == .switch)
        #expect(decision.reason == .protection)
        #expect(record.filledCopy.line1 == "Use Freedom ••1234")
        #expect(record.filledCopy.line2 == "Adds a warranty year + $500 theft cover")
        #expect(record.filledCopy.line3 == "$7.49 less cash back than Active Cash")
        #expect(record.filledCopy.instruction == "Change card to Visa ••1234, then place order")
        #expect(record.replayed == false)
        #expect(record.savedPurchaseId == nil)
        #expect(record.view == .result)
        #expect(record.createdAt == "2026-10-17T14:02:11-07:00")
        #expect(record.sentText == (try Fixtures.laptopReading()).redactedText)

        // The snippet path: the activity is ended before the snippet appears, and nothing alerted.
        #expect(await env.island.events == [.endAll, .startChecking, .end])
    }

    @Test func requestBodyHasNoLast4AndNoLongDigitRun() async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample()))
        )
        try await env.perform(TestEnvironment.screenshot())

        let body = try #require(env.requests.first)
        #expect(env.requests.count == 1)
        let text = try #require(String(data: body, encoding: .utf8))
        #expect(PrivacyGuard.longestDigitRun(text) < 12)
        #expect(!text.contains("last4"))
        #expect(!text.contains("••"))

        var object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let requestId = try #require(object["requestId"] as? String)
        object["requestId"] = nil
        let withoutId = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        for last4 in ["1234", "5678", "4321"] {
            #expect(!withoutId.contains(last4), "last 4 \(last4) left the phone")
        }

        let cards = try #require((object["wallet"] as? [String: Any])?["cards"] as? [[String: Any]])
        #expect(cards.map { Set($0.keys) } == Array(repeating: ["cardId", "isDefault"], count: 3))
        #expect(cards.map { $0["cardId"] as? String } == ["apple-card", "wf-active-cash", "chase-freedom-unlimited"])
        #expect(cards.map { $0["isDefault"] as? Bool } == [true, false, false])
        #expect(Set(object.keys) == ["client", "clientDate", "screen", "wallet", "prefs"])
        #expect(object["clientDate"] as? String == "2026-10-17")
        #expect((object["client"] as? [String: Any])?["app"] as? String == "paywise-ios")
        #expect((object["prefs"] as? [String: Any])?["paysInFull"] is NSNull)
        let screen = try #require(object["screen"] as? [String: Any])
        #expect(Set(screen.keys) == ["ocrText", "redactions", "ocrConfidence"])

        // The record keeps the exact payload, and the check ID is the request ID.
        let record = try #require(env.deps.checkStore.record(id: requestId))
        #expect(record.sentPayload == (try JSONValue(data: body)))
    }

    @Test func timeoutShowsCouldntCheck() async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample()), delay: 5),
            timeout: .milliseconds(300)
        )
        let clock = ContinuousClock()
        let start = clock.now
        try await env.perform(TestEnvironment.screenshot())
        #expect(clock.now - start < .seconds(3))

        let alert = try #require(await env.island.alerts.first)
        #expect(alert.phase == .error)
        #expect(alert.glyph == .warning)
        #expect(alert.line1 == "Couldn't check this time")
        #expect(alert.line2 == "Took too long · press again")
        #expect(alert.lockScreenText == "Paywise checked this screen")
        #expect(await env.island.events.last == .end)
        // silentAlerts defaults to on.
        #expect(await env.island.events.contains(.alert(alert, .silent)))

        let record = try #require(env.deps.checkStore.latest(now: Fixtures.demoNow))
        #expect(record.parsedResponse.decision?.kind == .error)
        #expect(record.parsedResponse.error?.code == .timeout)
        #expect(record.replayed == false)
    }

    @Test func offlineShowsNoConnection() async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .fail(.notConnectedToInternet))
        )
        try await env.perform(TestEnvironment.screenshot())

        let alert = try #require(await env.island.alerts.first)
        #expect(alert.line1 == "Couldn't check this time")
        #expect(alert.line2 == "No connection · press again")
    }

    @Test(arguments: [
        StubURLProtocol.Behavior.fail(.notConnectedToInternet),
        .respond(status: 503, body: Data("{}".utf8)),
    ])
    func replayHitAfterFailure(behavior: StubURLProtocol.Behavior) async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: behavior),
            replayEnabled: true
        )
        try await env.perform(TestEnvironment.screenshot())

        #expect(env.requests.count == 1)
        let record = try #require(env.deps.checkStore.latest(now: Fixtures.demoNow))
        #expect(record.replayed)
        #expect(record.parsedResponse.decision?.kind == .switch)
        #expect(record.filledCopy.line1 == "Use Freedom ••1234")
        #expect(await env.island.events == [.endAll, .startChecking, .end])
    }

    @Test func replayOffMeansCouldntCheck() async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .fail(.notConnectedToInternet)),
            replayEnabled: false
        )
        try await env.perform(TestEnvironment.screenshot())
        let record = try #require(env.deps.checkStore.latest(now: Fixtures.demoNow))
        #expect(!record.replayed)
        #expect(record.parsedResponse.decision?.kind == .error)
    }

    @Test func notCheckoutUploadsNothing() async throws {
        let env = TestEnvironment(
            reading: .notCheckout,
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample()))
        )
        try await env.perform(TestEnvironment.screenshot())

        #expect(env.requests.isEmpty)
        #expect(env.deps.checkStore.all().isEmpty)
        let alert = try #require(await env.island.alerts.first)
        #expect(alert.phase == .noCheckout)
        #expect(alert.line1 == "No checkout total found")
        #expect(alert.line2 == "Nothing left your phone")
        #expect(alert.line3 == "Scroll to the total and press again")
        #expect(await env.island.events.first == .endAll)
        #expect(await env.island.events.last == .end)
    }

    @Test func noImageIsNotSetUp() async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample()))
        )
        try await env.perform(CheckCheckoutIntent(image: nil))

        #expect(env.requests.isEmpty)
        #expect(env.deps.checkStore.all().isEmpty)
        #expect(await env.island.events == [.endAll])
    }

    @Test func islandModeShowsSwitchFallback() async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample())),
            snippetMode: .island
        )
        try await env.perform(TestEnvironment.screenshot())

        let events = await env.island.events
        guard case .alert(let state, let sound) = events.dropFirst(2).first else {
            Issue.record("expected an island alert, got \(events)")
            return
        }
        #expect(state.phase == .switchFallback)
        #expect(state.line1 == "Use Freedom ••1234")
        #expect(state.line3 == "$7.49 less cash back than Active Cash")
        #expect(state.cardShortName == "Freedom")
        #expect(state.cardId == "chase-freedom-unlimited")
        #expect(state.last4 == "1234")
        #expect(sound == .standard)
        #expect(events.last == .end)
    }

    @Test func readerFailureSendsNothing() async throws {
        let env = TestEnvironment(
            reading: .notCheckout,
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample()))
        )
        var deps = env.deps
        deps.screenReader = UnavailableScreenReader()
        try await Dependencies.$current.withValue(deps) {
            _ = try await TestEnvironment.screenshot().perform()
        }
        #expect(env.requests.isEmpty)
        #expect(env.deps.checkStore.all().isEmpty)
        // §6.3 *No checkout, on device*: no total was read and nothing left the phone.
        let alert = try #require(await env.island.alerts.first)
        #expect(alert.phase == .noCheckout)
        #expect(alert.line1 == "No checkout total found")
        #expect(alert.line2 == "Nothing left your phone")
        #expect(alert.line3 == "Scroll to the total and press again")
    }

    /// A Vision confidence is a Float; widened to Double it would put a 16-digit run in the body (§9.2).
    @Test func floatConfidenceIsRoundedBeforeSending() async throws {
        var reading = try Fixtures.laptopReading()
        reading.ocrConfidence = Double(Float(0.93))
        let env = TestEnvironment(
            reading: reading,
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample()))
        )
        try await env.perform(TestEnvironment.screenshot())

        let body = try #require(env.requests.first)
        let text = String(decoding: body, as: UTF8.self)
        #expect(PrivacyGuard.longestDigitRun(text) <= PrivacyGuard.maxDigitRun)
        #expect(PrivacyGuard.isSendable(body))
        #expect(text.contains(#""ocrConfidence":0.93"#))
    }

    /// The demo store's card labels reach the phone's text as "••5678" etc.; none of it may leave (§10).
    @Test func demoStoreCardLabelsNeverLeaveThePhone() async throws {
        var reading = try Fixtures.laptopReading()
        reading.redactedText = reading.redactedText.replacing("Mastercard [CARD]", with: "Mastercard ••5678")
            + "\nVisa ••4321\nVisa ending in 1234\nCard 1234 5678 9012 3456"
        reading.redactions = []
        reading.ocrConfidence = Double(Float(0.93))
        let env = TestEnvironment(
            reading: reading,
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample()))
        )
        try await env.perform(TestEnvironment.screenshot())

        let body = try #require(env.requests.first)
        var object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        object["requestId"] = nil
        let withoutId = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        for last4 in ["1234", "5678", "4321"] {
            #expect(!withoutId.contains(last4), "last 4 \(last4) left the phone")
        }
        let screen = try #require(object["screen"] as? [String: Any])
        let ocrText = try #require(screen["ocrText"] as? String)
        #expect(!ocrText.contains("••"))
        #expect(ocrText.contains("Pay with Mastercard [CARD]"))
        #expect(ocrText.hasSuffix("Visa [CARD]\nVisa [CARD]\nCard [CARD]"))
        #expect(screen["redactions"] as? [String] == ["card_number"])
        #expect(PrivacyGuard.longestDigitRun(String(decoding: body, as: UTF8.self)) <= PrivacyGuard.maxDigitRun)
        // The total survives, so the backend (and replay) can still read it.
        #expect(ReplayStore.key(for: ocrText, catalog: .bundled()) == .init(merchantId: "northbay-electronics", totalCents: 149_900))
    }

    /// A body that would break the backend's privacy rule is never sent (here a tampered wallet card ID).
    @Test func bodyFailingThePrivacyRuleIsNeverSent() async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample())),
            wallet: Wallet(cards: [.init(cardId: "card-123456789012", isDefault: true, last4: nil)])
        )
        try await env.perform(TestEnvironment.screenshot())

        #expect(env.requests.isEmpty)
        #expect(env.deps.checkStore.all().isEmpty)
        let alert = try #require(await env.island.alerts.first)
        #expect(alert.line1 == "No checkout total found")
        #expect(alert.line2 == "Nothing left your phone")
        #expect(await env.island.events.last == .end)
    }

    /// Pattern B needs a card name for its verb; without one it falls back to §6.6's static snippet.
    @Test func confirmWithoutCardNameShowsStaticSnippet() async throws {
        var response = try #require(try JSONSerialization.jsonObject(with: Fixtures.responseExample()) as? [String: Any])
        var decision = try #require(response["decision"] as? [String: Any])
        var copy = try #require(decision["copy"] as? [String: Any])
        decision["recommendedCardId"] = "unknown-card"
        copy["primaryButton"] = nil
        decision["copy"] = copy
        response["decision"] = decision
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 200, body: try JSONSerialization.data(withJSONObject: response))),
            snippetMode: .confirm
        )
        let outcome = await Dependencies.$current.withValue(env.deps) {
            await CheckFlow(deps: env.deps).run(imageData: Data([0x89]))
        }
        guard case .snippet = outcome else {
            Issue.record("expected the static snippet, got \(outcome)")
            return
        }
    }
}
