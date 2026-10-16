import AppIntents
import SwiftUI

/// The result snippet's three views (SPEC §6.3): *Result*, *Saved* and *Sent*, chosen by `record.view`.
/// Type follows docs/design.md §3 (sizes scale with Dynamic Type); secondary lines drop first at large sizes (§6.4).
/// Also renders island-only results (Keep, No checkout, Couldn't check) when no Live Activity can show them (§6.6).
struct CheckResultView: View {
    /// In the app (not the system snippet) the buttons run these instead of `Button(intent:)`, so the app's own view
    /// can reload after the same save path (`SavePurchaseIntent`) runs.
    struct InAppActions {
        var save: @MainActor () -> Void
        var showSent: @MainActor () -> Void
    }

    let record: CheckRecord
    var catalog: CardCatalog
    var showsSaveButton: Bool
    var actions: InAppActions?

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title2) private var line1Size: CGFloat = 23
    @ScaledMetric(relativeTo: .callout) private var lineSize: CGFloat = 16
    @ScaledMetric(relativeTo: .subheadline) private var savedSize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var instructionSize: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var footnoteSize: CGFloat = 13

    init(
        record: CheckRecord, catalog: CardCatalog = Dependencies.current.catalog, showsSaveButton: Bool = true,
        actions: InAppActions? = nil
    ) {
        self.record = record
        self.catalog = catalog
        self.showsSaveButton = showsSaveButton
        self.actions = actions
    }

    private var response: CheckResponse { record.parsedResponse }
    private var decision: CheckResponse.Decision? { response.decision }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SnippetHeader(replayed: record.replayed && record.view == .sent)
            switch record.view {
            case .result: result
            case .saved: saved
            case .sent: sent
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Result

    /// Switch and Keep-protected carry [Paying with …] (§6.3); island-only results never do.
    private var isActionable: Bool { Self.isActionable(response) }

    static func isActionable(_ response: CheckResponse) -> Bool {
        let decision = response.decision
        let savable = decision?.kind == .switch || (decision?.kind == .keep && decision?.reason == .alreadyProtected)
        return savable && response.purchaseDraft != nil
    }

    /// Whether this record's view shows [Paying with …], the one primary button (the app keeps its own secondary).
    static func showsSaveButton(_ record: CheckRecord, catalog: CardCatalog) -> Bool {
        let response = record.parsedResponse
        return record.view == .result && isActionable(response)
            && ResultText.primaryButtonTitle(decision: response.decision, catalog: catalog) != nil
    }

    private var copy: CheckRecord.FilledCopy { Self.displayedCopy(record) }

    /// Lines 1–3 as shown. Only *Switch, cash* puts an eligibility note in an empty line 3 (§6.3): the first one
    /// within §6.2's 44 characters, as the backend's `switch_cash` does. Every other state keeps line 3 as sent:
    /// *Keep, default best* has none ("—") even when the decision carries a note.
    static func displayedCopy(_ record: CheckRecord) -> CheckRecord.FilledCopy {
        var copy = record.filledCopy
        let decision = record.parsedResponse.decision
        if copy.line3 == nil, decision?.kind == .switch, decision?.reason == .cash,
           let note = decision?.eligibilityNotes?.first(where: { !$0.isEmpty && $0.count <= 44 }) {
            copy.line3 = note
        }
        return copy
    }

    @ViewBuilder private var result: some View {
        let copy = copy
        let cardId = decision?.recommendedCardId ?? decision?.defaultCardId
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                if isActionable || decision?.kind == .keep {
                    cardArt(cardId)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: line1Size * 0.9))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(copy.line1)
                    .font(.system(size: line1Size, weight: .bold))
                    .tracking(-0.5)
                    .lineLimit(oneLine ? 1 : 3)
                    .minimumScaleFactor(0.7)
                    // Shrink only to fit the width: the row can be offered less height than the line needs, which
                    // otherwise squeezes 23 pt down to the 70% floor (seen when rendering the snippet).
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("result.line1")
            }
            if let line2 = copy.line2 {
                Text(line2)
                    .font(.system(size: lineSize, weight: .medium))
                    .tracking(-0.2)
                    .accessibilityIdentifier("result.line2")
            }
            if showsLine3, let line3 = copy.line3 {
                Text(line3)
                    .font(.system(size: lineSize))
                    .tracking(-0.2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("result.line3")
            }
        }
        .monospacedDigit()
        // The system snippet reads as one spoken phrase (§6.4); in the app each line stays its own element, read as
        // shown, so UI tests can check the exact §6.3 copy.
        .modifier(SpokenLines(label: actions == nil ? SpokenCopy.label(copy) : nil))

        if showsInstruction, let instruction = copy.instruction {
            Text("↳ \(instruction)")
                .font(.system(size: instructionSize))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                // Spoken in the snippet (§6.4); in the app read as shown without the arrow, like lines 1–3 above.
                .accessibilityLabel(actions == nil ? SpokenCopy.spoken(instruction) : instruction)
                .accessibilityIdentifier("result.instruction")
        }

        if showsSaveButton, isActionable, let title = ResultText.primaryButtonTitle(decision: decision, catalog: catalog) {
            Group {
                if let actions {
                    Button(action: actions.save) { Text(title) }
                } else {
                    Button(intent: SavePurchaseIntent(checkId: record.checkId)) { Text(title) }
                }
            }
            .buttonStyle(SnippetButtonStyle(prominent: true))
            .accessibilityIdentifier("result.save")
        }
    }

    // MARK: Saved

    @ViewBuilder private var saved: some View {
        let saved = ResultText.saved(response.purchaseDraft)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                cardArt(response.purchaseDraft?.cardId)
                if oneLine && !savedLinesWrap {
                    SavedLine1(lines: saved.line1Cuts, size: line1Size)
                } else {
                    // Wraps from XL like lines 2–3: at XXL one line can't hold "✓ Saved: Wireless Earbuds · $249"
                    // even at 70%, and the cut would drop the price.
                    Text(saved.line1)
                        .font(.system(size: line1Size, weight: .bold))
                        .tracking(-0.5)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach([saved.line2, showsLine3 ? saved.line3 : nil].compactMap { $0 }, id: \.self) { line in
                // One line at the default sizes (shrinking a little); from XL a line wraps rather than cut off a
                // coverage date ("…to Feb 14, 2027").
                Text(line)
                    .font(.system(size: savedSize, weight: .medium))
                    .tracking(-0.3)
                    .lineLimit(savedLinesWrap ? nil : 1)
                    .minimumScaleFactor(savedLinesWrap ? 1 : 0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsFootnote {
                Text(saved.footnote)
                    .font(.system(size: footnoteSize))
                    .lineSpacing(2)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("result.saved")

        Group {
            if let actions {
                Button(action: actions.showSent) { Text("What we sent") }
            } else {
                Button(intent: ShowSentIntent(checkId: record.checkId)) { Text("What we sent") }
            }
        }
        .buttonStyle(SnippetButtonStyle(prominent: false))
        .accessibilityIdentifier("result.whatWeSent")
    }

    // MARK: Sent

    @ViewBuilder private var sent: some View {
        Text("What left your iPhone")
            .font(.system(size: line1Size, weight: .bold))
            .tracking(-0.5)
            .accessibilityIdentifier("result.sentTitle")
        // The whole text when it fits; scrolls only when it doesn't (scrolling in a snippet is unverified).
        ViewThatFits(in: .vertical) {
            sentText
            ScrollView { sentText }
        }
        .frame(maxHeight: 180)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        Text("Cards sent as product names only. No screenshot, no last 4.")
            .font(.system(size: footnoteSize))
            .foregroundStyle(.secondary)
    }

    private var sentText: some View {
        Text(record.sentText)
            .font(.system(size: footnoteSize, design: .monospaced))
            .accessibilityIdentifier("result.sentText")
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
    }

    // MARK: Parts

    /// The verdict line 1 stays on one line (shrinking a little) until accessibility sizes; Saved line 1 until XL.
    private var oneLine: Bool { !typeSize.isAccessibilitySize }
    /// Saved lines 1–3 wrap from XL: at XXL one line can't hold "…up to $500 to Feb 14, 2027" even at 85%.
    private var savedLinesWrap: Bool { typeSize >= .xLarge }

    /// The same expanded art as the island (SPEC §6.4), `art.assetName` from cards.json.
    private func cardArt(_ cardId: String?) -> some View {
        let card = catalog.card(cardId)
        return CardArtView(assetName: card?.art?.assetName, colorHex: card?.art?.color)
            .frame(width: CardArt.expandedSize.width, height: CardArt.expandedSize.height)
    }

    /// Dynamic Type drops secondary lines first: line 3 (and the Saved footnote), then the instruction.
    private var showsLine3: Bool { typeSize < .accessibility2 }
    private var showsFootnote: Bool { typeSize < .accessibility1 }
    private var showsInstruction: Bool { typeSize < .accessibility4 }
}

/// *Saved* line 1 on one line: "✓ Saved: Aero 14 · $1,499" shrinks to 70% like the verdict line; past that, the first
/// of `lines` (`Saved.line1Cuts`) that fits at 70% shows, so a long item name is cut and the price never is
/// ("✓ Saved: Noise-Cancelling He… · $299").
private struct SavedLine1: View {
    let lines: [String]
    let size: CGFloat

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(lines, id: \.self) { line in
                // Taken when the line fits at 70%. The text's own floor is lower: SwiftUI cuts a line that should
                // just fit at its floor (seen on iOS 27 up to about 72% for a 70% floor), and this text is only ever
                // offered a width that fits it at 70% or more, so it never gets that far.
                FitsWhenShrunk(scale: 0.7) {
                    Text(line)
                        .font(.system(size: size, weight: .bold))
                        .tracking(-0.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .monospacedDigit()
        // VoiceOver reads the whole name, not the cut.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.first ?? "")
    }
}

/// Reports its content's ideal width at `scale`, so `ViewThatFits` takes text that `minimumScaleFactor` can shrink to
/// fit; any other proposal passes straight through.
private struct FitsWhenShrunk: Layout {
    var scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        guard proposal.width == nil else { return subview.sizeThatFits(proposal) }
        let ideal = subview.sizeThatFits(proposal)
        return CGSize(width: (ideal.width * scale).rounded(.up), height: ideal.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// Wraps an optional record: a pruned or missing check shows §6.3 *Couldn't check*'s line 1 alone (§6.3 has no state
/// for a check that can no longer be read, and its line 2s name a network cause that isn't true here).
struct CheckSnippetView: View {
    let record: CheckRecord?
    let catalog: CardCatalog
    var showsSaveButton = true

    var body: some View {
        if let record {
            CheckResultView(record: record, catalog: catalog, showsSaveButton: showsSaveButton)
        } else {
            MessageSnippetView(line1: "Couldn't check this time", line2: nil, line3: nil, isWarning: true)
        }
    }
}

/// A static snippet of up to three lines (*Not set up*; island states with no Live Activity).
struct MessageSnippetView: View {
    let line1: String
    let line2: String?
    let line3: String?
    let isWarning: Bool

    @ScaledMetric(relativeTo: .title2) private var line1Size: CGFloat = 23
    @ScaledMetric(relativeTo: .callout) private var lineSize: CGFloat = 16
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SnippetHeader(replayed: false)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    if isWarning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    Text(line1)
                        .font(.system(size: line1Size, weight: .bold))
                        .tracking(-0.5)
                }
                if let line2 {
                    Text(line2)
                        .font(.system(size: lineSize, weight: .medium))
                        .tracking(-0.2)
                }
                if let line3, typeSize < .accessibility2 {
                    Text(line3)
                        .font(.system(size: lineSize))
                        .tracking(-0.2)
                        .foregroundStyle(.secondary)
                }
            }
            // Island states shown here can carry money (e.g. a Keep or switch-fallback line 3).
            .monospacedDigit()
            .accessibilityElement(children: .combine)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One spoken label for the result lines (the snippet), or the lines as separate elements (the app).
private struct SpokenLines: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
        } else {
            content.accessibilityElement(children: .contain)
        }
    }
}

/// "Paywise" with the logo (design.md §3 header; the mark from brand/08-monoline).
private struct SnippetHeader: View {
    let replayed: Bool

    var body: some View {
        HStack(spacing: 6) {
            PaywiseMark(size: 16)
                .accessibilityHidden(true)
            Text("Paywise")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if replayed {
                // §15.7 step 10: a replayed result is always labelled.
                Text("replayed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
        }
    }
}

/// design.md §4: 50 pt tall, fully round; primary is white on accent, secondary is label on fill.
struct SnippetButtonStyle: ButtonStyle {
    var prominent: Bool
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 16.5

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size, weight: .semibold))
            .tracking(-0.2)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(prominent ? Color("accent") : Color(.tertiarySystemFill), in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

#if DEBUG
extension CheckRecord {
    /// The demo laptop check, from the bundled replay fixture (fake data), for previews.
    static func preview(view: Screen = .result) -> CheckRecord? {
        DemoChecks.laptopSwitch().flatMap {
            DemoChecks.record(
                $0, wallet: .demo3Card, catalog: .bundled(), ocrText: ScreenReading.laptopCheckout.redactedText,
                view: view, replayed: view == .sent
            )
        }
    }
}

#Preview("Result") {
    CheckSnippetView(record: .preview(view: .result), catalog: .bundled())
}

#Preview("Saved") {
    CheckSnippetView(record: .preview(view: .saved), catalog: .bundled())
}

#Preview("Sent") {
    CheckSnippetView(record: .preview(view: .sent), catalog: .bundled())
}

#Preview("Not set up") {
    MessageSnippetView(
        line1: "Use the Paywise shortcut", line2: "It reads the screen for you",
        line3: "Set it up in the Paywise app", isWarning: false
    )
}
#endif
