#if DEBUG
import os
import SwiftUI

/// Debug-only screenshot hook: `-gallery <state>` opens the app on the result snippet in that state, drawn the way the
/// system presents it (design.md §4: material, 40 pt radius, 9 pt side inset, 54 pt from the top).
///
///     xcrun simctl launch <device> com.azealoo.paywise -gallery resultCash
///
/// The snippet's buttons run their intents in the app, where they find no stored check and do nothing.
enum GalleryState: String, CaseIterable, Sendable {
    /// *Switch, protection*: the demo laptop on `demo-3card`.
    case result
    /// *Switch, protection, pick also cash-best*: the laptop on `discover-fu`.
    case resultCashBest
    /// *Switch, cash*: the renewed laptop on `demo-3card`.
    case resultCash
    /// *Keep, protected*: the laptop on `fu-default`.
    case keepProtected
    /// *Saved* after [Paying with Freedom].
    case saved
    /// *Saved* for the demo earbuds: the longest Saved line 1 in the fixtures ("✓ Saved: Wireless Earbuds · $249").
    case savedEarbuds
    /// *Sent* after [What we sent].
    case sent
    /// *Not set up*: the intent ran with no image.
    case notSetUp

    static let log = Logger(subsystem: "com.azealoo.paywise", category: "demo")

    /// `-gallery <state>` from the launch arguments.
    static func requested(arguments: [String] = ProcessInfo.processInfo.arguments) -> GalleryState? {
        guard let index = arguments.firstIndex(of: "-gallery"), index + 1 < arguments.count else { return nil }
        let value = arguments[index + 1]
        guard let state = GalleryState(rawValue: value) else {
            log.error("-gallery: unknown state \(value, privacy: .public)")
            return nil
        }
        return state
    }

    /// The check this state shows; nil for *Not set up*, which has none.
    func record(catalog: CardCatalog) -> CheckRecord? {
        let laptopText = ScreenReading.laptopCheckout.redactedText
        switch self {
        case .result:
            return DemoChecks.laptopSwitch().flatMap {
                DemoChecks.record($0, wallet: .demo3Card, catalog: catalog, ocrText: laptopText)
            }
        case .resultCashBest:
            return DemoChecks.laptopSwitchAlsoCashBest(catalog).flatMap {
                DemoChecks.record($0, wallet: DemoChecks.discoverFU, catalog: catalog, ocrText: laptopText)
            }
        case .resultCash:
            return DemoChecks.renewedSwitchCash(catalog).flatMap {
                DemoChecks.record($0, wallet: .demo3Card, catalog: catalog, ocrText: DemoChecks.renewedOCRText)
            }
        case .keepProtected:
            return DemoChecks.laptopKeepProtected(catalog).flatMap {
                DemoChecks.record($0, wallet: DemoChecks.fuDefault, catalog: catalog, ocrText: laptopText)
            }
        case .saved:
            return DemoChecks.laptopSwitch().flatMap {
                DemoChecks.record($0, wallet: .demo3Card, catalog: catalog, ocrText: laptopText, view: .saved)
            }
        case .savedEarbuds:
            return DemoChecks.earbudsSwitch().flatMap {
                DemoChecks.record($0, wallet: .demo3Card, catalog: catalog, ocrText: DemoChecks.earbudsOCRText, view: .saved)
            }
        case .sent:
            return DemoChecks.laptopSwitch().flatMap {
                DemoChecks.record($0, wallet: .demo3Card, catalog: catalog, ocrText: laptopText, view: .sent)
            }
        case .notSetUp:
            return nil
        }
    }
}

/// One snippet state, full screen, for screenshots.
struct GalleryScreen: View {
    let state: GalleryState
    var catalog: CardCatalog = Dependencies.current.catalog

    var body: some View {
        VStack(spacing: 0) {
            snippet
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 40, style: .continuous))
                .shadow(color: Color(red: 10 / 255, green: 20 / 255, blue: 60 / 255).opacity(0.22), radius: 30, y: 22)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.top, 54)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
        .ignoresSafeArea()
        .task {
            GalleryState.log.notice("gallery \(state.rawValue, privacy: .public)")
            // The island hook works here too, for a snippet + island screenshot.
            if let command = DemoActivity.command() {
                _ = await DemoActivity.run(command)
            }
        }
    }

    @ViewBuilder private var snippet: some View {
        if state == .notSetUp {
            let message = MessageSnippetIntent.notSetUp
            MessageSnippetView(line1: message.line1, line2: message.line2, line3: message.line3, isWarning: message.isWarning)
        } else {
            CheckSnippetView(record: state.record(catalog: catalog), catalog: catalog)
        }
    }
}

#Preview("Gallery") {
    GalleryScreen(state: .resultCash, catalog: .bundled())
}
#endif
