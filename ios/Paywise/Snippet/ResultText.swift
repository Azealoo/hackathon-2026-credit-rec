import Foundation

/// Text for the snippet views that isn't backend copy: the button title and the *Saved* lines (SPEC §6.3).
enum ResultText {
    /// "Paying with Freedom", from `shortName` in cards.json, else the backend's `copy.primaryButton`. Nil when
    /// neither names a card: the button is then left out rather than given words §6.3 doesn't have.
    static func primaryButtonTitle(decision: CheckResponse.Decision?, catalog: CardCatalog) -> String? {
        if let name = catalog.shortName(decision?.recommendedCardId) { return "Paying with \(name)" }
        if let title = decision?.copy?.primaryButton, !title.isEmpty { return title }
        return nil
    }

    struct Saved: Equatable {
        var line1: String
        var line2: String?
        var line3: String?
        var footnote: String
    }

    /// §6.3 *Saved*: "✓ Saved: Aero 14 · $1,499" / "Theft & damage cover up to $500 to Feb 14, 2027" /
    /// "Extra warranty year to Oct 17, 2028*" / "*If the maker's warranty is 1 year. Planned: confirm after you pay."
    static func saved(_ draft: CheckResponse.PurchaseDraft?) -> Saved {
        // A missing item name is dropped, as §6.3 drops "••{…}" with no stored last 4: "✓ Saved · $1,499".
        let name = draft?.item.map(ItemName.short).flatMap { $0.isEmpty ? nil : ": " + $0 } ?? ""
        let price = draft?.priceUsd.map { " · " + Money.whole($0) } ?? ""
        let coverage = draft?.coverage ?? []

        let theft = coverage.first { $0.type == .purchaseProtection }.map { entry in
            let cap = entry.limitUsd.map { " up to " + Money.whole($0) } ?? ""
            return "Theft & damage cover\(cap)" + dateSuffix(entry.until)
        }
        let warranty = coverage.first { $0.type == .extendedWarranty }
        let warrantyLine = warranty.map { "Extra warranty year" + dateSuffix($0.until) + "*" }

        var footnote = "Planned: confirm after you pay."
        if let warranty {
            let months = warranty.assumesManufacturerWarrantyMonths ?? 12
            footnote = "*If the maker's warranty is \(duration(months: months)). " + footnote
        }
        return Saved(line1: "✓ Saved\(name)\(price)", line2: theft, line3: warrantyLine, footnote: footnote)
    }

    private static func dateSuffix(_ isoDate: String) -> String {
        shortDate(isoDate).map { " to " + $0 } ?? ""
    }

    /// "2027-02-14" → "Feb 14, 2027".
    static func shortDate(_ isoDate: String) -> String? {
        let parts = isoDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]) else { return nil }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(months[parts[1] - 1]) \(parts[2]), \(parts[0])"
    }

    private static func duration(months: Int) -> String {
        if months % 12 == 0 {
            let years = months / 12
            return years == 1 ? "1 year" : "\(years) years"
        }
        return months == 1 ? "1 month" : "\(months) months"
    }
}
