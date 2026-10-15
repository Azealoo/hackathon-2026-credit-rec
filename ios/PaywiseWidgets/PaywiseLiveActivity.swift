import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity views (SPEC §6.3, §6.4). Skeleton: renders whatever lines the state carries,
/// which today is only the *Checking* state started from the app's debug button.
struct PaywiseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PaywiseActivityAttributes.self) { context in
            LockScreenView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    GlyphView(glyph: context.state.glyph, isStale: context.isStale)
                        .font(.title2)
                }
                // Lines go in the full-width bottom region; the center region is too narrow for a 44-char line 2.
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.isStale {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.line1)
                                .font(.headline)
                                .lineLimit(1)
                            if let line2 = context.state.line2 {
                                Text(line2)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Keeps the first letters clear of the island's rounded bottom corners.
                        .padding(.horizontal, 8)
                    }
                }
            } compactLeading: {
                GlyphView(glyph: context.state.glyph, isStale: context.isStale)
            } compactTrailing: {
                if context.state.phase == .checking && !context.isStale {
                    Image(systemName: "ellipsis")
                        .accessibilityLabel("Checking")
                }
            } minimal: {
                GlyphView(glyph: context.state.glyph, isStale: context.isStale)
            }
        }
    }
}

/// Lock Screen: "Paywise is checking" / "Paywise checked this screen"; no card, amount or store.
/// Content is hidden in Always-On, and a stale activity shows the bare glyph.
private struct LockScreenView: View {
    let state: PaywiseActivityAttributes.ContentState
    let isStale: Bool
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        HStack(spacing: 12) {
            GlyphView(glyph: state.glyph, isStale: isStale)
                .font(.title2)
            if !isStale && !isLuminanceReduced {
                Text(state.lockScreenText)
                    .font(.headline)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }
}

private struct GlyphView: View {
    let glyph: PaywiseActivityAttributes.ContentState.Glyph
    let isStale: Bool

    var body: some View {
        Image(systemName: (isStale ? .app : glyph).systemImage)
            .accessibilityLabel("Paywise")
    }
}

#Preview("Island compact", as: .dynamicIsland(.compact), using: PaywiseActivityAttributes(checkId: "preview")) {
    PaywiseLiveActivity()
} contentStates: {
    PaywiseActivityAttributes.ContentState.checking
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: PaywiseActivityAttributes(checkId: "preview")) {
    PaywiseLiveActivity()
} contentStates: {
    PaywiseActivityAttributes.ContentState.checking
}

#Preview("Lock Screen", as: .content, using: PaywiseActivityAttributes(checkId: "preview")) {
    PaywiseLiveActivity()
} contentStates: {
    PaywiseActivityAttributes.ContentState.checking
}
