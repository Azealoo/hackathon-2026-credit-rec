import Foundation

/// The VoiceOver label for a result (SPEC §6.4): "Use Freedom, card ending 1 2 3 4. Adds a warranty year and up to
/// 500 dollars of theft cover. 7 dollars 49 less cash back than Active Cash."
enum SpokenCopy {
    static func label(_ copy: CheckRecord.FilledCopy) -> String {
        label(lines: [copy.line1, copy.line2, copy.line3])
    }

    /// The same for any lines, e.g. a Live Activity's lines 1–3.
    static func label(lines: [String?]) -> String {
        lines
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .map { sentence(spoken($0)) }
            .joined(separator: " ")
    }

    static func spoken(_ text: String) -> String {
        var result = text
        result = result.replacing(#/ ?••(\d)(\d)(\d)(\d)/#) { ", card ending \($0.1) \($0.2) \($0.3) \($0.4)" }
        result = result.replacing(#/\+ \$([0-9][0-9,]*(?:\.[0-9]{2})?) theft cover/#) {
            "and up to \(dollars(String($0.1))) of theft cover"
        }
        result = result.replacingOccurrences(of: " + ", with: " and ")
        result = result.replacing(#/\$([0-9][0-9,]*(?:\.[0-9]{2})?)/#) { dollars(String($0.1)) }
        if result.hasPrefix("✓ ") { result.removeFirst(2) }
        result = result.replacingOccurrences(of: " · ", with: ". ")
        return result
    }

    /// "7.49" → "7 dollars 49"; "500" → "500 dollars".
    private static func dollars(_ amount: String) -> String {
        let parts = amount.split(separator: ".")
        let whole = parts[0].replacingOccurrences(of: ",", with: "")
        let unit = whole == "1" ? "dollar" : "dollars"
        if parts.count > 1, parts[1] != "00" {
            return "\(whole) \(unit) \(parts[1])"
        }
        return "\(whole) \(unit)"
    }

    private static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return trimmed }
        return ".!?".contains(last) ? trimmed : trimmed + "."
    }
}
