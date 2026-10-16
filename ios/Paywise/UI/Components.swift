import SwiftUI

/// App-screen parts in docs/design.md's tokens: §2 colors (the `accent` asset, iOS system greys only), §3 type,
/// §4 shapes (50 pt round buttons, 22–26 pt grouped cards, 38 pt chips).

extension Font {
    /// A design.md §3 size as the nearest Dynamic Type style, so app screens scale with the user's text size
    /// (design.md: "prefer Dynamic Type styles near these over fixed sizes; the table is the visual target").
    static func app(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let style: Font.TextStyle = switch size {
        case 30...: .largeTitle
        case 26..<30: .title
        case 21..<26: .title2
        case 19..<21: .title3
        case 17..<19: .body
        case 16..<17: .callout
        case 14..<16: .subheadline
        case 13..<14: .footnote
        default: .caption
        }
        return .system(style, weight: weight)
    }
}

/// design.md §4: 50 pt tall, fully round. Primary is white on `accent`; secondary is label on the system fill.
struct AppButtonStyle: ButtonStyle {
    var prominent = true
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 17
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(prominent ? Color("accent") : Color(.tertiarySystemFill), in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(Capsule())
    }
}

/// design.md §4 chips: 38 pt pill; selected = the accent fill (accentDark on dark), white text, a check at the left.
/// The check mark (and the "Selected" trait) means color is never the only cue.
struct ChipButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.app(13, .bold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.app(15, .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(isSelected ? Color("accent") : Color(.tertiarySystemFill), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A grouped card (design.md §4: 22–26 pt radius) on the grouped background.
struct GroupedCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// A flowing row of chips that wraps onto the next line.
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// One card's art at the expanded/snippet size (52 × 32.8 pt, design.md §7), never larger.
struct CardThumb: View {
    let cardId: String?
    var catalog: CardCatalog

    var body: some View {
        let card = catalog.card(cardId)
        CardArtView(assetName: card?.art?.assetName, colorHex: card?.art?.color)
            .frame(width: CardArt.expandedSize.width, height: CardArt.expandedSize.height)
    }
}

/// The *Couldn't check* lines (§6.3) inside an app screen, with a ⚠ so color is never the only cue.
struct CouldntCheckView: View {
    let line2: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(CheckFlow.couldntCheck)
                    .font(.headline)
                Text(line2)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
