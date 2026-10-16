import CoreGraphics
import Foundation
import Testing
@testable import Paywise

/// Pure string tests for on-device redaction (SPEC §10, §15.7 step 8). All data is the fake identity from §15.4.
struct RedactorTests {
    private func redact(_ line: String) -> String { Redactor.redact(line).text }

    // MARK: Card numbers

    @Test(arguments: [
        "4111 1111 1111 1111",      // Luhn-valid, spaces
        "4111-1111-1111-1111",      // Luhn-valid, dashes
        ["4111", "1111", "1111", "1111"].joined(),  // Luhn-valid, plain (built here, never stored whole)
        "3782 822463 10005",        // 15-digit, Amex grouping
        "1234 5678 9012",           // 12 digits, not Luhn-valid: still a card number by length
        // ReadingOrder joins separate OCR fragments of one row with two spaces (verifier finding 5).
        "4111  1111  1111  1111",
        "4111 1111  1111  1111",
        "4111 -  1111  -  1111  -  1111",
        "4111 - 1111 - 1111 - 1111",
        "4111.1111.1111.1111",
        "4111—1111—1111—1111",
    ])
    func longDigitRunsBecomeCard(_ number: String) {
        let result = Redactor.redact("Card number " + number)
        #expect(result.text == "Card number [CARD]")
        #expect(result.kinds == ["card_number"])
        #expect(Redactor.longestDigitRun(in: result.text) < 12)
    }

    @Test func cardNumberSplitOverRows() {
        let result = Redactor.redact(lines: ["Card number 4111 1111", "1111 1111", "Total  $18.00"])
        #expect(result.lines == ["Card number [CARD]", "[CARD]", "Total  $18.00"])
        #expect(result.kinds == ["card_number"])
        #expect(Redactor.longestDigitRun(in: result.text) < 12)

        let groups = Redactor.redact(lines: ["4111", "1111", "1111", "1111"])
        #expect(groups.lines == ["[CARD]", "[CARD]", "[CARD]", "[CARD]"])
    }

    @Test func zipAbovePhoneIsNotACard() {
        let result = Redactor.redact(lines: ["Seattle, WA 98000", "555-010-0000"])
        #expect(result.lines == ["[ADDRESS]", "[PHONE]"])
        #expect(result.kinds == ["address", "phone"])
    }

    @Test func centsNextToDigitsKeepThePrice() {
        // The decimal point before cents is not a separator, so the total survives next to other digits.
        #expect(redact("Total  $18.00  1234 5678").hasPrefix("Total  $18.00"))
    }

    @Test func luhn() {
        #expect(Redactor.isLuhnValid("4111 1111 1111 1111"))
        #expect(Redactor.isLuhnValid(["3782", "822463", "10005"].joined()))
        #expect(!Redactor.isLuhnValid("4111 1111 1111 1112"))
        #expect(!Redactor.isLuhnValid("1"))
    }

    @Test func longestDigitRunCountsAcrossSeparators() {
        #expect(Redactor.longestDigitRun(in: "4111 1111 1111 1111") == 16)
        #expect(Redactor.longestDigitRun(in: "4111  1111  1111  1111") == 16)
        #expect(Redactor.longestDigitRun(in: "4111 - 1111 - 1111 - 1111") == 16)
        #expect(Redactor.longestDigitRun(in: "4111 1111\n1111 1111") == 16)
        #expect(Redactor.longestDigitRun(in: "4111      1111") == 4, "6 spaces end a run")
        #expect(Redactor.longestDigitRun(in: "Total  $1,499.00") == 5)
        #expect(Redactor.longestDigitRun(in: "(555) 010-0000") == 7)
        #expect(Redactor.longestDigitRun(in: "Order #NB-100234") == 6)
    }

    // MARK: Last 4

    @Test(arguments: [
        ("Visa ending in 1234", "Visa ending in [CARD]"),
        ("Card ends in 4321", "Card ends in [CARD]"),
        ("Mastercard ••5678", "Mastercard [CARD]"),
        ("Pay with  Mastercard • •5678  Change", "Pay with  Mastercard [CARD]  Change"),
        ("Paid with  Visa • • 1234", "Paid with  Visa [CARD]"),
        ("Visa **** 4321", "Visa [CARD]"),
        ("**** 4321", "[CARD]"),
        ("Account x1234", "Account [CARD]"),
        ("Mastercard 5678", "Mastercard [CARD]"),
        ("Amex ...1234", "Amex [CARD]"),
        ("Paid with  Visa . .1234", "Paid with  Visa [CARD]"),   // OCR reads the bullets as periods
        ("Paid with  Visa . . 1234", "Paid with  Visa [CARD]"),
        ("Last 4: 5678", "Last 4 [CARD]"),
        ("card no. ************1234", "card no [CARD]"),
    ])
    func lastFourBecomesCard(_ input: String, _ expected: String) {
        let result = Redactor.redact(input)
        #expect(result.text == expected)
        #expect(result.kinds == ["card_number"])
        for last4 in ["1234", "4321", "5678"] {
            #expect(!result.text.contains(last4))
        }
    }

    // MARK: Email and phone

    @Test func emailAndPhoneOnOneLine() {
        let result = Redactor.redact("alex@example.com · (555) 010-0000")
        #expect(result.text == "[EMAIL] · [PHONE]")
        #expect(result.kinds == ["email", "phone"])
    }

    @Test(arguments: ["(555) 010-0000", "555-010-0000", "555.010.0000", "+1 555 010 0000", "5550100000", "(555) 010–0000",
                      "+15550100000", "555 . 010 . 0000", "555. .010.0000", "555—010—0000", "1-555-010-0000", "+1 (555) 010-0000"])
    func phoneFormats(_ phone: String) {
        let result = Redactor.redact("Call " + phone)
        #expect(result.text == "Call [PHONE]")
        #expect(result.kinds == ["phone"])
    }

    @Test(arguments: ["alex@example.com", "alex.doe+orders@example.com", "ALEX@EXAMPLE.COM", "alex_doe@mail.example.co.uk"])
    func emailFormats(_ email: String) {
        #expect(redact("Contact " + email) == "Contact [EMAIL]")
    }

    @Test func spacedEmailFromOCR() {
        #expect(redact("alex doe @ example . com") == "[EMAIL]")
        #expect(redact("Email  alex doe @ example . com") == "Email  [EMAIL]")
        #expect(redact("alex @ example.com") == "[EMAIL]")
    }

