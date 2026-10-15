import Foundation

/// Bundled `/v1/check` responses for the demo fixtures (SPEC §15.7 step 10), used only when the request fails or times
/// out and the "replayEnabled" setting is on. Key: the merchant found in the OCR text + the "Total" line in cents →
/// `replay/<merchantId>_<totalCents>.json` (the `fixtures/replay` folder reference). Always labelled "replayed".
struct ReplayStore: Sendable {
    struct Key: Equatable, Sendable {
        var merchantId: String
        var totalCents: Int

        var fileName: String { "\(merchantId)_\(totalCents)" }
    }

    var bundle: Bundle = .main
    var subdirectory = "replay"

    static func key(for ocrText: String, catalog: CardCatalog) -> Key? {
        guard let merchantId = catalog.merchantId(in: ocrText),
              let cents = totalCents(in: ocrText)
        else { return nil }
        return Key(merchantId: merchantId, totalCents: cents)
    }

    func response(for key: Key) -> Data? {
        guard let url = bundle.url(forResource: key.fileName, withExtension: "json", subdirectory: subdirectory)
        else { return nil }
        return try? Data(contentsOf: url)
    }

    /// The amount on the last line that starts with "Total" (or "Order total"); not "Subtotal". If the amount is on
    /// the next line (OCR split it), that one is used.
    static func totalCents(in text: String) -> Int? {
        let lines = text.components(separatedBy: .newlines)
        var found: Int?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.range(of: #"^(order\s+)?total\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            else { continue }
            if let cents = moneyCents(in: trimmed) {
                found = cents
            } else if index + 1 < lines.count, let cents = moneyCents(in: lines[index + 1]) {
                found = cents
            }
        }
        return found
    }

    /// "$1,499.00" → 149900; "$18" → 1800.
    static func moneyCents(in text: String) -> Int? {
        guard let range = text.range(of: #"\$\s?[0-9][0-9,]*(\.[0-9]{2})?"#, options: .regularExpression) else {
            return nil
        }
        let digits = text[range].filter { $0.isNumber || $0 == "." }
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        guard let dollars = Int(parts[0]) else { return nil }
        let cents = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return dollars * 100 + cents
    }
}
