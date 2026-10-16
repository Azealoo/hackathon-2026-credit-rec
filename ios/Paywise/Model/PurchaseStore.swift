import Foundation
import SwiftData
import Synchronization

/// Saves purchases. One actor per container serializes every save, and `savePlanned` has no suspension point,
/// so two taps on [Paying with …] racing each other run one after the other and the second sees the first's ID.
@ModelActor
actor PurchaseStore {
    enum SaveError: Error, Equatable {
        case checkNotFound
        case nothingToSave
    }

    enum SaveOutcome: Sendable, Equatable {
        case saved(id: String)
        case alreadySaved(id: String)

        var purchaseId: String {
            switch self {
            case .saved(let id), .alreadySaved(let id): id
            }
        }
    }

    /// `SavePurchaseIntent`'s critical section (SPEC §15.5): idempotent per check.
    func savePlanned(checkId: String, checkStore: CheckStore) throws -> SaveOutcome {
        guard let record = checkStore.record(id: checkId) else { throw SaveError.checkNotFound }
        if let existing = record.savedPurchaseId {
            return .alreadySaved(id: existing)
        }

        // A purchase from this check may exist if the app stopped between the two writes below; reuse it.
        let purchaseId: String
        let outcome: SaveOutcome
        if let existing = try purchases(checkId: checkId).first {
            purchaseId = existing.id
            outcome = .alreadySaved(id: purchaseId)
        } else {
            guard let draft = record.parsedResponse.purchaseDraft,
                  let purchase = Purchase(planned: draft, checkId: checkId)
            else { throw SaveError.nothingToSave }
            modelContext.insert(purchase)
            try modelContext.save()
            purchaseId = purchase.id
            outcome = .saved(id: purchaseId)
        }

        try checkStore.update(id: checkId) { record in
            record.savedPurchaseId = purchaseId
            record.view = .saved
        }
        return outcome
    }

    /// Every purchase, newest purchase date first.
    func all() throws -> [PurchaseSnapshot] {
        try modelContext.fetch(FetchDescriptor<Purchase>()).map(PurchaseSnapshot.init)
            .sorted { ($0.purchaseDate, $0.id) > ($1.purchaseDate, $1.id) }
    }

    func purchase(id: String) throws -> PurchaseSnapshot? {
        try find(id).map(PurchaseSnapshot.init)
    }

    /// "I bought this", or [Yes] in the claim input (§5.4, §5.5): planned → confirmed.
    @discardableResult
    func confirm(id: String) throws -> PurchaseSnapshot? {
        guard let purchase = try find(id) else { return nil }
        purchase.status = .confirmed
        try modelContext.save()
        return PurchaseSnapshot(purchase)
    }

    /// [No, another card] in the claim input: the purchase was paid with `cardId`, so it is confirmed with that card.
    /// The saved coverage dates belonged to the old card's terms, so they are cleared; the coverage check works the
    /// dates out again for the new card.
    @discardableResult
    func confirm(id: String, paidWith cardId: String) throws -> PurchaseSnapshot? {
        guard let purchase = try find(id) else { return nil }
        if purchase.cardId != cardId {
            purchase.cardId = cardId
            purchase.coverage = []
        }
        purchase.status = .confirmed
        try modelContext.save()
        return PurchaseSnapshot(purchase)
    }

    /// The maker's warranty the user picked (nil for "Don't know").
    func setManufacturerWarranty(id: String, months: Int?) throws {
        guard let purchase = try find(id) else { return }
        purchase.manufacturerWarrantyMonths = months
        try modelContext.save()
    }

    func delete(id: String) throws {
        guard let purchase = try find(id) else { return }
        modelContext.delete(purchase)
        try modelContext.save()
    }

    func deleteAll() throws {
        try modelContext.delete(model: Purchase.self)
        try modelContext.save()
    }

    private func find(_ id: String) throws -> Purchase? {
        let id = id
        return try modelContext.fetch(FetchDescriptor<Purchase>(predicate: #Predicate { $0.id == id })).first
    }

    private func purchases(checkId: String) throws -> [Purchase] {
        let id: String? = checkId
        return try modelContext.fetch(FetchDescriptor<Purchase>(predicate: #Predicate { $0.checkId == id }))
    }
}

/// Creates the one `PurchaseStore` lazily, so a check that never saves doesn't open SwiftData.
final class PurchaseStoreProvider: Sendable {
    private let makeContainer: @Sendable () throws -> ModelContainer
    private let cached = Mutex<PurchaseStore?>(nil)

    init(makeContainer: @escaping @Sendable () throws -> ModelContainer) {
        self.makeContainer = makeContainer
    }

    func store() throws -> PurchaseStore {
        try cached.withLock { cached in
            if let cached { return cached }
            let store = PurchaseStore(modelContainer: try makeContainer())
            cached = store
            return store
        }
    }

    /// SwiftData in the App Group container (SPEC §9.1), shared by the app and its intents.
    static let appGroup = PurchaseStoreProvider {
        let configuration = ModelConfiguration(
            "Purchases",
            schema: Schema([Purchase.self]),
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: Purchase.self, configurations: configuration)
    }

    static func inMemory() -> PurchaseStoreProvider {
        PurchaseStoreProvider {
            try ModelContainer(
                for: Purchase.self,
                configurations: ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            )
        }
    }
}
