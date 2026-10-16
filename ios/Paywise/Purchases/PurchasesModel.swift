import Foundation
import os

/// The saved purchases for the app's screens, read from and written through the one `PurchaseStore` actor (the same
/// store `SavePurchaseIntent` saves into), as value snapshots. Reloaded whenever a screen appears or the app becomes
/// active, so a purchase saved from the snippet shows up.
@MainActor
@Observable
final class PurchasesModel {
    private(set) var purchases: [PurchaseSnapshot] = []
    private(set) var loaded = false
    let deps: AppDependencies

    private static let log = Logger(subsystem: "com.azealoo.paywise", category: "purchases")

    init(deps: AppDependencies) {
        self.deps = deps
    }

    var wallet: Wallet { deps.walletStore.load() }

    func purchase(id: String) -> PurchaseSnapshot? {
        purchases.first { $0.id == id }
    }

    func reload() async {
        do {
            purchases = try await deps.purchases.store().all()
        } catch {
            Self.log.error("Couldn't read purchases: \(String(describing: error), privacy: .public)")
        }
        loaded = true
    }

    /// "I bought this" (§5.4).
    func confirm(id: String) async {
        await change { try await $0.confirm(id: id) }
    }

    /// [Yes] or [No, another card] in the claim input (§5.5).
    func confirm(id: String, paidWith cardId: String) async {
        await change { try await $0.confirm(id: id, paidWith: cardId) }
    }

    func setManufacturerWarranty(id: String, months: Int?) async {
        await change { try await $0.setManufacturerWarranty(id: id, months: months) }
    }

    func delete(id: String) async {
        await change { try await $0.delete(id: id) }
    }

    private func change<T>(_ body: (PurchaseStore) async throws -> T) async {
        do {
            _ = try await body(deps.purchases.store())
        } catch {
            Self.log.error("Couldn't change a purchase: \(String(describing: error), privacy: .public)")
        }
        await reload()
    }
}
