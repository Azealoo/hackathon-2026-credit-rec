import SwiftUI

/// The pieces of the Paywise Live Activity (SPEC §6.3, §6.4; docs/design.md §3–§5). `PaywiseWidgets` arranges them
/// into the Dynamic Island and Lock Screen; they live in Shared so the app can draw the same pieces (debug gallery).
///
/// | Phase | Leading | Trailing | Minimal | Expanded bottom |
/// |---|---|---|---|---|
/// | checking | glyph | progress ring | glyph | lines 1–2 |
/// | keep | card art | ✓ | ✓ | lines 1–2 |
/// | switch_fallback | card art | ••last4 (compact) / glyph (expanded) | card art | lines 1–3 |
/// | no_checkout, error | glyph | ⚠ | ⚠ | lines 1–3 |
/// | stale (any) | glyph | — | glyph | — (`IslandExpandedBottom`) |
///
/// The island is always black, so its parts draw in the dark appearance (`accent` resolves to accentDark #5b74ff).
typealias ActivityState = PaywiseActivityAttributes.ContentState

enum IslandSlot {
    case compact
    case expanded
    case minimal
}

/// Leading: the card's art when the state names a card (Keep, the switch fallback), else the Paywise glyph.
struct IslandLeadingMark: View {
    let state: ActivityState
    let isStale: Bool
    let slot: IslandSlot

    var body: some View {
        if !isStale, let cardId = state.cardId {
            switch slot {
            case .expanded:
                CardArtImage(cardId: cardId)
                    .frame(width: CardArt.expandedSize.width, height: CardArt.expandedSize.height)
            case .compact, .minimal:
                CardArtImage(cardId: cardId, compact: true)
                    .frame(maxWidth: CardArt.compactSize.width, maxHeight: CardArt.compactSize.height)
            }
        } else {
            PaywiseGlyphMark(size: slot == .expanded ? 30 : 22)
        }
    }
}

/// Trailing: what happened. The ring while checking, ✓ for Keep, ⚠ for No checkout and Couldn't check, the last 4
/// for the switch fallback (compact). Color is never the only cue: each mark has its own shape.
struct IslandStatusMark: View {
    let state: ActivityState
    let isStale: Bool
    let slot: IslandSlot

    var body: some View {
        if !isStale {
            switch state.glyph {
            case .paywise:
                if state.phase == .checking {
                    CheckingRing(size: 22)
                }
            case .check:
                KeepMark(size: slot == .expanded ? 26 : 22)
            case .warning:
                WarningMark(size: slot == .expanded ? 26 : 22)
            case .card:
                if slot == .compact, let last4 = state.last4 {
                    Text("••\(last4)")
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityLabel("Card ending \(last4.map(String.init).joined(separator: " "))")
                } else {
                    PaywiseGlyphMark(size: 22)
                }
            }
        }
    }
}

/// Minimal (another app's Live Activity is running; also the 28-pt circle): the glyph while checking, ✓ for Keep,
/// ⚠ for errors (§6.4); the card's art for the switch fallback; the bare glyph when stale.
struct IslandMinimalMark: View {
    let state: ActivityState
    let isStale: Bool

    var body: some View {
        if isStale {
            PaywiseGlyphMark(size: 22)
        } else {
            switch state.glyph {
            case .paywise: PaywiseGlyphMark(size: 22)
            case .check: KeepMark(size: 22)
            case .warning: WarningMark(size: 22)
            case .card: IslandLeadingMark(state: state, isStale: false, slot: .minimal)
            }
        }
    }
}

/// ✓ in green (design.md §2: covered / Keep).
struct KeepMark: View {
    var size: CGFloat

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.black, .green)
            .accessibilityLabel("Keep")
    }
}

/// ⚠ in yellow (design.md §2 notice color on dark).
struct WarningMark: View {
    var size: CGFloat

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.black, .yellow)
            .accessibilityLabel("Warning")
    }
}

/// design.md §5 progress ring: 22 pt, accentDark arc on a faint track. A Live Activity can't run its own repeating
/// animation, so the system draws it from a timer: the arc fills over the check's deadline (6.0 s request plus
/// on-device reading) from the moment the state is drawn.
struct CheckingRing: View {
    var size: CGFloat = 22
    static let duration: TimeInterval = 7

    var body: some View {
        let start = Date.now
        ProgressView(timerInterval: start...start.addingTimeInterval(Self.duration), countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.circular)
        .tint(Color("accent"))
        .frame(width: size, height: size)
        .accessibilityLabel("Checking")
    }
}

/// Lines 1–3 for the expanded island, at design.md §3 sizes (23 bold / 16 medium / 16 regular secondary).
/// Lines are capped at one line each and shrink a little before they clip; Dynamic Type drops line 3 first (§6.4).
/// The island is a fixed height, so text grows with Dynamic Type only up to xxLarge.
struct IslandLines: View {
    let state: ActivityState

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // The cap sits outside the view that scales, so its @ScaledMetric sizes see the capped size.
        Content(state: state, showsLine3: typeSize < .xLarge)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SpokenCopy.label(lines: [state.line1, state.line2, state.line3]))
    }

    private struct Content: View {
        let state: ActivityState
        let showsLine3: Bool

        @ScaledMetric(relativeTo: .title2) private var line1Size: CGFloat = 23
        @ScaledMetric(relativeTo: .callout) private var lineSize: CGFloat = 16

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.line1)
                    .font(.system(size: line1Size, weight: .bold))
                    .tracking(-0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let line2 = state.line2 {
                    Text(line2)
                        .font(.system(size: lineSize, weight: .medium))
                        .tracking(-0.2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                if showsLine3, let line3 = state.line3 {
                    Text(line3)
                        .font(.system(size: lineSize))
                        .tracking(-0.2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The expanded island's full-width bottom region: lines 1–3, 8 pt in from each side so the first letters clear the
/// island's rounded corners. Nothing when stale (the leading glyph alone remains).
struct IslandExpandedBottom: View {
    let state: ActivityState
    let isStale: Bool

    var body: some View {
        if !isStale {
            IslandLines(state: state)
                .padding(.horizontal, 8)
                .padding(.top, 2)
        }
    }
}

/// Lock Screen (and the banner on phones without a Dynamic Island): "Paywise is checking" / "Paywise checked this
/// screen". No card, no amount, no store (§6.4). Always-On (`isLuminanceReduced`) and stale show the glyph only.
struct LockScreenContent: View {
    let state: ActivityState
    let isStale: Bool

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        HStack(spacing: 12) {
            PaywiseGlyphMark(size: 28)
            if !isStale && !isLuminanceReduced {
                Text(state.lockScreenText)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if state.phase == .checking {
                    CheckingRing(size: 22)
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
}
