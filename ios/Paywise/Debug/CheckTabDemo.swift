#if DEBUG
import Foundation
import os

/// Debug-only screenshot hook: `-checkState <state>` opens the Check tab on one in-app answer that the island shows
/// after a press (§6.3), drawn as "Check a screenshot" draws it (`InAppResultCard`):
///
///     xcrun simctl launch <device> com.azealoo.paywise -skipOnboarding -tab check -checkState keepDefault
///
/// Each state is built the way a real check builds it: a backend-style decision (`DemoChecks`) stored in a
/// `CheckRecord` with its copy filled for the demo wallet, or `CheckFlow`'s own on-device and error states.
enum CheckTabDemo: String, CaseIterable, Sendable {
    /// *Keep, default best*.
    case keepDefault
    /// *Keep, method* (S2: Apple Pay earns more).
    case keepMethod
    /// *Keep, items unreadable*.
    case keepItemsUnreadable
    /// *No checkout, on device*: no record, nothing was sent.
    case noCheckoutOnDevice
    /// *No checkout, from backend*.
    case noCheckoutFromBackend
    /// *No checkout, already paid*.
    case alreadyPaid
    /// *Couldn't check*: no connection (or a 5xx).
    case couldntCheck
    /// *Couldn't check*: the 6.0 s timeout.
    case tookTooLong

    static let log = Logger(subsystem: "com.azealoo.paywise", category: "demo")

    /// `-checkState <state>` from the launch arguments.
    static func requested(arguments: [String] = ProcessInfo.processInfo.arguments) -> CheckTabDemo? {
        guard let index = arguments.firstIndex(of: "-checkState"), index + 1 < arguments.count else { return nil }
        let value = arguments[index + 1]
        guard let state = CheckTabDemo(rawValue: value) else {
            log.error("-checkState: unknown state \(value, privacy: .public)")
            return nil
        }
        return state
    }

    /// `-doubleSave`: the in-app [Paying with …] runs the save twice at once, so a UI test can show that two saves
    /// racing on one check make one purchase (a synthesized double tap reaches a SwiftUI button as one action).
    static var doubleSave: Bool { ProcessInfo.processInfo.arguments.contains("-doubleSave") }

    /// The Check tab's phase for this state, with the copy filled for `wallet`.
    func phase(catalog: CardCatalog, wallet: Wallet = .demo3Card) -> InAppCheck.Phase? {
        switch self {
        case .noCheckoutOnDevice:
            return .message(CheckFlow.noCheckoutOnDevice)
        case .keepDefault:
            return island(DemoChecks.keepDefaultBest(catalog), catalog: catalog, wallet: wallet)
        case .keepMethod:
            return island(DemoChecks.keepMethod(catalog), catalog: catalog, wallet: wallet)
        case .keepItemsUnreadable:
            return island(DemoChecks.keepItemsUnreadable(catalog), catalog: catalog, wallet: wallet)
        case .noCheckoutFromBackend:
            return island(DemoChecks.noCheckoutFromBackend, catalog: catalog, wallet: wallet)
        case .alreadyPaid:
            return island(DemoChecks.alreadyPaid, catalog: catalog, wallet: wallet)
        case .couldntCheck, .tookTooLong:
            let failure: PaywiseAPI.Failure = self == .tookTooLong ? .timeout : .offline
            guard let response = try? CheckFlow.couldntCheckResponse(checkId: "demo", failure: failure)
                .decode(CheckResponse.self)
            else { return nil }
            return record(response, catalog: catalog, wallet: wallet)
        }
    }

    /// The demo laptop's response with `decision` in place of the switch, and no purchase to save.
    private func island(_ decision: CheckResponse.Decision, catalog: CardCatalog, wallet: Wallet) -> InAppCheck.Phase? {
        guard var response = DemoChecks.laptopSwitch() else { return nil }
        response.decision = decision
        response.purchaseDraft = nil
        return record(response, catalog: catalog, wallet: wallet)
    }

    private func record(_ response: CheckResponse, catalog: CardCatalog, wallet: Wallet) -> InAppCheck.Phase? {
        DemoChecks.record(
            response, wallet: wallet, catalog: catalog, ocrText: ScreenReading.laptopCheckout.redactedText
        ).map { .record($0) }
    }
}
#endif
