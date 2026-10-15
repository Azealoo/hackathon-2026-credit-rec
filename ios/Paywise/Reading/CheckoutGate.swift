import Foundation

/// The on-device checkout test (SPEC §10 "Accidental presses", §15.7 step 8). It only decides whether the redacted
/// text is uploaded at all: a screen passes when it shows a money total ("Total  $1,499.00") and a checkout word
/// ("Place order", "Pay with", "Checkout", …). Order confirmations pass on purpose ("Order placed", "Thank you",
/// "Order #"), so the backend can answer *Already paid?* (§6.3); a social feed or any screen without a total fails,
/// and then nothing leaves the phone.
enum CheckoutGate {
    struct Verdict: Sendable, Equatable {
        /// The total as printed, e.g. "$1,499.00", or nil if no total line with a dollar amount was found.
        var total: String?
        /// The first checkout word found, lowercased, e.g. "place order".
        var keyword: String?
        var passes: Bool { total != nil && keyword != nil }
    }

    /// Words that put a screen in the checkout flow (including just after paying). Matched case-insensitively.
    static let keywords = [
        "place order", "place your order", "pay with", "pay now", "checkout", "check out", "complete purchase",
        "complete order", "confirm and pay", "submit order", "buy now", "payment method", "review order",
        "continue to payment", "paid with", "order placed", "order confirmed", "thank you", "order #", "order number",
    ]

    static func evaluate(text: String) -> Verdict {
        evaluate(lines: text.components(separatedBy: "\n"))
    }

    static func evaluate(lines: [String]) -> Verdict {
        Verdict(total: total(in: lines), keyword: keyword(in: lines))
    }

    /// The amount on the first total line ("Total", "Order total", "Grand total", "Amount due", …), taken from the same
    /// line or, when OCR split the row, from the next line if that line is just an amount. "Subtotal" does not count.
    static func total(in lines: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            guard let label = totalLabel.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let labelEnd = Range(label.range, in: line)?.upperBound else { continue }
            let rest = String(line[labelEnd...])
            if let amount = firstAmount(in: rest) {
                return amount
            }
            if index + 1 < lines.count {
                let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
                if let amount = firstAmount(in: next), amount.count >= next.count - 1 {
                    return amount
                }
            }
        }
        return nil
    }

    static func keyword(in lines: [String]) -> String? {
        let text = lines.joined(separator: "\n").lowercased()
        return keywords.first { text.contains($0) }
    }

    /// "$1,499.00", "$ 18.00", "$249", "$1499.00".
    static func firstAmount(in text: String) -> String? {
        guard let match = amount.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range]).replacingOccurrences(of: " ", with: "")
    }

    private static let totalLabel = try! NSRegularExpression(
        pattern: #"(?i)(?<![a-z])(order total|grand total|estimated total|total due|amount due|you pay|total)(?![a-z])"#)
    private static let amount = try! NSRegularExpression(
        pattern: #"\$ ?(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]{2})?(?![0-9])"#)
}
