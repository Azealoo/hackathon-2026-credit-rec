import AppIntents
import Foundation

/// [Paying with …] in the result snippet (SPEC §15.5). Saves a planned `Purchase` from the check's `purchaseDraft`,
/// sets `savedPurchaseId` and `view = saved`. Idempotent, including two taps racing: `PurchaseStore` serializes saves
/// and re-checks `savedPurchaseId` inside its critical section. The system then re-performs the snippet intent.
struct SavePurchaseIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Purchase"
    static var isDiscoverable: Bool { false }
    static var supportedModes: IntentModes { [.background] }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Check ID")
    var checkId: String

    init() {}

    init(checkId: String) {
        self.checkId = checkId
    }

    func perform() async throws -> some IntentResult {
        _ = try await Self.save(checkId: checkId, deps: Dependencies.current)
        return .result()
    }

    /// The save itself: the snippet's button (`perform()`) and the app's own [Paying with …] (`InAppCheck`) both run
    /// it, so they share one idempotent path.
    static func save(checkId: String, deps: AppDependencies) async throws -> PurchaseStore.SaveOutcome {
        try await deps.purchases.store().savePlanned(checkId: checkId, checkStore: deps.checkStore)
    }
}

/// [What we sent] in the Saved snippet (SPEC §15.5): switches the snippet to the *Sent* view.
struct ShowSentIntent: AppIntent {
    static let title: LocalizedStringResource = "Show What Was Sent"
    static var isDiscoverable: Bool { false }
    static var supportedModes: IntentModes { [.background] }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Check ID")
    var checkId: String

    init() {}

    init(checkId: String) {
        self.checkId = checkId
    }

    func perform() async throws -> some IntentResult {
        try Dependencies.current.checkStore.update(id: checkId) { record in
            record.view = .sent
        }
        return .result()
    }
}
