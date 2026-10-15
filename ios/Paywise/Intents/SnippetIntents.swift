import AppIntents
import SwiftUI

/// The interactive result snippet (SPEC §15.5). Reads the `CheckRecord` and shows its current view (Result, Saved or
/// Sent). No side effects: the system re-performs it after each button.
struct CheckResultSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Check Result"
    static var isDiscoverable: Bool { false }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Check ID")
    var checkId: String

    init() {}

    init(checkId: String) {
        self.checkId = checkId
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let deps = Dependencies.current
        let record = deps.checkStore.record(id: checkId)
        return .result(view: CheckSnippetView(
            record: record,
            catalog: deps.catalog,
            // In Pattern B the system's confirm verb is the button, so the view doesn't add its own.
            showsSaveButton: deps.settings.snippetMode != .confirm
        ))
    }
}

/// A static snippet of up to three lines: *Not set up*, and island states shown when no Live Activity can (§6.6).
struct MessageSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Paywise Message"
    static var isDiscoverable: Bool { false }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Line 1")
    var line1: String
    @Parameter(title: "Line 2")
    var line2: String?
    @Parameter(title: "Line 3")
    var line3: String?
    @Parameter(title: "Warning", default: false)
    var isWarning: Bool

    init() {}

    init(line1: String, line2: String?, line3: String?, isWarning: Bool) {
        self.line1 = line1
        self.line2 = line2
        self.line3 = line3
        self.isWarning = isWarning
    }

    init(state: PaywiseActivityAttributes.ContentState) {
        self.init(line1: state.line1, line2: state.line2, line3: state.line3, isWarning: state.glyph == .warning)
    }

    /// §6.3 *Not set up*: the intent ran with no image.
    static var notSetUp: MessageSnippetIntent {
        MessageSnippetIntent(
            line1: "Use the Paywise shortcut",
            line2: "It reads the screen for you",
            line3: "Set it up in the Paywise app",
            isWarning: false
        )
    }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: MessageSnippetView(line1: line1, line2: line2, line3: line3, isWarning: isWarning))
    }
}
