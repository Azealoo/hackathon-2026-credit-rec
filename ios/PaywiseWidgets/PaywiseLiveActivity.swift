import ActivityKit
import SwiftUI
import WidgetKit

/// The Paywise Live Activity (SPEC §6.3, §6.4): *Checking*, then the island results `CheckCheckoutIntent` alerts
/// with (Keep, No checkout, Couldn't check, the switch fallback). The parts live in `Shared/LiveActivityViews.swift`;
/// this file places them. Long lines go in the full-width bottom region (the center region clips ~40-character lines;
/// `IslandExpandedBottom`).
struct PaywiseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PaywiseActivityAttributes.self) { context in
            // Lock Screen: the system material (light or dark with the phone), design.md §1 / §4.
            LockScreenContent(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(nil)
        } dynamicIsland: { context in
            let state = context.state
            let isStale = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandLeadingMark(state: state, isStale: isStale, slot: .expanded)
                        .padding(.leading, 4)
                        .islandAppearance()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandStatusMark(state: state, isStale: isStale, slot: .expanded)
                        .padding(.trailing, 4)
                        .islandAppearance()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedBottom(state: state, isStale: isStale)
                        .islandAppearance()
                }
            } compactLeading: {
                IslandLeadingMark(state: state, isStale: isStale, slot: .compact)
                    .islandAppearance()
            } compactTrailing: {
                IslandStatusMark(state: state, isStale: isStale, slot: .compact)
                    .islandAppearance()
            } minimal: {
                IslandMinimalMark(state: state, isStale: isStale)
                    .islandAppearance()
            }
            .keylineTint(Color("accent"))
        }
    }
}

private extension View {
    /// The island is always black: draw in the dark appearance so `accent` is accentDark (#5b74ff) and labels are light.
    func islandAppearance() -> some View {
        environment(\.colorScheme, .dark)
    }
}

#if DEBUG
/// Sample states for Xcode previews (fake data; the app's copy comes from the backend or `CheckFlow`).
private extension PaywiseActivityAttributes.ContentState {
    static let previewKeep = Self(
        phase: .keep, glyph: .check, cardId: "apple-card", cardShortName: "Apple Card", last4: "5678",
        line1: "✓ Keep Apple Card ••5678", line2: "Best of your 3 cards here",
        lockScreenText: checkedLockScreenText
    )
    static let previewNoCheckout = Self(
        phase: .noCheckout, glyph: .warning,
        line1: "No checkout total found", line2: "Nothing left your phone", line3: "Scroll to the total and press again",
        lockScreenText: checkedLockScreenText
    )
    static let previewCouldntCheck = Self(
        phase: .error, glyph: .warning,
        line1: "Couldn't check this time", line2: "No connection · press again",
        lockScreenText: checkedLockScreenText
    )
    static let previewSwitchFallback = Self(
        phase: .switchFallback, glyph: .card, cardId: "chase-freedom-unlimited", cardShortName: "Freedom",
        last4: "1234", line1: "Use Freedom ••1234", line2: "Adds a warranty year + $500 theft cover",
        line3: "$7.49 less cash back than Active Cash", lockScreenText: checkedLockScreenText
    )
}

private let previewAttributes = PaywiseActivityAttributes(checkId: "preview")

#Preview("Compact", as: .dynamicIsland(.compact), using: previewAttributes) {
    PaywiseLiveActivity()
} contentStates: {
    PaywiseActivityAttributes.ContentState.checking
    PaywiseActivityAttributes.ContentState.previewKeep
    PaywiseActivityAttributes.ContentState.previewSwitchFallback
    PaywiseActivityAttributes.ContentState.previewCouldntCheck
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: previewAttributes) {
    PaywiseLiveActivity()
} contentStates: {
    PaywiseActivityAttributes.ContentState.checking
    PaywiseActivityAttributes.ContentState.previewKeep
    PaywiseActivityAttributes.ContentState.previewNoCheckout
    PaywiseActivityAttributes.ContentState.previewCouldntCheck
    PaywiseActivityAttributes.ContentState.previewSwitchFallback
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: previewAttributes) {
    PaywiseLiveActivity()
} contentStates: {
    PaywiseActivityAttributes.ContentState.checking
    PaywiseActivityAttributes.ContentState.previewKeep
    PaywiseActivityAttributes.ContentState.previewNoCheckout
}

#Preview("Lock Screen", as: .content, using: previewAttributes) {
    PaywiseLiveActivity()
} contentStates: {
    PaywiseActivityAttributes.ContentState.checking
    PaywiseActivityAttributes.ContentState.previewKeep
}
#endif
