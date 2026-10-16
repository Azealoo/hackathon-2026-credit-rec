import Foundation
import SwiftData

/// A saved purchase (SPEC §15.5, `contracts/purchase.schema.json`), in SwiftData in the App Group container.
/// It leaves the phone only as part of a coverage check the user runs.
@Model
final class Purchase {
    enum Status: String, Codable, Sendable {
        case planned, confirmed
    }

    /// "p_<uuid>"
    @Attribute(.unique) var id: String
    /// nil when the purchase wasn't saved from a check.
    var checkId: String?
    var statusRaw: String
    var merchant: String
    var item: String
    var category: String
    var condition: String
    var priceUsd: Double
    /// yyyy-MM-dd
    var purchaseDate: String
    var cardId: String
    var coverage: [CoverageEntry]
    var manufacturerWarrantyMonths: Int?
    var orderNumber: String?
    var transactionId: String?

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: String = Purchase.newID(), checkId: String?, status: Status, merchant: String, item: String,
        category: String, condition: String, priceUsd: Double, purchaseDate: String, cardId: String,
        coverage: [CoverageEntry], manufacturerWarrantyMonths: Int? = nil, orderNumber: String? = nil,
        transactionId: String? = nil
    ) {
        self.id = id
        self.checkId = checkId
        self.statusRaw = status.rawValue
        self.merchant = merchant
        self.item = item
        self.category = category
        self.condition = condition
        self.priceUsd = priceUsd
        self.purchaseDate = purchaseDate
        self.cardId = cardId
        self.coverage = coverage
        self.manufacturerWarrantyMonths = manufacturerWarrantyMonths
        self.orderNumber = orderNumber
        self.transactionId = transactionId
    }

    static func newID() -> String { "p_" + UUID().uuidString.lowercased() }

    /// A planned purchase from a check's `purchaseDraft`; nil when the draft lacks what a purchase needs.
    convenience init?(planned draft: CheckResponse.PurchaseDraft, checkId: String) {
        guard let merchant = draft.merchant, let item = draft.item, let priceUsd = draft.priceUsd,
              let purchaseDate = draft.purchaseDate, let cardId = draft.cardId
        else { return nil }
        self.init(
            checkId: checkId, status: .planned, merchant: merchant, item: item,
            category: draft.category ?? "general", condition: (draft.condition ?? .unknown).rawValue,
            priceUsd: priceUsd, purchaseDate: purchaseDate, cardId: cardId, coverage: draft.coverage ?? []
        )
    }

    /// "Aero 14" for "Aero 14 Laptop, 14-inch" (R6).
    var shortItemName: String { ItemName.short(item) }
}

/// A copy of a `Purchase` that can cross actors (the app's screens read these, never the model itself).
struct PurchaseSnapshot: Sendable, Equatable, Identifiable, Hashable {
    var id: String
    var checkId: String?
    var status: Purchase.Status
    var merchant: String
    var item: String
    var category: String
    var condition: String
    var priceUsd: Double
    /// yyyy-MM-dd
    var purchaseDate: String
    var cardId: String
    var coverage: [CoverageEntry]
    var manufacturerWarrantyMonths: Int?

    init(_ purchase: Purchase) {
        id = purchase.id
        checkId = purchase.checkId
        status = purchase.status
        merchant = purchase.merchant
        item = purchase.item
        category = purchase.category
        condition = purchase.condition
        priceUsd = purchase.priceUsd
        purchaseDate = purchase.purchaseDate
        cardId = purchase.cardId
        coverage = purchase.coverage
        manufacturerWarrantyMonths = purchase.manufacturerWarrantyMonths
    }

    init(
        id: String, checkId: String?, status: Purchase.Status, merchant: String, item: String, category: String,
        condition: String, priceUsd: Double, purchaseDate: String, cardId: String, coverage: [CoverageEntry],
        manufacturerWarrantyMonths: Int? = nil
    ) {
        self.id = id
        self.checkId = checkId
        self.status = status
        self.merchant = merchant
        self.item = item
        self.category = category
        self.condition = condition
        self.priceUsd = priceUsd
        self.purchaseDate = purchaseDate
        self.cardId = cardId
        self.coverage = coverage
        self.manufacturerWarrantyMonths = manufacturerWarrantyMonths
    }

    var shortItemName: String { ItemName.short(item) }
}

enum ItemName {
    /// R6: the item name before the first comma, with its last word dropped only if what remains contains a digit.
    /// "Aero 14 Laptop, 14-inch" → "Aero 14"; "Wireless Earbuds, Noise-Cancelling" → "Wireless Earbuds".
    static func short(_ name: String) -> String {
        let head = name.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        var words = head.split(whereSeparator: \.isWhitespace)
        guard words.count > 1 else { return head }
        words.removeLast()
        let rest = words.joined(separator: " ")
        return rest.contains(where: \.isNumber) ? rest : head
    }
}
