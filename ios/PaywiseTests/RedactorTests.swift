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
        "4111111111111111",         // Luhn-valid, plain
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
        #expect(Redactor.isLuhnValid("378282246310005"))
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
