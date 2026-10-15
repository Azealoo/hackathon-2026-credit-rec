import Foundation
import Testing
@testable import Paywise

/// `SavePurchaseIntent` / `ShowSentIntent` (SPEC §15.5, §15.7 step 12a).
struct SavePurchaseTests {
    private func environmentWithRecord() throws -> (TestEnvironment, CheckRecord) {
        let env = TestEnvironment(reading: .laptopCheckout)
        let record = try Fixtures.recordExample()
        try env.deps.checkStore.write(record, now: Fixtures.demoNow)
        return (env, record)
    }

    @Test func doubleTapRacingSavesExactlyOnePurchase() async throws {
        let (env, record) = try environmentWithRecord()
        let checkId = record.checkId

        try await Dependencies.$current.withValue(env.deps) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<4 {
                    group.addTask { _ = try await SavePurchaseIntent(checkId: checkId).perform() }
                }
                try await group.waitForAll()
            }
        }

        let purchases = try await env.deps.purchases.store().all()
        #expect(purchases.count == 1)
        let purchase = try #require(purchases.first)
        #expect(purchase.checkId == checkId)
        #expect(purchase.status == .planned)
        #expect(purchase.cardId == "chase-freedom-unlimited")
        #expect(purchase.id.hasPrefix("p_"))

        let updated = try #require(env.deps.checkStore.record(id: checkId))
        #expect(updated.savedPurchaseId == purchase.id)
        #expect(updated.view == .saved)
    }

    @Test func savingAgainLaterDoesNothing() async throws {
        let (env, record) = try environmentWithRecord()
        let store = try env.deps.purchases.store()
        let first = try await store.savePlanned(checkId: record.checkId, checkStore: env.deps.checkStore)
        let second = try await store.savePlanned(checkId: record.checkId, checkStore: env.deps.checkStore)
        #expect(first == .saved(id: first.purchaseId))
        #expect(second == .alreadySaved(id: first.purchaseId))
        #expect(try await store.all().count == 1)
    }

    @Test func unknownCheckThrows() async throws {
        let (env, _) = try environmentWithRecord()
        await #expect(throws: PurchaseStore.SaveError.checkNotFound) {
            _ = try await env.deps.purchases.store().savePlanned(checkId: "nope", checkStore: env.deps.checkStore)
        }
    }

    @Test func showSentSwitchesView() async throws {
        let (env, record) = try environmentWithRecord()
        try await Dependencies.$current.withValue(env.deps) {
            _ = try await ShowSentIntent(checkId: record.checkId).perform()
        }
        #expect(env.deps.checkStore.record(id: record.checkId)?.view == .sent)
    }

    @Test func savedViewCopy() throws {
        let draft = try Fixtures.recordExample().parsedResponse.purchaseDraft
        let saved = ResultText.saved(draft)
        #expect(saved.line1 == "✓ Saved: Aero 14 · $1,499")
        #expect(saved.line2 == "Theft & damage cover up to $500 to Feb 14, 2027")
        #expect(saved.line3 == "Extra warranty year to Oct 17, 2028*")
        #expect(saved.footnote == "*If the maker's warranty is 1 year. Planned: confirm after you pay.")
    }
}

/// R6: the short item name for Saved and Purchases.
struct ItemNameTests {
    @Test(arguments: [
        ("Aero 14 Laptop, 14-inch", "Aero 14"),
        ("Wireless Earbuds, Noise-Cancelling", "Wireless Earbuds"),
        ("Mug", "Mug"),
        ("Ceramic Mug, 12 oz", "Ceramic Mug"),
        ("Aero 14 Laptop", "Aero 14"),
        ("Pro 2", "Pro 2"),
    ])
    func shortName(name: String, expected: String) {
        #expect(ItemName.short(name) == expected)
    }
}
