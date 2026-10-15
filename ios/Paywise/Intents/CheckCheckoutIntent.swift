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
        let deps = Dependencies.current
        let outcome = await CheckFlow(deps: deps).run(imageData: image?.data)

        switch outcome {
        case .notSetUp:
            return .result(snippetIntent: MessageSnippetIntent.notSetUp)

        case .snippet(let checkId):
            // The Live Activity is ended before the snippet appears (§6.3).
            await deps.island.end()
            return .result(snippetIntent: CheckResultSnippetIntent(checkId: checkId))

        case .confirm(let checkId, let actionName):
            await deps.island.end()
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
                try? await Task.sleep(for: alert.hold)
                await deps.island.end()
                return .result(snippetIntent: EmptySnippetIntent())
            }
            // No Live Activity could show (§6.6): the same state as a static snippet.
            await deps.island.end()
            if alert.hasRecord {
                return .result(snippetIntent: CheckResultSnippetIntent(checkId: alert.checkId))
            }
            return .result(snippetIntent: MessageSnippetIntent(state: alert.state))
        }
    }
}
