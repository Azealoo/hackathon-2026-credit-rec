import Foundation

/// The words the Purchases screens show for one purchase, built from the purchase, the wallet and cards.json.
enum PurchaseText {
    /// SPEC §15.7 step 12a, word for word:
    /// "Aero 14 · Freedom ••1234 · Planned · theft & damage up to $500 to Feb 14, 2027 · warranty year to Oct 17, 2028".
    /// Parts without data are left out: no stored last 4 drops "••1234" (as §6.3 does), no cap drops "up to $500",
    /// and a purchase with no coverage entry of a kind drops that part. Cover whose last day is before `today`
    /// (`Day.today`) reads "theft & damage ended Feb 14, 2027".
    static func line(_ purchase: PurchaseSnapshot, wallet: Wallet, catalog: CardCatalog, today: String) -> String {
        var parts = [purchase.shortItemName, card(purchase.cardId, wallet: wallet, catalog: catalog), status(purchase.status)]
        if let theft = purchase.coverage.first(where: { $0.type == .purchaseProtection }), let until = Day.medium(theft.until) {
            if hasEnded(theft.until, today: today) {
                parts.append("theft & damage ended \(until)")
            } else {
                let cap = theft.limitUsd.map { " up to " + Money.whole($0) } ?? ""
                parts.append("theft & damage\(cap) to \(until)")
            }
        }
        if let warranty = purchase.coverage.first(where: { $0.type == .extendedWarranty }), let until = Day.medium(warranty.until) {
            parts.append(hasEnded(warranty.until, today: today) ? "warranty year ended \(until)" : "warranty year to \(until)")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Whether cover through `until` (its last day) has ended by `today`; both yyyy-MM-dd, which compare as dates.
    static func hasEnded(_ until: String, today: String) -> Bool {
        PaywiseSettings.isDay(until) && PaywiseSettings.isDay(today) && until < today
    }

    /// "Freedom ••1234", or "Freedom" with no stored last 4.
    static func card(_ cardId: String, wallet: Wallet, catalog: CardCatalog) -> String {
        let name = catalog.shortName(cardId) ?? cardId
        return wallet.last4(for: cardId).map { "\(name) ••\($0)" } ?? name
    }

    static func status(_ status: Purchase.Status) -> String {
        switch status {
        case .planned: "Planned"
        case .confirmed: "Confirmed"
        }
    }

    /// One coverage line on the detail screen. Ended cover is drawn greyed with a non-check icon.
    struct CoverageLine: Equatable, Hashable {
        var text: String
        var ended: Bool
    }

    /// The detail screen's coverage lines, in the Saved snippet's words (§6.3 *Saved*), each compared with `today`
    /// (`Day.today`): at §12.1's "14 months later", theft & damage reads "ended Feb 14, 2027", not live cover.
    static func coverageLines(_ purchase: PurchaseSnapshot, today: String) -> [CoverageLine] {
        var lines: [CoverageLine] = []
        if let theft = purchase.coverage.first(where: { $0.type == .purchaseProtection }), let until = Day.medium(theft.until) {
            let ended = hasEnded(theft.until, today: today)
            let cap = theft.limitUsd.map { " up to " + Money.whole($0) } ?? ""
            lines.append(.init(text: ended ? "Theft & damage cover ended \(until)" : "Theft & damage cover\(cap) to \(until)", ended: ended))
        }
        if let warranty = purchase.coverage.first(where: { $0.type == .extendedWarranty }), let until = Day.medium(warranty.until) {
            let ended = hasEnded(warranty.until, today: today)
            lines.append(.init(text: ended ? "Extra warranty year ended \(until)*" : "Extra warranty year to \(until)*", ended: ended))
        }
        return lines
    }

    /// The footnote under an extended-warranty line ("*If the maker's warranty is 1 year.").
    static func warrantyFootnote(_ purchase: PurchaseSnapshot) -> String? {
        guard let warranty = purchase.coverage.first(where: { $0.type == .extendedWarranty }) else { return nil }
        let months = warranty.assumesManufacturerWarrantyMonths ?? 12
        return "*If the maker's warranty is \(duration(months: months))."
    }

    /// "$1,499.00": the price with cents, as a receipt shows it.
    static func price(_ usd: Double) -> String {
        usd.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")).precision(.fractionLength(2)))
    }

    static func duration(months: Int) -> String {
        if months % 12 == 0 {
            let years = months / 12
            return years == 1 ? "1 year" : "\(years) years"
        }
        return months == 1 ? "1 month" : "\(months) months"
    }

    /// An SF Symbol for the purchase row's icon tile, by cards.json item category.
    static func symbol(category: String) -> String {
        switch category {
        case "computers": "laptopcomputer"
        case "phones": "iphone"
        case "audio": "headphones"
        case "cameras": "camera"
        case "electronics": "tv"
        case "appliances": "washer"
        case "tools": "hammer"
        case "bikes": "bicycle"
        case "instruments": "guitars"
        case "apparel": "tshirt"
        case "home": "cup.and.saucer"
        default: "bag"
        }
    }
}