    // MARK: Names and addresses

    @Test func shipToBlock() {
        let result = Redactor.redact(lines: [
            "Ship to",
            "Alex Doe",
            "123 Example St, Seattle, WA 98000",
            "Free delivery in 2–4 days",
            "Contact",
        ])
        #expect(result.lines == ["Ship to", "[NAME]", "[ADDRESS]", "Free delivery in 2–4 days", "Contact"])
        #expect(result.kinds == ["address", "name"])
    }

    @Test func multiLineAddressBlock() {
        let result = Redactor.redact(lines: [
            "Shipping address", "Alex Doe", "123 Example St", "Apt 4", "Seattle, WA 98000", "Total  $18.00",
        ])
        #expect(result.lines == ["Shipping address", "[NAME]", "[ADDRESS]", "[ADDRESS]", "[ADDRESS]", "Total  $18.00"])
    }

    @Test(arguments: [
        ("Ship to: Alex Doe, 123 Example St", "Ship to [ADDRESS]"),
        ("Deliver to Alex Doe - Seattle 98000", "Deliver to [ADDRESS]"),
        ("Name: Alex Doe", "Name [NAME]"),
        ("Billing address: 123 Example St, Seattle, WA 98000", "Billing address [ADDRESS]"),
    ])
    func headerWithContentOnSameLine(_ input: String, _ expected: String) {
        #expect(redact(input) == expected)
    }

    /// Label and value on one row, as ReadingOrder joins two columns (verifier finding 5).
    @Test(arguments: [
        ("Name on card  Alex Doe", "Name on card [NAME]"),
        ("Cardholder  Alex Doe", "Cardholder [NAME]"),
        ("Cardholder name: Alex Doe", "Cardholder name [NAME]"),
        ("Full name  Alex Doe", "Full name [NAME]"),
        ("Name on card  alex doe", "Name on card [NAME]"),
        ("Name  Alex Doe", "Name [NAME]"),
        ("Name Alex Doe", "Name [NAME]"),
        ("Account: Alex Doe", "Account [NAME]"),
        ("Contact  Alex Doe", "Contact [NAME]"),
        ("Ship to  Alex Doe", "Ship to [NAME]"),
        ("Signed in as Alex Doe", "Signed in as [NAME]"),
        ("Logged in as alex", "Logged in as [NAME]"),
    ])
    func nameOnTheSameRow(_ input: String, _ expected: String) {
        let result = Redactor.redact(input)
        #expect(result.text == expected)
        #expect(result.kinds == ["name"])
    }

    @Test func contactBlockTakesTheName() {
        let result = Redactor.redact(lines: ["Contact", "Alex Doe", "alex@example.com", "(555) 010-0000", "Pay with  Visa ••1234"])
        #expect(result.lines == ["Contact", "[NAME]", "[EMAIL]", "[PHONE]", "Pay with  Visa [CARD]"])
        #expect(result.kinds == ["card_number", "email", "phone", "name"])
    }

    @Test func shippingBlockTakesNameAndAddress() {
        let result = Redactor.redact(lines: ["Shipping", "Alex Doe", "123 Example St", "Seattle, Washington 98000", "Total  $18.00"])
        #expect(result.lines == ["Shipping", "[NAME]", "[ADDRESS]", "[ADDRESS]", "Total  $18.00"])
    }

    @Test func softBlockKeepsShopText() {
        let lines = ["Shipping", "Standard Shipping  Free", "Pay with", "Apple Pay", "Account", "Northbay Electronics", "Total  $18.00"]
        let result = Redactor.redact(lines: lines)
        #expect(result.lines == lines)
        #expect(result.kinds.isEmpty)
    }

    @Test func zipLineInsideABlock() {
        let result = Redactor.redact(lines: ["Ship to", "Alex Doe", "123 Example St", "Seattle Washington 98000", "Arrives Friday"])
        #expect(result.lines == ["Ship to", "[NAME]", "[ADDRESS]", "[ADDRESS]", "Arrives Friday"])
    }

    @Test func nameRightAboveAnAddress() {
        #expect(Redactor.redact(lines: ["Alex Doe", "123 Example St, Seattle, WA 98000"]).lines == ["[NAME]", "[ADDRESS]"])
        // A store name above a pickup address stays: the backend matches merchants by name.
        #expect(Redactor.redact(lines: ["Pickup at", "Best Buy", "123 Example St"]).lines == ["Pickup at", "Best Buy", "[ADDRESS]"])
    }

    @Test func nameHeaderBlock() {
        let result = Redactor.redact(lines: ["Name", "Alex Doe", "Email", "alex@example.com"])
        #expect(result.lines == ["Name", "[NAME]", "Email", "[EMAIL]"])
        #expect(result.kinds == ["email", "name"])
    }

    @Test func deliverToBlockFirstLineAlwaysGoes() {
        // Whatever follows the header is treated as personal, even if it doesn't look like a name.
        let result = Redactor.redact(lines: ["Deliver to", "alex doe home", "Arrives Friday"])
        #expect(result.lines == ["Deliver to", "[ADDRESS]", "Arrives Friday"])
    }

    @Test(arguments: ["123 Example St, Seattle, WA 98000", "Seattle, WA 98000", "4 Main Street", "WA 98000-1234",
                      "Seattle, Washington 98000", "SEATTLE, WA 98000"])
    func addressLinesAnywhere(_ line: String) {
        let result = Redactor.redact(lines: ["Northbay Electronics", line])
        #expect(result.lines == ["Northbay Electronics", "[ADDRESS]"])
        #expect(result.kinds == ["address"])
    }

    @Test func greetingName() {
        #expect(redact("Thank you, Alex.") == "Thank you, [NAME].")
        #expect(redact("Hi Alex Doe") == "Hi [NAME]")
        #expect(redact("Thank you for your order") == "Thank you for your order")
    }

    // MARK: What must survive

    @Test(arguments: [
        "Northbay Electronics",
        "Aero 14 Laptop, 14-inch  $1,499.00",
        "Renewed · no warranty",
        "Ceramic Coffee Mug, 12 oz  $18.00",
        "Total  $1,499.00",
        "Total  $1499.00",
        "Order #NB-100234",
        "Qty 1",
        "Free delivery in 2–4 days",
        "Place order",
        "Shipping  Free",
        "Name brand headphones  $90.00",
        "Standard Shipping  Free",
        "Contact us",
        "Arrives Oct 17 – Oct 19",
        "Approved • Mock payment, no money moved -",
        "txn MOCK-7QX2K9PL",
        "Wireless Earbuds,  $249.00",
        "Renewed • no warranty",
    ])
    func orderSummaryIsKept(_ line: String) {
        let result = Redactor.redact(line)
        #expect(result.text == line)
        #expect(result.kinds.isEmpty)
    }

