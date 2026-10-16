import AppIntents
import Foundation

/// The "Paywise" Shortcut's action (SPEC §9.1, §15.5): reads the checkout screenshot on the phone, asks `/v1/check`,
/// and answers with an interactive snippet or an island alert. Main app target only; deliberately not in an
/// `AppShortcutsProvider` (§15.9). Every path ends its Live Activity before returning, and no path can run past 30 s:
/// reading ≤8 s + request ≤6 s + hold ≤8 s.
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
        trace.begin(.pressToResult)
        trace.begin(.intentToChecking)
        let deps = Dependencies.current
        let outcome = await CheckFlow(deps: deps).run(imageData: image?.data, trace: trace)
        trace.begin(.result)

        switch outcome {
        case .notSetUp:
            trace.resultShown()
            return .result(snippetIntent: MessageSnippetIntent.notSetUp)

        case .snippet(let checkId):
            // The Live Activity is ended before the snippet appears (§6.3).
            await deps.island.end()
            trace.resultShown()
            return .result(snippetIntent: CheckResultSnippetIntent(checkId: checkId))

        case .confirm(let checkId, let actionName):
            await deps.island.end()
            // The confirmation prompt shows the result snippet; the wait for the user's tap isn't timed.
            trace.resultShown()
            do {
                try await requestConfirmation(
                    actionName: .custom(
                        acceptLabel: LocalizedStringResource(stringLiteral: actionName),
                        acceptAlternatives: [],
                        denyLabel: "Done",
                        denyAlternatives: []
                    ),
                    snippetIntent: CheckResultSnippetIntent(checkId: checkId)
                )
            } catch {
                // Done, a swipe, or the system refusing the prompt: nothing to save.
                return .result(snippetIntent: EmptySnippetIntent())
            }
            _ = try? await deps.purchases.store().savePlanned(checkId: checkId, checkStore: deps.checkStore)
            return .result(snippetIntent: CheckResultSnippetIntent(checkId: checkId))

        case .island(let alert):
            if await deps.island.alert(checkId: alert.checkId, state: alert.state, sound: alert.sound) {
                trace.resultShown()
                try? await Task.sleep(for: alert.hold)
                await deps.island.end()
                return .result(snippetIntent: EmptySnippetIntent())
            }
            // No Live Activity could show (§6.6): the same state as a static snippet.
            await deps.island.end()
            trace.resultShown()
            if alert.hasRecord {
                return .result(snippetIntent: CheckResultSnippetIntent(checkId: alert.checkId))
            }
            return .result(snippetIntent: MessageSnippetIntent(state: alert.state))
        }
    }
}
