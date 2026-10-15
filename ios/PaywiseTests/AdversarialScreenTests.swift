import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Paywise

/// A fake checkout drawn in code, so real Vision OCR splits it the way it splits a real screen: card digit groups far
/// apart come back as separate fragments, a label and its value on one row are joined with two spaces.
/// Fake data only: Alex Doe, the 4111 1111 1111 1111 test number, last 4 1234, (555) 010-0000.
struct SyntheticScreen: Sendable, CustomTestStringConvertible {
    /// Text, x and y of the baseline in points from the top-left, font size in points.
    struct Item: Sendable {
        var text: String
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
    }

    let name: String
    let items: [Item]
    var testDescription: String { name }

    /// A 393 × 852 pt screen at @3x, white with black Helvetica text. Everything sits below the 62 pt top strip.
    func png() throws -> Data {
        let scale: CGFloat = 3
        let width = 1179, height = 2556
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for item in items {
            let font = CTFontCreateWithName("Helvetica" as CFString, item.size * scale, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: item.text, attributes: attributes))
            context.textPosition = CGPoint(x: item.x * scale, y: CGFloat(height) - item.y * scale)
            CTLineDraw(line, context)
        }
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private static func item(_ text: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat = 17) -> Item {
        Item(text: text, x: x, y: y, size: size)
    }

    /// "Checkout" at the top and "Total $18.00" at the bottom, so every screen passes the on-device gate.
    private static func checkout(_ name: String, _ body: [Item]) -> SyntheticScreen {
        SyntheticScreen(name: name, items: [item("Checkout", 20, 120, 30)] + body + [item("Total", 20, 420, 22), item("$18.00", 300, 420, 22)])
    }

    /// The card number as 4 groups `gap` points apart: about 56–68 pt reads as one fragment, 75 pt and more as several.
    private static func cardGroups(gap: CGFloat, size: CGFloat = 22) -> [Item] {
        let groups = ["4111", "1111", "1111", "1111"].enumerated().map { index, group in
            item(group, 20 + CGFloat(index) * gap, 240, size)
        }
        return [item("Card number", 20, 200)] + groups
    }

    static let all: [SyntheticScreen] = [
        checkout("card-gap-62", cardGroups(gap: 62)),
        checkout("card-gap-75", cardGroups(gap: 75)),
        checkout("card-gap-100", cardGroups(gap: 100)),
        checkout("card-four-boxes", cardGroups(gap: 90, size: 17)),
        checkout("card-spaced-dashes", [item("4111 - 1111 - 1111 - 1111", 20, 240, 20)]),
        checkout("card-dots", [item("4111.1111.1111.1111", 20, 240, 20)]),
        checkout("card-two-rows", [item("Card number", 20, 200), item("4111 1111", 20, 240, 22), item("1111 1111", 20, 272, 22)]),
        checkout("name-same-row", [item("Name on card", 20, 200), item("Alex Doe", 250, 200), item("Cardholder", 20, 240), item("Alex Doe", 250, 240),
                                   item("Full name", 20, 280), item("Alex Doe", 250, 280), item("Name", 20, 320), item("Alex Doe", 250, 320)]),
        checkout("contact-block", [item("Contact", 20, 200), item("Alex Doe", 20, 230), item("alex@example.com", 20, 260), item("(555) 010-0000", 20, 290)]),
        checkout("shipping-block", [item("Shipping", 20, 200), item("Alex Doe", 20, 230), item("123 Example St", 20, 260),
                                    item("Seattle, Washington 98000", 20, 290), item("Standard Shipping", 20, 330), item("Free", 330, 330)]),
        checkout("last4-periods", [item("Paid with", 20, 200), item("Visa . .1234", 250, 200)]),
        checkout("signed-in-and-phones", [item("Signed in as Alex Doe", 20, 200), item("Account: Alex Doe", 20, 240),
                                          item("+15550100000", 20, 280), item("555 . 010 . 0000", 20, 310)]),
    ]
}

/// Verifier findings on the OCR + redaction step (SPEC §10, §15.7 step 8), run through the real reader on the simulator.
@Suite(.serialized)
struct AdversarialScreenTests {
    let reader = VisionScreenReader()

    @Test(arguments: SyntheticScreen.all)
    func nothingIdentifyingSurvives(_ screen: SyntheticScreen) async throws {
        let reading = try await reader.read(try screen.png())
        let text = reading.redactedText
        print("PAYWISE_ADV \(screen.name) checkout=\(reading.isCheckout) redactions=\(reading.redactions)\n\(text)\nPAYWISE_ADV_END")

        #expect(Redactor.longestDigitRun(in: text) < 12)
        #expect(!text.contains("4111"))
        #expect(!text.contains("1111"))
        #expect(!text.contains("1234"), "no last 4")
        #expect(!text.contains("Alex"))
        #expect(!text.contains("alex"))
        #expect(!text.contains("Doe"))
        #expect(!text.contains("@"))
        #expect(!text.contains("555"))
        #expect(!text.contains("010"))
        #expect(!text.contains("Example St"))
        #expect(!text.contains("Seattle"))
        #expect(!text.contains("98000"))

        // The gate still passes and the total is still there for the backend.
        #expect(reading.isCheckout)
        #expect(CheckoutGate.evaluate(text: text).total == "$18.00")
    }
}
