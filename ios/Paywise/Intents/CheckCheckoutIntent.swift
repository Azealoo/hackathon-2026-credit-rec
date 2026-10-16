import AppIntents
import Foundation

/// The "Paywise" Shortcut's action (SPEC §9.1, §15.5): reads the checkout screenshot on the phone, asks `/v1/check`,
/// and answers with an interactive snippet or an island alert. Main app target only; deliberately not in an
/// `AppShortcutsProvider` (§15.9). Every path ends its Live Activity before returning, and no path can run past 30 s
/// (§6.2): reading ≤8 s + request ≤6 s + hold ≤8 s, and Pattern B's confirmation prompt is given up at
/// `AppDependencies.intentLimit` (28 s) after the press.
struct CheckCheckoutIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Check Checkout"
    static var description: IntentDescription? {
        IntentDescription("Reads the checkout on screen and tells you which of your cards covers this purchase.")
    }
    static var supportedModes: IntentModes { [.background] }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Screenshot", supportedContentTypes: [.image])
    var image: IntentFile?

    init() {}

    init(image: IntentFile?) {
        self.image = image
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetIntent {
        try await perform(trace: CheckTrace(source: .intent))
    }

    /// `perform()`, timed by `trace` (SPEC §15.7 step 6: os_signpost per link, `CheckTrace`). Tests pass their own
    /// trace to read the links back. `result` and `press-to-result` end when the answer is handed to the system or the
    /// island alert is sent, before any hold.
    @MainActor
    func perform(trace: CheckTrace) async throws -> some IntentResult & ShowsSnippetIntent {
        let started = ContinuousClock.now
        trace.begin(.pressToResult)
        trace.begin(.intentToChecking)
        let deps = Dependencies.current
        let outcome = await CheckFlow(deps: deps).run(imageData: image?.data, trace: trace)
        trace.begin(.result)
        if let checkId = outcome.recordCheckId {
            // §6.6 "save later": in the fallback modes a Switch or Keep-protected result shows without its own
            // [Paying with …] (the island alert, Pattern B's static snippet or an unanswered prompt), so the Check tab
            // offers this press's result. Pattern A's snippet has the button: nothing is offered.
            deps.settings.lastPressCheckId = deps.settings.snippetMode == .snippet ? nil : checkId
        }

        switch outcome {
        case .notSetUp:
            trace.resultShown()
            return .result(snippetIntent: MessageSnippetIntent.notSetUp)

        case .snippet(let checkId):
            // The Live Activity is ended before the snippet appears (§6.3).
            await deps.island.end(checkId: checkId)
            trace.resultShown()
            return .result(snippetIntent: CheckResultSnippetIntent(checkId: checkId))

        case .confirm(let checkId, let actionName):
            await deps.island.end(checkId: checkId)
            // The confirmation prompt shows the result snippet. The wait for the user's tap is bounded: §6.2's 30 s
            // covers the whole intent, so the prompt is given up at `intentLimit` after the press.
            trace.resultShown()
            let intent = self
            let answer = await Self.confirmation(within: deps.intentLimit - (ContinuousClock.now - started)) {
                try await intent.requestConfirmation(
                    actionName: .custom(
                        acceptLabel: LocalizedStringResource(stringLiteral: actionName),
                        acceptAlternatives: [],
                        denyLabel: "Done",
                        denyAlternatives: []
                    ),
                    snippetIntent: CheckResultSnippetIntent(checkId: checkId)
                )
            }
            guard answer == .confirmed else {
                // Done, a swipe, the system refusing the prompt, or no answer in time: nothing to save (the Check tab
                // still offers it). On a timeout, make sure this check's activity is gone before returning.
                if answer == .timedOut { await deps.island.end(checkId: checkId) }
                return .result(snippetIntent: EmptySnippetIntent())
            }
            _ = try? await deps.purchases.store().savePlanned(checkId: checkId, checkStore: deps.checkStore)
            return .result(snippetIntent: CheckResultSnippetIntent(checkId: checkId))

        case .island(let alert):
            if await deps.island.alert(checkId: alert.checkId, state: alert.state, sound: alert.sound) {
                trace.resultShown()
                try? await Task.sleep(for: alert.hold)
                await deps.island.end(checkId: alert.checkId)
                return .result(snippetIntent: EmptySnippetIntent())
            }
            // No Live Activity could show (§6.6): the same state as a static snippet.
            await deps.island.end(checkId: alert.checkId)
            trace.resultShown()
            if alert.hasRecord {
                return .result(snippetIntent: CheckResultSnippetIntent(checkId: alert.checkId))
            }
            return .result(snippetIntent: MessageSnippetIntent(state: alert.state))
        }
    }

    /// How Pattern B's prompt ended.
    enum Confirmation: Equatable, Sendable {
        /// The custom verb ([Paying with …]).
        case confirmed
        /// Done, a swipe, or the system refusing or cancelling the prompt.
        case declined
        /// No answer within the time left (§6.2).
        case timedOut
    }

    /// Waits for `prompt` at most `limit` (nothing at all when no time is left), even if the prompt ignores
    /// cancellation (`withHardDeadline`).
    static func confirmation(
        within limit: Duration, _ prompt: @escaping @Sendable () async throws -> Void
    ) async -> Confirmation {
        guard limit > .zero else { return .timedOut }
        do {
            try await withHardDeadline(limit, prompt)
            return .confirmed
        } catch is DeadlineExceeded {
            return .timedOut
        } catch {
            return .declined
        }
    }
}
