import Foundation
import Testing
@testable import Paywise

/// The DEBUG screenshot hooks: `-demoActivity` and `-gallery` parse, and every gallery state shows SPEC §6.3 copy.
struct DebugHookTests {
    @Test func demoActivityArguments() {
        for demo in DemoActivity.allCases {
            #expect(DemoActivity.command(arguments: ["Paywise", "-demoActivity", demo.rawValue]) == .start(demo))
        }
        #expect(DemoActivity.command(arguments: ["Paywise", "-demoActivity", "end"]) == .end)
        #expect(DemoActivity.command(arguments: ["Paywise", "-demoActivity", "nonsense"]) == nil)
        #expect(DemoActivity.command(arguments: ["Paywise", "-demoActivity"]) == nil)
        #expect(DemoActivity.command(arguments: ["Paywise"]) == nil)
        #expect(Set(DemoActivity.allCases.map(\.rawValue)) == [
            "checking", "keep", "keepMethod", "noCheckout", "couldntCheck", "switchFallback", "stale",
        ])
    }

    @Test func demoSoundsMatchARealPress() {
        let settings = PaywiseSettings(suiteName: "paywise.tests.\(UUID().uuidString)")
        settings.silentAlerts = true
        #expect(DemoActivity.keep.sound(settings: settings) == .silent)
        #expect(DemoActivity.switchFallback.sound(settings: settings) == .standard)
        settings.silentAlerts = false
        #expect(DemoActivity.couldntCheck.sound(settings: settings) == .standard)
        #expect(!DemoActivity.checking.alerts && !DemoActivity.stale.alerts && DemoActivity.keep.alerts)
    }

    /// `stale` is requested 5 s before it goes stale, so the system flips it (a staleDate already past at request time
    /// draws nothing in the island); the other demo states never go stale.
    @Test func onlyTheStaleDemoGoesStaleFiveSecondsAfterTheRequest() {
        #expect(DemoActivity.stale.staleDelay == 5)
        for demo in DemoActivity.allCases where demo != .stale {
            #expect(demo.staleDelay == nil, "\(demo.rawValue)")
        }
    }

    @Test func galleryArguments() {
        for state in GalleryState.allCases {
            #expect(GalleryState.requested(arguments: ["Paywise", "-gallery", state.rawValue]) == state)
        }
        #expect(GalleryState.requested(arguments: ["Paywise", "-gallery", "nonsense"]) == nil)
        #expect(GalleryState.requested(arguments: ["Paywise"]) == nil)
        #expect(Set(GalleryState.allCases.map(\.rawValue)) == [
            "result", "resultCashBest", "resultCash", "keepProtected", "saved", "savedEarbuds", "sent", "notSetUp",
        ])
    }

    struct ResultCopy: Sendable {
        var kind: DecisionKind
        var reason: DecisionReason
        var copy: CheckRecord.FilledCopy
        var eligibilityNote: String?
        var button: String
    }

    static let resultCopy: [GalleryState: ResultCopy] = [
        .result: ResultCopy(
            kind: .switch, reason: .protection,
            copy: .init(
                line1: "Use Freedom ••1234", line2: "Adds a warranty year + $500 theft cover",
                line3: "$7.49 less cash back than Active Cash", instruction: "Change card to Visa ••1234, then place order"
            ),
            button: "Paying with Freedom"
        ),
        .resultCashBest: ResultCopy(
            kind: .switch, reason: .protection,
            copy: .init(
                line1: "Use Freedom ••1234", line2: "Adds a warranty year + $500 theft cover",
                line3: "Also earns the most cash back here", instruction: "Change card to Visa ••1234, then place order"
            ),
            button: "Paying with Freedom"
        ),
        .resultCash: ResultCopy(
            kind: .switch, reason: .cash,
            copy: .init(
                line1: "Use Active Cash ••4321", line2: "$10.99 more cash back than Apple Card",
                line3: nil, instruction: "Change card to Visa ••4321, then place order"
            ),
            eligibilityNote: "Renewed, no warranty: no card covers it",
            button: "Paying with Active Cash"
        ),
        .keepProtected: ResultCopy(
            kind: .keep, reason: .alreadyProtected,
            copy: .init(
                line1: "✓ Keep Freedom ••1234", line2: "Adds a warranty year + $500 theft cover",
                line3: "Save it so you can claim later", instruction: nil
            ),
            button: "Paying with Freedom"
        ),
    ]

    @Test(arguments: [GalleryState.result, .resultCashBest, .resultCash, .keepProtected])
    func galleryResultCopy(_ state: GalleryState) throws {
        let catalog = CardCatalog.bundled()
        let expected = try #require(Self.resultCopy[state])
        let record = try #require(state.record(catalog: catalog))
        let decision = try #require(record.parsedResponse.decision)
        #expect(record.view == .result)
        #expect(decision.kind == expected.kind)
        #expect(decision.reason == expected.reason)
        #expect(record.filledCopy == expected.copy)
        #expect(decision.eligibilityNotes?.first == expected.eligibilityNote)
        #expect(ResultText.primaryButtonTitle(decision: decision, catalog: catalog) == expected.button)
        #expect(record.parsedResponse.purchaseDraft != nil)
    }

    @Test func gallerySaved() throws {
        let record = try #require(GalleryState.saved.record(catalog: .bundled()))
        #expect(record.view == .saved)
        #expect(ResultText.saved(record.parsedResponse.purchaseDraft) == .init(
            line1: "✓ Saved: Aero 14 · $1,499",
            line2: "Theft & damage cover up to $500 to Feb 14, 2027",
            line3: "Extra warranty year to Oct 17, 2028*",
            footnote: "*If the maker's warranty is 1 year. Planned: confirm after you pay."
        ))
    }

    @Test func gallerySavedEarbuds() throws {
        let record = try #require(GalleryState.savedEarbuds.record(catalog: .bundled()))
        #expect(record.view == .saved)
        #expect(ResultText.saved(record.parsedResponse.purchaseDraft) == .init(
            line1: "✓ Saved: Wireless Earbuds · $249",
            line2: "Theft & damage cover up to $500 to Feb 14, 2027",
            line3: "Extra warranty year to Oct 17, 2028*",
            footnote: "*If the maker's warranty is 1 year. Planned: confirm after you pay."
        ))
    }

    @Test func gallerySentShowsTheRedactedTextWithoutLast4() throws {
        let record = try #require(GalleryState.sent.record(catalog: .bundled()))
        #expect(record.view == .sent)
        #expect(record.sentText == ScreenReading.laptopCheckout.redactedText)
        #expect(!record.replayed)
        let payload = String(decoding: try JSONEncoder().encode(record.sentPayload), as: UTF8.self)
        for last4 in ["1234", "5678", "4321"] {
            #expect(!payload.contains(last4))
        }
    }

    @Test func galleryNotSetUp() {
        #expect(GalleryState.notSetUp.record(catalog: .bundled()) == nil)
        let message = MessageSnippetIntent.notSetUp
        #expect(message.line1 == "Use the Paywise shortcut")
        #expect(message.line2 == "It reads the screen for you")
        #expect(message.line3 == "Set it up in the Paywise app")
    }
}
