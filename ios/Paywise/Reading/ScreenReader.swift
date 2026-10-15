import Foundation

/// What on-device reading produced from one screenshot: redacted text only (SPEC §10).
struct ScreenReading: Sendable, Equatable {
    /// Redacted OCR text, top status strip already cropped. This is the only screen text that may leave the phone.
    var redactedText: String
    /// Which redaction kinds fired: "card_number", "address", "email", "phone", "name".
    var redactions: [String]
    /// Mean OCR confidence, 0...1.
    var ocrConfidence: Double
    /// On-device checkout gate: a money total plus a checkout keyword were found.
    var isCheckout: Bool
}

protocol ScreenReader: Sendable {
    func read(_ imageData: Data) async throws -> ScreenReading
}
