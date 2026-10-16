import Foundation
import Testing
@testable import Paywise

private final class ScreenshotBundleToken {}

/// One of the 7 demo-store screenshots in fixtures/screenshots (SPEC §15.4), bundled into this test target.
struct DemoScreenshot: Sendable, CustomTestStringConvertible {
    let name: String
    /// The order total the reading must keep, or nil for screens without one.
    let total: String?
    /// Whether the merchant name must survive.
    let hasMerchant: Bool
    /// Expected on-device gate result; nil means "rejected, or passes without a readable total" (blurry).
    let passesGate: Bool?

    var testDescription: String { name }

    static let all: [DemoScreenshot] = [
        DemoScreenshot(name: "laptop-checkout", total: "$1,499.00", hasMerchant: true, passesGate: true),
        DemoScreenshot(name: "laptop-renewed-checkout", total: "$1,099.00", hasMerchant: true, passesGate: true),
        DemoScreenshot(name: "earbuds-checkout", total: "$249.00", hasMerchant: true, passesGate: true),
        DemoScreenshot(name: "mug-checkout", total: "$18.00", hasMerchant: true, passesGate: true),
        // Order confirmations are sent on purpose: the backend answers "Already paid?" (§6.3).
        DemoScreenshot(name: "laptop-confirmation", total: "$1,499.00", hasMerchant: true, passesGate: true),
        DemoScreenshot(name: "feed-not-checkout", total: nil, hasMerchant: false, passesGate: false),
        DemoScreenshot(name: "blurry-unreadable", total: nil, hasMerchant: false, passesGate: nil),
    ]

    func data() throws -> Data {
        let url = try #require(Bundle(for: ScreenshotBundleToken.self).url(forResource: name, withExtension: "png"),
                               "\(name).png is bundled into PaywiseTests (project.yml)")
        return try Data(contentsOf: url)
    }
}

/// SPEC §15.7 step 8 "done when", on the 7 demo screenshots: merchant + total kept, no status-bar text,
/// 0 digit runs ≥12, 0 emails, 0 phones, 0 names or address lines, no last 4, feed rejected on device.
/// Serialized so the timing test measures one OCR at a time.
@Suite(.serialized)
struct ScreenshotReadingTests {
    let reader = VisionScreenReader()

    @Test(arguments: DemoScreenshot.all)
    func readsAndRedacts(_ shot: DemoScreenshot) async throws {
        let reading = try await reader.read(try shot.data())
        let text = reading.redactedText
        print("PAYWISE_OCR \(shot.name) checkout=\(reading.isCheckout) confidence=\(String(format: "%.2f", reading.ocrConfidence)) redactions=\(reading.redactions)\n\(text)\nPAYWISE_OCR_END")

        // Nothing that identifies the shopper or the card.
        #expect(Redactor.longestDigitRun(in: text) < 12)
        #expect(!matches(#"[A-Za-z0-9._%+\-]+ ?@ ?[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, text), "no email")
        #expect(!text.contains("@"))
        #expect(!matches(#"\(?[0-9]{3}\)?[ .\-–]?[0-9]{3}[ .\-–][0-9]{4}"#, text), "no phone number")
        #expect(!text.contains("555"))
        #expect(!text.contains("Alex"), "no name, not even the first name")
        #expect(!text.contains("Doe"))
        #expect(!text.contains("123 Example St"))
        #expect(!text.contains("Example St"))
        #expect(!text.contains("Seattle"))
        #expect(!text.contains("98000"))
        #expect(!matches(#"(?i)(visa|master ?card|amex|discover)\W{0,6}(5678|4321|1234)"#, text), "no last 4 next to a network")
        for last4 in ["5678", "4321", "1234"] {
            #expect(!text.contains(last4), "last 4 \(last4) never leaves")
        }

        // The status strip is cropped: no time, carrier or battery.
        #expect(!text.contains("9:41"))
        #expect(!matches(#"(?m)^\s*0?9:41"#, text))
        #expect(!text.contains("100%"))

        // What the backend needs is kept.
        if shot.hasMerchant {
            #expect(text.localizedCaseInsensitiveContains("Northbay"), "merchant kept")
        }
        if let total = shot.total {
            #expect(text.contains(total), "total \(total) kept")
            #expect(CheckoutGate.evaluate(text: text).total == total, "the total line reads \(total)")
        }

        // The on-device gate.
        switch shot.passesGate {
        case true?:
            #expect(reading.isCheckout)
        case false?:
            #expect(!reading.isCheckout, "rejected on device: nothing is uploaded")
        case nil:
            #expect(!reading.isCheckout || CheckoutGate.evaluate(text: text).total == nil, "blurry: rejected, or no total read")
        }

        if shot.passesGate == true && shot.name.hasSuffix("checkout") {
            #expect(reading.redactions == ["card_number", "address", "email", "phone", "name"])
            #expect(reading.ocrConfidence > 0.5)
        }
    }

    /// Read + redact time per image. Target p50 ≤400 ms inside the background intent on the phone (§9.4, §15.7 step 8);
    /// this prints the simulator's number, which runs Vision on the Mac's CPU/GPU, not the phone's Neural Engine.
    /// Not yet measured on the phone. For scale (2026-10-15, same 7 crops): simulator p50 417–602 ms depending on load;
    /// the same Vision request run natively on the Mac, p50 78 ms, and 75 ms at @2x (so downscaling buys nothing there
    /// and changes the OCR text).
    @Test func readTimeP50() async throws {
        let images = try DemoScreenshot.all.map { try $0.data() }

        let coldStart = ContinuousClock.now
        _ = try await reader.read(images[0])
        let cold = coldStart.duration(to: .now)

        var samples: [Duration] = []
        for _ in 0..<3 {
            for image in images {
                let start = ContinuousClock.now
                _ = try await reader.read(image)
                samples.append(start.duration(to: .now))
            }
        }
        samples.sort()
        let p50 = samples[samples.count / 2]
        let p90 = samples[(samples.count * 9) / 10]
        print("PAYWISE_OCR_TIMING cold=\(milliseconds(cold)) ms p50=\(milliseconds(p50)) ms p90=\(milliseconds(p90)) ms max=\(milliseconds(samples.last!)) ms n=\(samples.count)")

        // Sanity bound only; the 400 ms target is checked on the device (docs/spikes.md).
        #expect(p50 < .seconds(5))
    }

    private func milliseconds(_ duration: Duration) -> Int {
        Int(Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15)
    }

    private func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
