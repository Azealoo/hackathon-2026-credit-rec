import SwiftUI
import UIKit

/// The bundled card art (docs/design.md §6–§7), made by `ios/tools/make_assets.sh` into `Shared/Assets.xcassets`,
/// so the app and the widget extension both have it. Named after the card's `id` in `data/cards.json`
/// (its `art.assetName` is `card-<id>`).
enum CardArt {
    /// The expanded island slot and the snippet (the film's 52 × 32.8 pt; 156 × 98 px @3x).
    static let expandedSize = CGSize(width: 52, height: 32.8)
    /// The compact island slot on 393-pt screens (52.33 × 36.67 pt; 157 × 110 px @3x). The card is letterboxed.
    static let compactSize = CGSize(width: 157.0 / 3, height: 110.0 / 3)

    /// `card-<id>` (expanded and snippet) or `card-<id>-compact`.
    static func assetName(cardId: String, compact: Bool = false) -> String {
        "card-\(cardId)" + (compact ? "-compact" : "")
    }

    static func hasImage(named name: String, in bundle: Bundle = .main) -> Bool {
        UIImage(named: name, in: bundle, with: nil) != nil
    }
}

/// One card's art at `CardArt`'s sizes: the bundled image, or the drawn construction for a card without one.
struct CardArtImage: View {
    let cardId: String
    var compact = false

    var body: some View {
        let name = CardArt.assetName(cardId: cardId, compact: compact)
        if CardArt.hasImage(named: name) {
            Image(name)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            CardArtView(assetName: nil, colorHex: nil)
        }
    }
}

/// The Paywise glyph (design.md §5), the template vector asset `glyph`, in the accent color
/// (`accentDark` wherever the environment is dark, e.g. the island).
struct PaywiseGlyphMark: View {
    var size: CGFloat

    var body: some View {
        Image("glyph")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(Color("accent"))
            .accessibilityLabel("Paywise")
    }
}

/// Generic card art (docs/design.md §6): uses the team-made image asset `assetName` when it is in the bundle,
/// otherwise draws the shared construction from the card's base color in `data/cards.json` (`art.color`).
/// No text, logos or numbers on the art; the name and last 4 sit beside it in live text.
struct CardArtView: View {
    let assetName: String?
    let colorHex: String?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let assetName, CardArt.hasImage(named: assetName) {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
            } else {
                // A card with no art and no `art.color` (e.g. an unknown cardId) is drawn in a system grey
                // (design.md §2: no new greys).
                ConstructedCardArt(base: RGB(hex: colorHex) ?? RGB(.systemGray3, colorScheme: colorScheme))
            }
        }
        .aspectRatio(1.586, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// design.md §6: ID-1 ratio, 8.5% corner radius, a soft sheen circle clipped by the card, a small gold chip.
private struct ConstructedCardArt: View {
    let base: RGB

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let shape = RoundedRectangle(cornerRadius: width * 0.085, style: .continuous)
            ZStack(alignment: .topLeading) {
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: base.color, location: 0),
                            .init(color: base.scaled(base.isLight ? 0.91 : 0.6).color, location: base.isLight ? 0.6 : 0.55),
                            .init(color: base.scaled(base.isLight ? 0.83 : 0.36).color, location: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                Circle()
                    .fill(Color.white.opacity(base.isLight ? 0.6 : 0.13))
                    .frame(width: width * 1.1, height: width * 1.1)
                    .offset(x: width * 0.35, y: -width * 0.55)
                RoundedRectangle(cornerRadius: width * 0.03, style: .continuous)
                    .fill(LinearGradient(
                        colors: [RGB(hex: "#f1d796")!.color, RGB(hex: "#c9a54f")!.color],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: width * 0.16, height: height * 0.24)
                    .offset(x: width * 0.11, y: height * 0.36)
            }
            .frame(width: width, height: height)
            .clipShape(shape)
            .overlay {
                if base.isLight {
                    shape.strokeBorder(Color.black.opacity(0.12), lineWidth: 0.6)
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 0.5, y: 0.5)
        }
    }
}

/// A color parsed from a "#rrggbb" string.
struct RGB: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// A system color resolved for `colorScheme`, so the card construction can shade it.
    init(_ color: UIColor, colorScheme: ColorScheme) {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(red: Double(red), green: Double(green), blue: Double(blue))
    }

    init?(hex: String?) {
        guard var hex else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        red = Double((value >> 16) & 0xff) / 255
        green = Double((value >> 8) & 0xff) / 255
        blue = Double(value & 0xff) / 255
    }

    var color: Color { Color(red: red, green: green, blue: blue) }

    /// Relative luminance above which the card counts as "light" (the Apple Card shape in design.md §6).
    var isLight: Bool { 0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.8 }

    func scaled(_ factor: Double) -> RGB {
        RGB(red: red * factor, green: green * factor, blue: blue * factor)
    }
}
