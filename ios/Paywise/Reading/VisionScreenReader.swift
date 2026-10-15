import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Reads a screenshot on the device (SPEC §9.1 intent step 3, §15.7 step 8): crop the status-bar strip, run Vision
/// text recognition (accurate, en-US), put the lines in reading order, run the checkout gate and redact.
/// The screenshot itself never leaves this function; only the redacted text does.
struct VisionScreenReader: ScreenReader {
    enum ReadError: Error, Equatable {
        /// The data is not an image, or the image is no taller than the top strip.
        case unreadableImage
    }

    func read(_ imageData: Data) async throws -> ScreenReading {
        let fragments = try await recognize(imageData)
        return Self.reading(from: fragments)
    }

    /// OCR only: the cropped screenshot's text fragments, unredacted. Stays on the device.
    func recognize(_ imageData: Data) async throws -> [OCRFragment] {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let cropped = TopStripCrop.crop(image) else {
            throw ReadError.unreadableImage
        }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
        request.automaticallyDetectsLanguage = false
        request.usesLanguageCorrection = true

        let observations = try await request.perform(on: cropped)
        return observations.compactMap { observation in
            guard let best = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            // Vision's normalised space has its origin at the bottom-left; flip to top-left for reading order.
            let topLeftBox = CGRect(x: box.origin.x, y: 1 - box.origin.y - box.height, width: box.width, height: box.height)
            return OCRFragment(text: best.string, box: topLeftBox, confidence: Double(best.confidence))
        }
    }

    /// Gate + redaction over OCR fragments. Pure, so tests can feed it fragments without an image.
    static func reading(from fragments: [OCRFragment]) -> ScreenReading {
        let lines = ReadingOrder.lines(fragments)
        let verdict = CheckoutGate.evaluate(lines: lines)
        let redaction = Redactor.redact(lines: lines)
        return ScreenReading(
            redactedText: redaction.text,
            redactions: redaction.kinds,
            ocrConfidence: ReadingOrder.meanConfidence(fragments),
            isCheckout: verdict.passes
        )
    }
}