    /// The §15.5 request example, before redaction.
    @Test func specExampleScreen() {
        let screen = """
        Northbay Electronics
        Checkout
        Aero 14 Laptop, 14-inch (New)  $1,499.00
        Total  $1,499.00
        Pay with Mastercard ••5678
        Change
        Ship to
        Alex Doe
        123 Example St, Seattle, WA 98000
        alex@example.com · (555) 010-0000
        Place order
        """
        let result = Redactor.redact(screen)
        #expect(result.text == """
        Northbay Electronics
        Checkout
        Aero 14 Laptop, 14-inch (New)  $1,499.00
        Total  $1,499.00
        Pay with Mastercard [CARD]
        Change
        Ship to
        [NAME]
        [ADDRESS]
        [EMAIL] · [PHONE]
        Place order
        """)
        #expect(result.kinds == ["card_number", "address", "email", "phone", "name"])
    }
}

struct CheckoutGateTests {
    @Test func checkoutPasses() {
        let verdict = CheckoutGate.evaluate(text: "Checkout\nAero 14 Laptop  $1,499.00\nTotal  $1,499.00\nPlace order")
        #expect(verdict.total == "$1,499.00")
        #expect(verdict.passes)
    }

    @Test func totalOnTheNextLine() {
        let verdict = CheckoutGate.evaluate(lines: ["Order total", "$ 18.00", "Pay now"])
        #expect(verdict.total == "$18.00")
        #expect(verdict.passes)
    }

    @Test func orderConfirmationPassesSoTheBackendCanSayAlreadyPaid() {
        let verdict = CheckoutGate.evaluate(lines: ["Order placed", "Thank you, [NAME].", "Order #NB-100234", "Total  $1,499.00"])
        #expect(verdict.passes)
    }

    @Test func feedFails() {
        let verdict = CheckoutGate.evaluate(lines: ["Feed", "Jordan Sample", "2h", "128 likes · 14 comments"])
        #expect(verdict.total == nil)
        #expect(!verdict.passes)
    }

    @Test func keywordWithoutTotalFails() {
        #expect(!CheckoutGate.evaluate(lines: ["Checkout", "Your bag is empty", "Place order"]).passes)
    }

    @Test func subtotalIsNotATotal() {
        #expect(CheckoutGate.evaluate(lines: ["Subtotal  $40.00", "Checkout"]).total == nil)
    }

    @Test func totalWithoutKeywordFails() {
        let verdict = CheckoutGate.evaluate(lines: ["Running total  $40.00", "Nice weather"])
        #expect(verdict.total == "$40.00")
        #expect(!verdict.passes)
    }
}

struct TopStripCropTests {
    @Test(arguments: [(1179, 2556, 3), (1206, 2622, 3), (1290, 2796, 3), (1125, 2436, 3), (828, 1792, 2), (750, 1334, 2), (320, 568, 1)])
    func scaleFromPixelWidth(_ width: Int, _ height: Int, _ scale: Int) {
        #expect(TopStripCrop.scale(pixelWidth: width, pixelHeight: height) == scale)
        #expect(TopStripCrop.cropPixels(pixelWidth: width, pixelHeight: height) == 62 * scale)
    }

    @Test func cropRemovesTheTopRows() throws {
        // 30 × 400 px grey image (@1x): the top 62 rows are black (the "status bar"), the rest white.
        let width = 30, height = 400
        var pixels = [UInt8](repeating: 255, count: width * height)
        for index in 0..<(62 * width) { pixels[index] = 0 }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))

        let cropped = try #require(TopStripCrop.crop(image))
        #expect(cropped.width == width)
        #expect(cropped.height == height - 62)

        var out = [UInt8](repeating: 0, count: cropped.width * cropped.height)
        let context = try #require(CGContext(data: &out, width: cropped.width, height: cropped.height, bitsPerComponent: 8,
                                             bytesPerRow: cropped.width, space: CGColorSpaceCreateDeviceGray(),
                                             bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        #expect(out.allSatisfy { $0 == 255 }, "no black status-bar rows survive the crop")
    }

    @Test func tooSmallImageIsRejected() {
        #expect(TopStripCrop.keptRect(pixelWidth: 300, pixelHeight: 62) == nil)
    }
}

struct ReadingOrderTests {
    /// A card number drawn as four separate boxes comes out of OCR as four fragments on one row; ReadingOrder joins
    /// them with two spaces and the Redactor must still catch it (verifier finding 5).
    @Test func cardNumberInFourFragmentsIsRedacted() {
        let fragments = [
            OCRFragment(text: "Checkout", box: CGRect(x: 0.05, y: 0.05, width: 0.3, height: 0.03), confidence: 1),
            OCRFragment(text: "Card number", box: CGRect(x: 0.05, y: 0.10, width: 0.3, height: 0.02), confidence: 1),
            OCRFragment(text: "1111", box: CGRect(x: 0.75, y: 0.15, width: 0.12, height: 0.025), confidence: 1),
            OCRFragment(text: "4111", box: CGRect(x: 0.05, y: 0.15, width: 0.12, height: 0.025), confidence: 1),
            OCRFragment(text: "1111", box: CGRect(x: 0.28, y: 0.152, width: 0.12, height: 0.025), confidence: 1),
            OCRFragment(text: "1111", box: CGRect(x: 0.51, y: 0.149, width: 0.12, height: 0.025), confidence: 1),
            OCRFragment(text: "Name on card", box: CGRect(x: 0.05, y: 0.20, width: 0.3, height: 0.02), confidence: 1),
            OCRFragment(text: "Alex Doe", box: CGRect(x: 0.60, y: 0.20, width: 0.3, height: 0.02), confidence: 1),
            OCRFragment(text: "Total", box: CGRect(x: 0.05, y: 0.30, width: 0.1, height: 0.02), confidence: 1),
            OCRFragment(text: "$18.00", box: CGRect(x: 0.75, y: 0.30, width: 0.2, height: 0.02), confidence: 1),
        ]
        let lines = ReadingOrder.lines(fragments)
        #expect(lines.contains("4111  1111  1111  1111"))
        #expect(lines.contains("Name on card  Alex Doe"))

        let reading = VisionScreenReader.reading(from: fragments)
        #expect(reading.redactedText == "Checkout\nCard number\n[CARD]\nName on card [NAME]\nTotal  $18.00")
        #expect(reading.redactions == ["card_number", "name"])
        #expect(reading.isCheckout)
        #expect(Redactor.longestDigitRun(in: reading.redactedText) < 12)
    }

    @Test func rowsAreJoinedLeftToRight() {
        let fragments = [
            OCRFragment(text: "$1,499.00", box: CGRect(x: 0.75, y: 0.50, width: 0.2, height: 0.02), confidence: 1),
            OCRFragment(text: "Place order", box: CGRect(x: 0.30, y: 0.60, width: 0.3, height: 0.02), confidence: 0.5),
            OCRFragment(text: "Total", box: CGRect(x: 0.05, y: 0.505, width: 0.1, height: 0.02), confidence: 1),
            OCRFragment(text: "Checkout", box: CGRect(x: 0.05, y: 0.10, width: 0.3, height: 0.03), confidence: 1),
        ]
        #expect(ReadingOrder.lines(fragments) == ["Checkout", "Total  $1,499.00", "Place order"])
        #expect(ReadingOrder.meanConfidence(fragments) == 0.875)
        #expect(ReadingOrder.meanConfidence([]) == 0)
    }
}

// Review round 2 privacy fixes (SPEC §10, §15.7 step 8): card-entry forms, addresses and names the first rules
// missed, card product names in a "Pay with" block, and the claim's typed description. Fake data only: Alex Doe,
// "Example"/"Sample" streets, the 98000 ZIP, (555) 010-0000, last 4 1234/4321/5678, and the 4111… test number built
// at runtime from 4-digit groups, so these suites store no run of 12+ digits.

/// A fake card number from its groups ("4111 1111 l111 1111" when OCR read a 1 as an l).
private func fakeCard(_ groups: [String] = ["4111", "1111", "1111", "1111"], separator: String = " ") -> String {
    groups.joined(separator: separator)
}

/// A full card number with no label next to it, as a filled form shows it (built at runtime, never a literal).
private let fakePAN = fakeCard(["4242", "4242", "4242", "4242"])

/// Card numbers with OCR look-alike letters for digits: (groups, separator).
private let lookalikeCardNumbers: [([String], String)] = [
    (["4111", "1111", "l111", "1111"], " "),
    (["4111", "1111", "1111", "111I"], " "),
    (["5105", "105|", "0510", "5100"], "  "),
    (["5555", "S555", "5555", "4444"], " "),
    (["4111", "1O11", "1111", "1111"], "-"),
    (["4111", "1111", "1111", "111o"], " "),
    (["5555", "5555", "B555", "4444"], " "),
    (["4111", "Z111", "1111", "1111"], " "),
    (["4111", "1111", "l1l1", "1111"], ""),
    // A whole group misread (review round 2): inside the number, at its end, at its start.
    (["4111", "1111", "llll", "1111"], " "),
    (["4111", "IIII", "1111", "1111"], "  "),
    (["4111", "1111", "1111", "llll"], " "),
    (["llll", "1111", "1111", "1111"], " "),
]

/// Card forms with the expiry and code side by side and no label of their own: (OCR rows, redacted rows, kinds).
private let unlabelledFieldCases: [(lines: [String], expected: [String], kinds: [String])] = [
    (["Card information", fakePAN, "12 / 28  123"], ["Card information", "[CARD]", "[CARD]  [CARD]"], ["card_number"]),
    (["Card number", fakePAN + "  12 / 28  123  98000"], ["Card number", "[CARD]  [CARD]  [CARD]  [ADDRESS]"], ["card_number", "address"]),
    (["Card details", fakePAN, "12/28  123"], ["Card details", "[CARD]", "[CARD]  [CARD]"], ["card_number"]),
    (["Card number", fakePAN, "12 / 28  123"], ["Card number", "[CARD]", "[CARD]  [CARD]"], ["card_number"]),
    (["Card number", fakePAN + "  12 / 28  123"], ["Card number", "[CARD]  [CARD]  [CARD]"], ["card_number"]),
    // No card-form label: the card number makes it a card form.
    (["Pay with card", fakePAN, "12 / 28  123", "Pay  $18.00"], ["Pay with card", "[CARD]", "[CARD]  [CARD]", "Pay  $18.00"], ["card_number"]),
    // No full number: an expiry and a code side by side make it one.
    (["Payment", "Visa ending 4242", "12 / 28  123"], ["Payment", "Visa ending [CARD]", "[CARD]  [CARD]"], ["card_number"]),
    (["Card information", "Visa ending 4242", "12 / 28  123"], ["Card information", "Visa ending [CARD]", "[CARD]  [CARD]"], ["card_number"]),
    // The code and the ZIP on a row of their own; a placeholder left next to a typed code.
    (["Card information", fakePAN, "12 / 28", "123  98000"], ["Card information", "[CARD]", "[CARD]", "[CARD]  [ADDRESS]"], ["card_number", "address"]),
    (["Card number", "MM / YY  123"], ["Card number", "MM / YY  [CARD]"], ["card_number"]),
    (["Card information", fakePAN, "12 / 28  123", "ZIP  98000-1234"], ["Card information", "[CARD]", "[CARD]  [CARD]", "ZIP  [ADDRESS]"], ["card_number", "address"]),
]

private let walletLast4 = Wallet.demo3Card.cards.compactMap(\.last4)
private let cardNames = CardCatalog.bundled().cards.flatMap { [$0.shortName, $0.displayName].compactMap { $0 } }

/// What leaves the phone for these OCR rows, in CheckFlow's order: Redactor, then PrivacyGuard.scrub.
private func sent(_ lines: [String], walletLast4: [String] = walletLast4) -> String {
    let redaction = Redactor.redact(lines: lines)
    let reading = ScreenReading(redactedText: redaction.text, redactions: redaction.kinds, ocrConfidence: 0.9, isCheckout: true)
    return PrivacyGuard.scrub(reading, walletLast4: walletLast4, cardNames: cardNames).text
}

private func jsonBody(_ text: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["ocrText": text])
}

// MARK: - ios-privacy-1: card-entry forms

struct CardFormRedactionTests {
    @Test func expiryAndCodeOnTheLabelRow() {
        let result = Redactor.redact(lines: ["Card number", fakeCard(), "Expiry  12/28", "CVV  123"])
        #expect(result.lines == ["Card number", "[CARD]", "Expiry [CARD]", "CVV [CARD]"])
        #expect(result.kinds == ["card_number"])
    }

    @Test(arguments: [
        ("Exp 12/28", "Exp [CARD]"),
        ("Exp. 12/2028", "Exp [CARD]"),
        ("Expiration date: 12/2028", "Expiration date [CARD]"),
        ("Expiry date  12 / 28", "Expiry date [CARD]"),
        ("Valid thru 01/29", "Valid thru [CARD]"),
        ("Expires 1/29", "Expires [CARD]"),
        ("MM/YY  12/28", "MM/YY [CARD]"),
        ("Security code: 1234", "Security code [CARD]"),
        ("CVC2 123", "CVC2 [CARD]"),
        ("CVV: 123", "CVV [CARD]"),
        ("Exp  12/28  CVV  123", "Exp [CARD]  CVV [CARD]"),
    ])
    func labelledFields(_ input: String, _ expected: String) {
        let result = Redactor.redact(input)
        #expect(result.text == expected)
        #expect(result.kinds == ["card_number"])
    }

    @Test func valuesOnTheRowsUnderTheirLabels() {
        let stacked = Redactor.redact(lines: ["Card number", fakeCard(), "Expiry", "12 / 28", "Security code", "123"])
        #expect(stacked.lines == ["Card number", "[CARD]", "Expiry", "[CARD]", "Security code", "[CARD]"])

        let columns = Redactor.redact(lines: ["Expiry  CVC", "12/28  123", "Total  $18.00"])
        #expect(columns.lines == ["Expiry  CVC", "[CARD]  [CARD]", "Total  $18.00"])
        #expect(columns.kinds == ["card_number"])
    }

    @Test func anyExpiryAndLoneCodeOnACardForm() {
        // Placeholders gone once typed: no label next to the values, but the screen is a card form.
        let result = Redactor.redact(lines: ["Checkout", "Card number", fakeCard(), "12/28", "123", "Total  $18.00", "Pay now"])
        #expect(result.lines == ["Checkout", "Card number", "[CARD]", "[CARD]", "[CARD]", "Total  $18.00", "Pay now"])
    }

    @Test func datesAndCountsOffACardFormStay() {
        let lines = ["Arrives 10/17", "Order date 10/15/2026", "Qty 2", "Express shipping", "Total  $18.00"]
        #expect(Redactor.redact(lines: lines).lines == lines)
        // A full date is never an expiry, even on a card form.
        #expect(Redactor.redact(lines: ["Card number", "Order date 10/15/2026"]).lines == ["Card number", "Order date 10/15/2026"])
    }

    /// OCR misreads in some fonts (Gill Sans read a 1 as "|"): O/o → 0, l/I/| → 1, S → 5, B → 8, Z → 2.
    @Test(arguments: lookalikeCardNumbers)
    func lookalikeLettersInACardNumber(_ groups: [String], _ separator: String) {
        let number = fakeCard(groups, separator: separator)
        for lines in [["Card number", number], ["Card number  " + number]] {
            let result = Redactor.redact(lines: lines)
            #expect(result.kinds == ["card_number"], "\(lines)")
            #expect(result.lines.last?.hasSuffix("[CARD]") == true, "\(result.lines)")
            for group in groups where group.allSatisfy(\.isNumber) {
                #expect(!result.text.contains(group), "\(group) survived in \(result.text)")
            }
        }
        // The backstop catches it without the Redactor too, unless the groups were run together.
        if !separator.isEmpty {
            let scrubbed = PrivacyGuard.scrub(ScreenReading(redactedText: "Card " + number, redactions: [], ocrConfidence: 0.9, isCheckout: true))
            #expect(scrubbed.text == "Card [CARD]", "\(number)")
        }
    }

    @Test func lookalikeNumberSplitOverRows() {
        let result = Redactor.redact(lines: ["Card number 4111 l111", "1111 1111", "Total  $18.00"])
        #expect(result.lines == ["Card number [CARD]", "[CARD]", "Total  $18.00"])
    }

    @Test(arguments: ["So 2024 SOLD 1999", "BOSS 1234 5678", "1OO% Cotton", "Size S  Qty 1", "Is it 10 or 12", "Total  $1,499.00"])
    func wordsNextToNumbersStay(_ line: String) {
        #expect(Redactor.redact(line).text == line)
        let scrubbed = PrivacyGuard.scrub(ScreenReading(redactedText: line, redactions: [], ocrConfidence: 0.9, isCheckout: true))
        #expect(scrubbed.text == line)
    }

    /// The finding's checkout, end to end: nothing of the card leaves, and the gate still sees the total.
    @Test func cardEntryCheckoutSendsNoCardData() throws {
        let lines = ["Checkout", "Card number", fakeCard(["5105", "105|", "0510", "5100"], separator: "  "), "Expiration date", "12/28",
                     "CVC", "123", "Total  $18.00", "Pay now"]
        let text = sent(lines)
        #expect(text == "Checkout\nCard number\n[CARD]\nExpiration date\n[CARD]\nCVC\n[CARD]\nTotal  $18.00\nPay now")
        for fragment in ["5105", "0510", "5100", "12/28", "\n123"] {
            #expect(!text.contains(fragment), "\(fragment) left the phone")
        }
        #expect(PrivacyGuard.isSendable(try jsonBody(text)))
        #expect(CheckoutGate.evaluate(text: text).passes)
    }

    // Review round 2: a filled form whose placeholders are gone shows the expiry and the code side by side with no
    // label of their own (Stripe's one "Card information" field, a one-row card element).

    @Test(arguments: unlabelledFieldCases)
    func unlabelledCodeNextToTheExpiry(_ testCase: (lines: [String], expected: [String], kinds: [String])) throws {
        let result = Redactor.redact(lines: testCase.lines)
        #expect(result.lines == testCase.expected)
        #expect(result.kinds == testCase.kinds)
        let text = sent(testCase.lines)
        for fragment in ["4242", "123", "28", "98000"] {
            #expect(!text.contains(fragment), "\(fragment) left the phone: \(text)")
        }
        #expect(PrivacyGuard.isSendable(try jsonBody(text)))
    }

    /// The reviewer's real Vision OCR of a filled Stripe-style form (accurate, en-US, language correction), as
    /// ReadingOrder joined it. Before the fix "[CARD] / 28  123" left the phone.
    @Test func filledCardInformationFieldSendsNoCardData() throws {
        let lines = ["Northbay Electronics", "Total due  $18.00", "Pay with card", "Card information", fakePAN, "12 / 28  123",
                     "Cardholder name", "Alex Doe", "Pay"]
        let text = sent(lines)
        #expect(text == "Northbay Electronics\nTotal due  $18.00\nPay with card\nCard information\n[CARD]\n[CARD]  [CARD]\n"
            + "Cardholder name\n[NAME]\nPay")
        #expect(PrivacyGuard.isSendable(try jsonBody(text)))
        #expect(CheckoutGate.evaluate(text: text).passes)
    }

    @Test func filledCardInformationFieldFromOCRFragments() {
        func fragment(_ text: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat = 0.12) -> OCRFragment {
            OCRFragment(text: text, box: CGRect(x: x, y: y, width: width, height: 0.025), confidence: 1)
        }
        let fragments = [
            fragment("Northbay Electronics", 0.05, 0.05, 0.4),
            fragment("Total due", 0.05, 0.10, 0.2), fragment("$18.00", 0.75, 0.10, 0.2),
            fragment("Card information", 0.05, 0.15, 0.35),
            fragment(fakePAN, 0.07, 0.20, 0.6),
            fragment("12 / 28", 0.07, 0.25, 0.15), fragment("123", 0.55, 0.25, 0.08),
            fragment("Cardholder name", 0.05, 0.30, 0.35),
            fragment("Alex Doe", 0.07, 0.35, 0.2),
        ]
        let reading = VisionScreenReader.reading(from: fragments)
        #expect(reading.redactedText == "Northbay Electronics\nTotal due  $18.00\nCard information\n[CARD]\n[CARD]  [CARD]\n"
            + "Cardholder name\n[NAME]")
        #expect(reading.redactions == ["card_number", "name"])
    }

    /// On a card form only card fields go: a phone, prices, a quantity, an ISO date, a full date and a time stay.
    @Test func otherNumbersOnACardFormStay() {
        let result = Redactor.redact(lines: ["Card number", fakePAN, "(555) 010-0000", "Total  $1,499.00", "1499.00", "Qty 2",
                                             "2026-10-17", "Order date 10/15/2026", "10:42"])
        #expect(result.lines == ["Card number", "[CARD]", "[PHONE]", "Total  $1,499.00", "1499.00", "Qty 2",
                                 "2026-10-17", "Order date 10/15/2026", "10:42"])
    }

    /// A word of look-alike letters next to a number that is not a card stays, also across rows.
    @Test func lookalikeWordsAcrossRowsStay() {
        let lines = ["So 2024 SOLD 1999", "BOSS 1234 5678", "Call 555 010 0000 IS"]
        #expect(Redactor.redact(lines: lines).lines == ["So 2024 SOLD 1999", "BOSS 1234 5678", "Call [PHONE] IS"])
    }

    /// Through ReadingOrder as the screen reader joins it: four number boxes, two label columns, two value columns.
    @Test func cardFormFromOCRFragments() {
        func fragment(_ text: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat = 0.12) -> OCRFragment {
            OCRFragment(text: text, box: CGRect(x: x, y: y, width: width, height: 0.025), confidence: 1)
        }
        let fragments = [
            fragment("Checkout", 0.05, 0.05, 0.3),
            fragment("Card number", 0.05, 0.10, 0.3),
            fragment("4111", 0.05, 0.15), fragment("1111", 0.28, 0.151), fragment("l111", 0.51, 0.149), fragment("1111", 0.75, 0.15),
            fragment("Expiration date", 0.05, 0.20, 0.35), fragment("Security code", 0.55, 0.20, 0.35),
            fragment("12/28", 0.05, 0.25), fragment("123", 0.55, 0.25),
            fragment("Total", 0.05, 0.30, 0.1), fragment("$18.00", 0.75, 0.30, 0.2),
        ]
        let reading = VisionScreenReader.reading(from: fragments)
        #expect(reading.redactedText == "Checkout\nCard number\n[CARD]\nExpiration date  Security code\n[CARD]  [CARD]\nTotal  $18.00")
        #expect(reading.redactions == ["card_number"])
        #expect(reading.isCheckout)
    }
}

// MARK: - ios-privacy-2: addresses and names

struct AddressRedactionTests {
    @Test(arguments: [
        "1 Example Loop", "45 Sample Trail", "2 Example Plaza", "221 Elm Row", "9 Old Mill Pike", "77 Sample Terrace",
        "12 Example Parkway", "3 Elm Circle", "5 Harbor Way", "8 Union Place", "4 Rose Court", "6 Maple Lane",
        "100 Coast Highway", "18 Market Square", "10 Example Yards", "12 Broadway", "221 Example", "1600 Sample",
    ])
    func streetsUnderShipTo(_ street: String) {
        let result = Redactor.redact(lines: ["Ship to", "Alex Doe", street, "Seattle, WA 98000", "Arrives Friday"])
        #expect(result.lines == ["Ship to", "[NAME]", "[ADDRESS]", "[ADDRESS]", "Arrives Friday"])
        #expect(result.kinds == ["address", "name"])
    }

    /// With a suffix, a street goes wherever it is on the screen, not only in a block.
    @Test(arguments: ["1 Example Loop", "45 Sample Trail", "2 Example Plaza", "9 Old Mill Pike", "Apt 4B", "Suite 200", "Unit 5",
                      "PO Box 123", "P.O. Box 77", "Seattle, WA, 98000-1234", "1 EXAMPLE LOOP, SEATTLE, WA, 98000-1234"])
    func addressLinesAnywhere(_ line: String) {
        let result = Redactor.redact(lines: ["Northbay Electronics", line])
        #expect(result.lines == ["Northbay Electronics", "[ADDRESS]"])
    }

    @Test(arguments: ["Unit price  $5.00", "Unit price", "2 x Ceramic Mug", "2 Way Radio  $40.00", "Free delivery in 2–4 days"])
    func shopTextIsNotAnAddress(_ line: String) {
        #expect(Redactor.redact(lines: ["Northbay Electronics", line]).lines == ["Northbay Electronics", line])
    }

    /// The block stays open over a line it leaves, so the street and city below it still go.
    @Test func addressBlockStaysOpenOverOtherLines() {
        let result = Redactor.redact(lines: ["Ship to", "Alex Doe", "Home", "221 Example", "Seattle, WA 98000", "United States", "Arrives Friday"])
        #expect(result.lines == ["Ship to", "[NAME]", "Home", "[ADDRESS]", "[ADDRESS]", "[ADDRESS]", "Arrives Friday"])
        // A blank row right after the header doesn't use up the name line; a section label still ends the block.
        let blank = Redactor.redact(lines: ["Ship to", "", "Alex Doe", "221 Example", "Contact", "221 Sample"])
        #expect(blank.lines == ["Ship to", "", "[NAME]", "[ADDRESS]", "Contact", "221 Sample"])
    }

    @Test func shopTextInsideAnAddressBlockStays() {
        let lines = ["Delivery", "Tomorrow", "8 AM - 12 PM", "3 business days", "2 Year Protection Plan", "Total  $18.00"]
        #expect(Redactor.redact(lines: lines).lines == lines)
    }

    @Test func headerWithTheNameOnItsRowStillTakesTheAddress() {
        #expect(Redactor.redact(lines: ["Ship to  Alex Doe", "2 Example Plaza", "Seattle, WA 98000"]).lines
            == ["Ship to [NAME]", "[ADDRESS]", "[ADDRESS]"])
        #expect(Redactor.redact(lines: ["Shipping  Alex Doe", "221 Example", "Seattle WA 98000", "United States"]).lines
            == ["Shipping [NAME]", "[ADDRESS]", "[ADDRESS]", "[ADDRESS]"])
        #expect(Redactor.redact(lines: ["Delivering to Alex Doe", "1 EXAMPLE LOOP, SEATTLE, WA, 98000-1234"]).lines
            == ["Delivering to [NAME]", "[ADDRESS]"])
        #expect(Redactor.redact(lines: ["Ship to", "Alex Doe", "c/o Jamie Doe", "1 Example Loop"]).lines
            == ["Ship to", "[NAME]", "[NAME]", "[ADDRESS]"])
    }

    @Test(arguments: [
        ("Pickup person  Alex Doe", "Pickup person [NAME]"),
        ("Picked up by: Alex Doe", "Picked up by [NAME]"),
        ("Order for Alex Doe", "Order for [NAME]"),
        ("Gift for Alex Doe", "Gift for [NAME]"),
        ("First name  Alex", "First name [NAME]"),
        ("Last name  Doe", "Last name [NAME]"),
        ("Recipient name  Alex Doe", "Recipient name [NAME]"),
        ("Attn: Alex Doe", "Attn [NAME]"),
        ("Buyer: Alex Doe", "Buyer [NAME]"),
    ])
    func nameLabels(_ input: String, _ expected: String) {
        let result = Redactor.redact(input)
        #expect(result.text == expected)
        #expect(result.kinds == ["name"])
    }

    @Test func nameOnTheRowUnderANameLabel() {
        #expect(Redactor.redact(lines: ["Pickup person", "Alex Doe"]).lines == ["Pickup person", "[NAME]"])
        #expect(Redactor.redact(lines: ["Order for", "Alex Doe", "Total  $18.00"]).lines == ["Order for", "[NAME]", "Total  $18.00"])
    }

    @Test(arguments: ["Order for pickup", "Gift for Mom", "Buyer protection", "Name brand headphones  $90.00"])
    func labelWordsInShopTextStay(_ line: String) {
        #expect(Redactor.redact(line).text == line)
    }

    @Test func nameAboveAnAddressWithARowBetween() {
        #expect(Redactor.redact(lines: ["Alex Doe", "", "1 Example Loop", "Seattle, WA 98000"]).lines == ["[NAME]", "", "[ADDRESS]", "[ADDRESS]"])
        #expect(Redactor.redact(lines: ["Alex Doe", "Home", "1 Example Loop"]).lines == ["[NAME]", "Home", "[ADDRESS]"])
        #expect(Redactor.redact(lines: ["Alex Doe", "1 Example Loop", "Seattle, WA 98000"]).lines == ["[NAME]", "[ADDRESS]", "[ADDRESS]"])
        // Store names stay: the backend matches merchants by name.
        #expect(Redactor.redact(lines: ["Best Buy", "Pickup", "123 Example St"]).lines == ["Best Buy", "Pickup", "[ADDRESS]"])
    }

    @Test func nameAboveAnEmailOrPhone() {
        #expect(Redactor.redact(lines: ["Alex Doe", "alex@example.com"]).lines == ["[NAME]", "[EMAIL]"])
        #expect(Redactor.redact(lines: ["Alex Doe", "(555) 010-0000"]).lines == ["[NAME]", "[PHONE]"])
        #expect(Redactor.redact(lines: ["Northbay Electronics", "(555) 010-0000"]).lines == ["Northbay Electronics", "[PHONE]"])
    }
}

// MARK: - ios-privacy-3: card product names in a payment block

struct PaymentBlockRedactionTests {
    @Test(arguments: [
        "Chase Freedom Unlimited", "Wells Fargo Active Cash", "Active Cash", "Freedom Unlimited", "Chase Freedom Rise",
        "Apple Card", "Discover it", "Discover it Student Cash Back", "Capital One Venture",
    ])
    func productNameStaysAndTheLast4Goes(_ product: String) {
        for header in ["Pay with", "Payment", "Payment method"] {
            // An empty wallet, so the Redactor alone has to take the last 4.
            let text = sent([header, product, "1234", "Total  $18.00"], walletLast4: [])
            #expect(text == "\(header)\n\(product)\n[CARD]\nTotal  $18.00")
        }
        #expect(sent(["Pay with  " + product]) == "Pay with  " + product)
        #expect(Redactor.looksLikeCardProduct(product))
        #expect(!Redactor.looksLikePersonName(product))
    }

    @Test func holderNameStillGoes() {
        let result = Redactor.redact(lines: ["Pay with", "Chase Freedom Unlimited", "Alex Doe", "••1234"])
        #expect(result.lines == ["Pay with", "Chase Freedom Unlimited", "[NAME]", "[CARD]"])
        // One issuer word is not a product: "Chase Doe" is a person.
        #expect(Redactor.redact(lines: ["Pay with", "Chase Doe", "Visa ••1234"]).lines == ["Pay with", "[NAME]", "Visa [CARD]"])
        #expect(!Redactor.looksLikeCardProduct("Alex Doe"))
        #expect(!Redactor.looksLikeCardProduct("Chase Doe"))
    }

    @Test func last4UnderACardNameWithoutAHeader() {
        #expect(sent(["Chase Freedom Unlimited", "1234"], walletLast4: []) == "Chase Freedom Unlimited\n[CARD]")
        #expect(sent(["Apple Card", "(5678)"], walletLast4: []) == "Apple Card\n([CARD])")
    }

    @Test(arguments: ["#### 4321", "---- 4321", "°°°° 5678", "oooo 5678", "–– 1234"])
    func misreadMasks(_ line: String) {
        #expect(Redactor.redact(line).text == "[CARD]")
        #expect(Redactor.redact(lines: ["Payment method", line]).lines == ["Payment method", "[CARD]"])
        let scrubbed = PrivacyGuard.scrub(ScreenReading(redactedText: line, redactions: [], ocrConfidence: 0.9, isCheckout: true))
        #expect(scrubbed.text == "[CARD]")
    }
}

// MARK: - ios-privacy-7: the claim's typed description

struct FreeTextRedactionTests {
    @Test(arguments: [
        ("Stolen at 1 Example Loop, my Freedom ending 1234, call 555-010-0000", "Stolen at [ADDRESS], my Freedom ending [CARD], call [PHONE]"),
        ("Taken from my car at 45 Sample Trail, Seattle, WA 98000", "Taken from my car at [ADDRESS], [ADDRESS]"),
        ("Email me at alex@example.com", "Email me at [EMAIL]"),
        ("My card exp 12/28 cvv 123 was in the bag", "My card exp [CARD] cvv [CARD] was in the bag"),
    ])
    func personalPartsGoAndTheStoryStays(_ input: String, _ expected: String) {
        #expect(Redactor.redactFreeText(input).text == expected)
    }

    @Test func typedCardNumberWithALookalike() {
        let typed = "Card " + fakeCard(["4111", "1111", "l111", "1111"]) + " was charged"
        #expect(Redactor.redactFreeText(typed).text == "Card [CARD] was charged")
    }

    /// The §5.5 demo strings and ordinary sentences come through word for word.
    @Test(arguments: [
        "Lines across the screen. Never dropped.", "Stolen from my bag", "Cracked it when I dropped it", "It stopped turning on",
        "Dropped it 2 days ago on the way home", "Fell 4 feet onto the court", "Left it on the train at 5 PM",
    ])
    func storiesStay(_ text: String) {
        let result = Redactor.redactFreeText(text)
        #expect(result.text == text)
        #expect(result.kinds.isEmpty)
    }
}

/// The claim's description is redacted before every `POST /v1/coverage` (SPEC §10).
@MainActor
struct ClaimDescriptionPrivacyTests {
    private func purchase(status: Purchase.Status) throws -> PurchaseSnapshot {
        let draft = try #require(try Fixtures.recordExample().parsedResponse.purchaseDraft)
        return PurchaseSnapshot(
            id: "p_privacy", checkId: "5f0c0000-aaaa-4bbb-8ccc-ddddeeeeffff", status: status,
            merchant: try #require(draft.merchant), item: try #require(draft.item), category: draft.category ?? "general",
            condition: draft.condition?.rawValue ?? "unknown", priceUsd: try #require(draft.priceUsd),
            purchaseDate: try #require(draft.purchaseDate), cardId: try #require(draft.cardId), coverage: draft.coverage ?? []
        )
    }

    private func incidentDescription(_ body: Data) throws -> String? {
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        return (object["incident"] as? [String: Any])?["description"] as? String
    }

    private static let typed = "Stolen at 1 Example Loop, my Freedom ending 1234, call 555-010-0000 or alex@example.com"
    private static let redacted = "Stolen at [ADDRESS], my Freedom ending [CARD], call [PHONE] or [EMAIL]"

    @Test func classificationSendsTheRedactedDescription() async throws {
        let reply = Data(#"{"incident":{"cause":"theft","causeSource":"llm"}}"#.utf8)
        let env = TestEnvironment(reading: .laptopCheckout, route: .init(behavior: .respond(status: 200, body: reply)))
        let model = ClaimModel(purchase: try purchase(status: .planned), deps: env.deps, wallet: .demo3Card)
        model.description = Self.typed
        await model.classify(model.trimmedDescription)

        let body = try #require(env.requests.first)
        #expect(try incidentDescription(body) == Self.redacted)
        let text = String(decoding: body, as: UTF8.self)
        for personal in ["1234", "555", "010-0000", "Example Loop", "alex"] {
            #expect(!text.contains(personal), "\(personal) was sent")
        }
        // The text is still the user's, so the chip the server picked applies.
        #expect(model.cause == .theft)
    }

    @Test func verdictSendsTheRedactedDescription() async throws {
        let html = "<!doctype html><title>Verdict</title>"
        let env = TestEnvironment(reading: .laptopCheckout, route: .init(behavior: .respond(status: 200, body: Data(html.utf8))))
        let purchases = PurchasesModel(deps: env.deps)
        let model = ClaimModel(purchase: try purchase(status: .confirmed), deps: env.deps, wallet: .demo3Card)
        model.warranty = .oneYear
        model.description = "Bought on Freedom 1234, then taken from 45 Sample Trail"
        model.pick(.theft)

        // "Freedom 1234" has no card word: PrivacyGuard.scrub takes it with the catalog's card names.
        let expected = "Bought on Freedom [CARD], then taken from [ADDRESS]"
        #expect(model.verdictRequest().incident.description == expected)
        let request = try #require(await model.prepareVerdict(purchases))
        #expect(request.incident.description == expected)

        let verdict = VerdictModel(request: request, api: env.deps.coverage)
        await verdict.load()
        let body = try #require(env.requests.first)
        #expect(try incidentDescription(body) == expected)
        #expect(!String(decoding: body, as: UTF8.self).contains("1234"))
    }

    @Test func plainDescriptionsAreSentAsTyped() throws {
        let env = TestEnvironment(reading: .laptopCheckout)
        let model = ClaimModel(purchase: try purchase(status: .confirmed), deps: env.deps, wallet: .demo3Card)
        model.description = "Lines across the screen. Never dropped."
        #expect(model.verdictRequest().incident.description == "Lines across the screen. Never dropped.")
        #expect(model.sendableDescription("Cracked it when I dropped it") == "Cracked it when I dropped it")
    }
}
