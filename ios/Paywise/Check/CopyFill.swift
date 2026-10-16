import Foundation

/// Fills the backend's §6.3 copy on the phone (SPEC §6.3, §15.7 step 10): `{last4:<cardId>}` from the wallet
/// (with no stored last 4 the " ••{…}" token is dropped) and `{ppCap}` from the response's verified limit
/// (if it isn't verified, "+ {ppCap} theft cover" reads "+ theft cover").
enum CopyFill {
    static func fill(_ copy: CheckResponse.Copy?, wallet: Wallet, ppCap: Double?) -> CheckRecord.FilledCopy {
        CheckRecord.FilledCopy(
            line1: copy?.line1.map { fill($0, wallet: wallet, ppCap: ppCap) } ?? "",
            line2: copy?.line2.map { fill($0, wallet: wallet, ppCap: ppCap) },
            line3: copy?.line3.map { fill($0, wallet: wallet, ppCap: ppCap) },
            instruction: copy?.instruction.map { fill($0, wallet: wallet, ppCap: ppCap) }
        )
    }

    static func fill(_ text: String, wallet: Wallet, ppCap: Double?) -> String {
        var result = fillLast4(text, wallet: wallet)
        if let ppCap {
            result = result.replacingOccurrences(of: "{ppCap}", with: Money.whole(ppCap))
        } else {
            result = result.replacingOccurrences(of: "{ppCap} ", with: "")
                .replacingOccurrences(of: " {ppCap}", with: "")
                .replacingOccurrences(of: "{ppCap}", with: "")
        }
        return result
    }

    private static let last4Token = try! NSRegularExpression(pattern: #"( ?)(••)?\{last4:([a-z0-9-]+)\}"#)

    private static func fillLast4(_ text: String, wallet: Wallet) -> String {
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in last4Token.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let space = ns.substring(with: match.range(at: 1))
            let bullets = match.range(at: 2).location == NSNotFound ? "" : "••"
            let cardId = ns.substring(with: match.range(at: 3))
            if let last4 = wallet.last4(for: cardId) {
                result += space + bullets + last4
            }
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    /// `{ppCap}`: the verified purchase-protection limit in the response, else the catalog's verified limit for the
    /// recommended card (a Keep-protected result gains nothing, so the response may carry none).
    static func ppCap(decision: CheckResponse.Decision?, catalog: CardCatalog) -> Double? {
        if let gained = decision?.protectionsGained?.first(where: { $0.type == .purchaseProtection }) {
            guard gained.verification == .verified else { return nil }
            if let amount = gained.limit?.amountUsd { return amount }
        }
        return catalog.verifiedPurchaseProtectionCap(cardId: decision?.recommendedCardId)
    }
}

enum Money {
    /// "$500", "$1,499", "$7.49": cents only when there are any.
    static func whole(_ usd: Double) -> String {
        let cents = (usd * 100).rounded()
        let isWhole = cents.truncatingRemainder(dividingBy: 100) == 0
        return usd.formatted(
            .currency(code: "USD").locale(Locale(identifier: "en_US")).precision(.fractionLength(isWhole ? 0 : 2))
        )
    }
}
