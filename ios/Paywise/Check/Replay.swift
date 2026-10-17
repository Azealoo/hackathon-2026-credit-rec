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

    /// A bundled response fitted to the request it answers. nil when it recommends a card the wallet doesn't hold: a
    /// replay never names a card the user lacks. Otherwise its purchase draft moves to `clientDate`, the purchase date
    /// and each coverage end by the same number of days (an end can land a day off across a Feb 29), so an offline
    /// replay on judging day saves the purchase dated that day, not the fixture's Oct 17. Same day: `data` unchanged.
    static func fitted(_ data: Data, clientDate: String, walletCardIds: Set<String>) -> Data? {
        guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let cardId = (object["decision"] as? [String: Any])?["recommendedCardId"] as? String,
           !walletCardIds.contains(cardId) {
            return nil
        }
        guard var draft = object["purchaseDraft"] as? [String: Any],
              let bought = draft["purchaseDate"] as? String,
              let shift = days(from: bought, to: clientDate), shift != 0
        else { return data }
        draft["purchaseDate"] = clientDate
        if let coverage = draft["coverage"] as? [[String: Any]] {
            draft["coverage"] = coverage.map { entry in
                var entry = entry
                if let until = entry["until"] as? String, let moved = day(until, plus: shift) { entry["until"] = moved }
                return entry
            }
        }
        object["purchaseDraft"] = draft
        return try? JSONSerialization.data(withJSONObject: object)
    }

    private static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private static func days(from start: String, to end: String) -> Int? {
        guard let start = Day.date(start, timeZone: .gmt), let end = Day.date(end, timeZone: .gmt) else { return nil }
        return gregorian.dateComponents([.day], from: start, to: end).day
    }

    private static func day(_ day: String, plus days: Int) -> String? {
        guard let date = Day.date(day, timeZone: .gmt), let moved = gregorian.date(byAdding: .day, value: days, to: date)
        else { return nil }
        return Day.string(moved, timeZone: .gmt)
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

    /// "$1,499.00" → 149900; "$18" → 1800. nil when the amount doesn't fit in an Int of cents (OCR text is untrusted:
    /// "$100,000,000,000,000,000.00" must not trap).
    static func moneyCents(in text: String) -> Int? {
        guard let range = text.range(of: #"\$\s?[0-9][0-9,]*(\.[0-9]{2})?"#, options: .regularExpression) else {
            return nil
        }
        let digits = text[range].filter { $0.isNumber || $0 == "." }
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        guard let dollars = Int(parts[0]) else { return nil }
        let cents = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let (dollarCents, overflowed) = dollars.multipliedReportingOverflow(by: 100)
        let (total, overflowedAdding) = dollarCents.addingReportingOverflow(cents)
        return overflowed || overflowedAdding ? nil : total
    }
}
