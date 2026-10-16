import Foundation

/// Returns a given `ScreenReading` for any image. Used by tests and previews.
struct FixtureScreenReader: ScreenReader {
    var reading: ScreenReading

    func read(_ imageData: Data) async throws -> ScreenReading {
        reading
    }
}

extension ScreenReading {
    /// The demo laptop checkout as on-device reading would produce it (SPEC §15.5 request example; fake data).
    static let laptopCheckout = ScreenReading(
        redactedText: """
        Northbay Electronics
        Checkout
        Aero 14 Laptop, 14-inch (New)  $1,499.00
        Total  $1,499.00
        Pay with Mastercard [CARD]
        Change
        Ship to [ADDRESS]
        Place order
        """,
        redactions: ["card_number", "address", "email", "phone"],
        ocrConfidence: 0.93,
        isCheckout: true
    )

    /// A screen with no checkout total: the on-device gate fails and nothing is sent.
    static let notCheckout = ScreenReading(
        redactedText: "Feed\nJordan Sample\nMade it to the top of the ridge before sunrise.",
        redactions: [],
        ocrConfidence: 0.95,
        isCheckout: false
    )
}

/// Production placeholder until on-device reading (`VisionScreenReader`, SPEC §15.7 step 8) is plugged in.
struct UnavailableScreenReader: ScreenReader {
    struct NotAvailable: Error, CustomStringConvertible {
        var description: String { "On-device screen reading is not available in this build yet." }
    }

    func read(_ imageData: Data) async throws -> ScreenReading {
        throw NotAvailable()
    }
}
