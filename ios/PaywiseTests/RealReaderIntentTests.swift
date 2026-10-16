import AppIntents
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Paywise

/// Finish line F5: `CheckCheckoutIntent.perform()` with the REAL on-device reader (`VisionScreenReader`: crop, OCR,
/// gate, redaction) on fixtures/screenshots/laptop-checkout.png, and a stubbed backend that answers with
/// fixtures/replay/northbay-electronics_149900.json. The stored record carries the §6.3 Switch copy, and what left the
/// phone carries the merchant and total and nothing that identifies the shopper.
@MainActor
struct RealReaderIntentTests {
    @Test func laptopScreenshotThroughTheRealReaderGivesTheSwitchCopy() async throws {
        let replay = try #require(
            ReplayStore(bundle: .main).response(for: .init(merchantId: "northbay-electronics", totalCents: 149_900)),
            "fixtures/replay/northbay-electronics_149900.json is bundled (project.yml)"
        )
        let screenshot = try #require(DemoScreenshot.all.first { $0.name == "laptop-checkout" }).data()

        let env = TestEnvironment(reading: .notCheckout, route: .init(behavior: .respond(status: 200, body: replay)))
        var deps = env.deps
        deps.screenReader = VisionScreenReader()
        let intent = CheckCheckoutIntent(image: IntentFile(data: screenshot, filename: "laptop-checkout.png", type: .png))
        try await Dependencies.$current.withValue(deps) {
            _ = try await intent.perform()
        }

        // One request left the phone, and the record keeps it.
        #expect(env.requests.count == 1)
        let record = try #require(deps.checkStore.latest(now: Fixtures.demoNow))
        #expect(record.replayed == false)
        #expect(record.parsedResponse.decision?.kind == .switch)

        // §6.3 *Switch, protection*, filled on the phone for demo-3card.
        #expect(record.filledCopy.line1 == "Use Freedom ••1234")
        #expect(record.filledCopy.line2 == "Adds a warranty year + $500 theft cover")
        #expect(record.filledCopy.line3 == "$7.49 less cash back than Active Cash")
        #expect(record.filledCopy.instruction == "Change card to Visa ••1234, then place order")

        // What was sent: the merchant and total, and nothing that identifies the shopper.
        let ocrText = record.sentText
        print("PAYWISE_F5_SENT\n\(ocrText)\nPAYWISE_F5_SENT_END")
        #expect(ocrText.contains("Northbay"))
        #expect(ocrText.contains("$1,499.00"))
        #expect(!ocrText.contains("Alex Doe"))
        #expect(!ocrText.contains("@"))
        #expect(!ocrText.contains("(555)"))
        #expect(PrivacyGuard.longestDigitRun(ocrText) < 12)

        let body = try #require(env.requests.first)
        #expect(PrivacyGuard.longestDigitRun(String(decoding: body, as: UTF8.self)) < 12)
        let sent = try JSONDecoder().decode(CheckRequest.self, from: body)
        #expect(sent.screen.ocrText == ocrText)

        // The snippet path: the activity is ended before the snippet appears.
        #expect(await env.island.events == [.endAll, .startChecking, .end])
    }
}
