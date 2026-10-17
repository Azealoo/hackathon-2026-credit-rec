import Foundation
import os

/// "Check a screenshot" in the app (SPEC §5.1, §15.7 step 11): the same pipeline as `CheckCheckoutIntent` —
/// `CheckFlow` with the on-device reader, `/v1/check`, replay and the `CheckRecord` — shown in the app instead of a
/// snippet or the island. [Paying with …] and [What we sent] run the snippet's own intents (the same idempotent save
/// path), then the view reloads from the stored record.
@MainActor
@Observable
final class InAppCheck {
    enum Phase: Equatable {
        case idle
        /// §6.3 *Checking*: "Reading this screen…" / "Only the order summary leaves your phone".
        case checking
        /// A stored check: Switch, Keep, No checkout from the backend, Couldn't check (all read from the record).
        case record(CheckRecord)
        /// No record was written (the on-device gate failed and nothing was sent): the island state's lines.
        case message(PaywiseActivityAttributes.ContentState)
    }

    private(set) var phase: Phase = .idle
    /// The phase shows the last press's result, offered to save (§6.6 "save later"), not a check run here.
    private(set) var showsLastPress = false
    let deps: AppDependencies

    private static let log = Logger(subsystem: "com.azealoo.paywise", category: "in-app-check")

    /// The app's dependencies with the island switched off: in the app the answer shows on screen, so no Live
    /// Activity is started for it.
    init(deps: AppDependencies) {
        var deps = deps
        deps.island = NoIsland()
        self.deps = deps
    }

    var isChecking: Bool { phase == .checking }

    var record: CheckRecord? {
        if case .record(let record) = phase { return record }
        return nil
    }

    func reset() {
        phase = .idle
        showsLastPress = false
    }

    /// §6.3 *Switch fallback* and §6.6: a press whose result had no [Paying with …] (the island alert, or Pattern B's
    /// static snippet) is saved later in the app. Shows the last press's check with [Paying with …] while it can still
    /// be saved: a Switch or Keep-protected record under 24 h old (`CheckStore` drops older ones) with nothing saved
    /// yet. Run when the Check tab appears and whenever the app becomes active; never interrupts a running check.
    func offerLastPress() {
        guard phase != .checking,
              let checkId = deps.settings.lastPressCheckId,
              let record = deps.checkStore.record(id: checkId),
              record.savedPurchaseId == nil,
              CheckResultView.showsSaveButton(record, catalog: deps.catalog)
        else { return }
        if case .record(let shown) = phase, shown.checkId == checkId { return }
        phase = .record(record)
        showsLastPress = true
    }

    #if DEBUG
    /// `-checkState`: opens on a stored answer (Paywise/Debug/CheckTabDemo.swift).
    func show(_ phase: Phase) {
        self.phase = phase
    }
    #endif

    /// Runs one check on `imageData` (a screenshot from Photos, or the bundled sample).
    func run(imageData: Data) async {
        phase = .checking
        showsLastPress = false
        let deps = deps
        // A check run here is now the latest check, so the last press's result is no longer offered.
        deps.settings.lastPressCheckId = nil
        // Signposts `read`, `post` and `record` like a press (CheckTrace), labeled "in-app".
        let outcome = await CheckFlow(deps: deps).run(imageData: imageData, trace: CheckTrace(source: .inApp))
        switch outcome {
        case .snippet(let checkId), .confirm(let checkId, _):
            show(checkId: checkId, fallback: nil)
        case .island(let alert):
            show(checkId: alert.hasRecord ? alert.checkId : nil, fallback: alert.state)
        case .ignored:
            // A screenshot of Paywise's own result: nothing was sent.
            phase = .message(CheckFlow.noCheckoutOnDevice)
        case .notSetUp:
            phase = .message(.init(
                phase: .error, glyph: .warning, line1: CheckFlow.couldntCheck,
                line2: CheckFlow.somethingWentWrong, lockScreenText: PaywiseActivityAttributes.ContentState.checkedLockScreenText
            ))
        }
    }

    #if DEBUG
    /// Every save's outcome, in the order they finished ("saved", "alreadySaved", "failed"), for the `-doubleSave`
    /// UI test.
    private(set) var saveOutcomes: [String] = []
    #endif

    /// [Paying with …]: `SavePurchaseIntent`'s idempotent save, then the Saved view.
    func save() async {
        guard let checkId = record?.checkId else { return }
        let outcome: String
        do {
            switch try await SavePurchaseIntent.save(checkId: checkId, deps: deps) {
            case .saved: outcome = "saved"
            case .alreadySaved: outcome = "alreadySaved"
            }
        } catch {
            outcome = "failed"
            Self.log.error("Save failed: \(String(describing: error), privacy: .public)")
        }
        Self.log.notice("Save \(checkId, privacy: .public): \(outcome, privacy: .public)")
        #if DEBUG
        saveOutcomes.append(outcome)
        #endif
        reload(checkId: checkId)
    }

    /// [What we sent]: `ShowSentIntent`, then the Sent view.
    func showSent() async {
        guard let checkId = record?.checkId else { return }
        do {
            try await Dependencies.$current.withValue(deps) {
                _ = try await ShowSentIntent(checkId: checkId).perform()
            }
        } catch {
            Self.log.error("Show sent failed: \(String(describing: error), privacy: .public)")
        }
        reload(checkId: checkId)
    }

    private func show(checkId: String?, fallback: PaywiseActivityAttributes.ContentState?) {
        if let checkId, let record = deps.checkStore.record(id: checkId) {
            phase = .record(record)
        } else if let fallback {
            phase = .message(fallback)
        } else {
            phase = .idle
        }
    }

    private func reload(checkId: String) {
        if let record = deps.checkStore.record(id: checkId) {
            phase = .record(record)
        }
    }
}

/// The island switched off, for checks whose answer the app shows itself.
struct NoIsland: IslandPresenting {
    func endAll() async {}
    func startChecking(checkId: String) async -> Bool { false }
    func alert(checkId: String, state: PaywiseActivityAttributes.ContentState, sound: AlertSoundChoice) async -> Bool { false }
    func end(checkId: String) async {}
}
