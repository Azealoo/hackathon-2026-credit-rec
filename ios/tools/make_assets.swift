// Generates Paywise's visual assets from docs/design.md §5–§7, so they can be rebuilt exactly.
// Run it through ios/tools/make_assets.sh, which also turns the silence written here into silent.caf (afconvert).
//
//   xcrun swift ios/tools/make_assets.swift <repo-root> <silence.wav to write>
//
// Writes (and overwrites):
//   ios/Shared/Assets.xcassets   (app + widget): card-<id>, card-<id>-compact, glyph, accent
//   ios/Paywise/Assets.xcassets  (app only):     AppIcon (standard, dark, tinted)
//
// Card IDs and asset names come from data/cards.json; only the art (design.md §6 gradients) lives here.
// No text, logos, network marks or numbers are drawn on any card.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Arguments

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: make_assets.swift <repo-root> <silence.wav>\n".utf8))
    exit(2)
}
let root = URL(fileURLWithPath: arguments[1], isDirectory: true)
let silenceURL = URL(fileURLWithPath: arguments[2])
let sharedCatalog = root.appending(path: "ios/Shared/Assets.xcassets", directoryHint: .isDirectory)
let appCatalog = root.appending(path: "ios/Paywise/Assets.xcassets", directoryHint: .isDirectory)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make_assets: \(message)\n".utf8))
    exit(1)
}

// MARK: - Sizes (docs/design.md §7, SPEC §6.1)

/// Point sizes of the two card-art slots. Pixels are floored, so no export is ever larger than its slot.
enum Slot {
    /// Compact leading on 393-pt screens: 52.33 × 36.67 pt (157 × 110 px @3x).
    static let compact = CGSize(width: 157.0 / 3, height: 110.0 / 3)
    /// Expanded leading and the snippet: the film's 52 × 32.8 pt (156 × 98 px @3x).
    static let expanded = CGSize(width: 52, height: 32.8)
}

let scales: [Int] = [2, 3]
let cardRatio: CGFloat = 1.586

// MARK: - Card art (docs/design.md §6)

struct CardStyle {
    /// 135° gradient stops: hex color and location.
    var stops: [(String, CGFloat)]
}

/// design.md §6 table. Freedom Rise and Discover are "proposed" there and give no middle location;
/// they use 55%, like Freedom.
let cardStyles: [String: CardStyle] = [
    "chase-freedom-unlimited": CardStyle(stops: [("#3f7ff0", 0), ("#1b4fb8", 0.55), ("#10306f", 1)]),
    "apple-card": CardStyle(stops: [("#fbfbfc", 0), ("#e4e5ea", 0.60), ("#cfd1d8", 1)]),
    "wf-active-cash": CardStyle(stops: [("#ef6a5b", 0), ("#c23a3f", 0.60), ("#8e2232", 1)]),
    "chase-freedom-rise": CardStyle(stops: [("#35b6a8", 0), ("#1a7f86", 0.55), ("#0f4f57", 1)]),
    "discover-it-student-cash-back": CardStyle(stops: [("#f6a54a", 0), ("#e07a2b", 0.55), ("#a84f1a", 1)]),
]

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: String) -> (CGFloat, CGFloat, CGFloat) {
    var digits = hex
    if digits.hasPrefix("#") { digits.removeFirst() }
    guard digits.count == 6, let value = UInt32(digits, radix: 16) else { fail("bad color \(hex)") }
    return (CGFloat((value >> 16) & 0xff) / 255, CGFloat((value >> 8) & 0xff) / 255, CGFloat(value & 0xff) / 255)
}

func color(_ hex: String, _ alpha: CGFloat = 1) -> CGColor {
    let (r, g, b) = rgb(hex)
    return CGColor(colorSpace: sRGB, components: [r, g, b, alpha])!
}

func luminance(_ hex: String) -> CGFloat {
    let (r, g, b) = rgb(hex)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

/// A bitmap with a top-left origin (y down), so the design's CSS-style numbers read directly.
func makeContext(width: Int, height: Int, opaque: Bool) -> CGContext {
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB, bitmapInfo: info
    ) else { fail("no bitmap context \(width)x\(height)") }
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    return context
}

func writePNG(_ context: CGContext, to url: URL) {
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("can't encode \(url.lastPathComponent)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("can't write \(url.path)") }
}

/// CSS `linear-gradient(<angle>deg, …)` over `rect`: 0° points up, 90° right; the end colors meet the corners.
func linearGradient(_ context: CGContext, in rect: CGRect, angle degrees: CGFloat, stops: [(CGColor, CGFloat)]) {
    let theta = degrees * .pi / 180
    let direction = CGPoint(x: sin(theta), y: -cos(theta))
    let length = abs(rect.width * sin(theta)) + abs(rect.height * cos(theta))
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let start = CGPoint(x: center.x - direction.x * length / 2, y: center.y - direction.y * length / 2)
    let end = CGPoint(x: center.x + direction.x * length / 2, y: center.y + direction.y * length / 2)
    let gradient = CGGradient(
        colorsSpace: sRGB, colors: stops.map(\.0) as CFArray, locations: stops.map(\.1)
    )!
    context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// One card per design.md §6, drawn into `card` (pixels) at `scale` px per pt.
func drawCard(_ context: CGContext, in card: CGRect, style: CardStyle, scale: CGFloat) {
    let width = card.width
    let height = card.height
    let isLight = luminance(style.stops[0].0) > 0.8
    let radius = 0.085 * width
    let shape = CGPath(roundedRect: card, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Edge: a 1 px soft shadow rgba(0,0,0,.18). Shadow offsets are in device space (y up), so down is negative.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -0.33 * scale), blur: 0.67 * scale, color: color("#000000", 0.18))
    context.addPath(shape)
    context.setFillColor(color(style.stops[0].0))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    // Body: the card's 135° gradient.
    linearGradient(context, in: card, angle: 135, stops: style.stops.map { (color($0.0), $0.1) })
    // Sheen: a circle 110% of the width, left edge at 35%, top at −55% (of the width), clipped by the card.
    let diameter = 1.1 * width
    context.setFillColor(color("#ffffff", isLight ? 0.6 : 0.13))
    context.fillEllipse(in: CGRect(x: card.minX + 0.35 * width, y: card.minY - 0.55 * width, width: diameter, height: diameter))
    // Chip: 16% × 24%, 11% in, 36% down, radius 3% of the width, gold gradient top to bottom.
    let chip = CGRect(x: card.minX + 0.11 * width, y: card.minY + 0.36 * height, width: 0.16 * width, height: 0.24 * height)
    context.addPath(CGPath(roundedRect: chip, cornerWidth: 0.03 * width, cornerHeight: 0.03 * width, transform: nil))
    context.clip()
    linearGradient(context, in: chip, angle: 180, stops: [(color("#f1d796"), 0), (color("#c9a54f"), 1)])
    context.restoreGState()

    // The light card gets a 0.6 pt rgba(0,0,0,.12) inner stroke so it doesn't vanish on white.
    if isLight {
        let line = 0.6 * scale
        let inner = card.insetBy(dx: line / 2, dy: line / 2)
        context.addPath(CGPath(
            roundedRect: inner, cornerWidth: radius - line / 2, cornerHeight: radius - line / 2, transform: nil
        ))
        context.setStrokeColor(color("#000000", 0.12))
        context.setLineWidth(line)
        context.strokePath()
    }
}

/// The card art at `slot` (pt) and `scale`: the card spans the slot's width (less 0.5 pt a side for the shadow)
/// at the ID-1 ratio, centred; the compact slot is taller than a card, so it is letterboxed (transparent bands).
func cardImage(style: CardStyle, slot: CGSize, scale: Int) -> CGContext {
    let s = CGFloat(scale)
    let width = Int((slot.width * s + 0.001).rounded(.down))
    let height = Int((slot.height * s + 0.001).rounded(.down))
    let context = makeContext(width: width, height: height, opaque: false)
    let cardWidth = CGFloat(width) - s
    let cardHeight = min(cardWidth / cardRatio, CGFloat(height) - 0.25 * s)
    let card = CGRect(
        x: (CGFloat(width) - cardWidth) / 2,
        y: max(0, (CGFloat(height) - cardHeight) / 2 - 0.15 * s),
        width: cardWidth,
        height: cardHeight
    )
    drawCard(context, in: card, style: style, scale: s)
    return context
}

// MARK: - Glyph (docs/design.md §5)

/// The shield outline and the three lines on the 24 × 24 grid, mapped by `transform`.
func glyphPaths(_ transform: CGAffineTransform) -> (shield: CGPath, lines: CGPath) {
    let t = transform
    let shield = CGMutablePath()
    shield.move(to: CGPoint(x: 12, y: 2.6), transform: t)
    shield.addLine(to: CGPoint(x: 19.4, y: 5.4), transform: t)
    shield.addLine(to: CGPoint(x: 19.4, y: 11.3), transform: t)
    shield.addCurve(
        to: CGPoint(x: 12, y: 21.4), control1: CGPoint(x: 19.4, y: 15.8), control2: CGPoint(x: 16.3, y: 19.4), transform: t
    )
    shield.addCurve(
        to: CGPoint(x: 4.6, y: 11.3), control1: CGPoint(x: 7.7, y: 19.4), control2: CGPoint(x: 4.6, y: 15.8), transform: t
    )
    shield.addLine(to: CGPoint(x: 4.6, y: 5.4), transform: t)
    shield.closeSubpath()
    let lines = CGMutablePath()
    for (y, endX) in [(9.4, 15.6), (12.4, 15.6), (15.4, 12.3)] as [(CGFloat, CGFloat)] {
        lines.move(to: CGPoint(x: 8.4, y: y), transform: t)
        lines.addLine(to: CGPoint(x: endX, y: y), transform: t)
    }
    return (shield, lines)
}

/// design.md §5 path, verbatim apart from spelling out the implicit commands. Strokes on each path (not inherited)
/// so the asset compiler's SVG reader sees them.
let glyphSVG = """
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
  <path d="M12 2.6 L19.4 5.4 V11.3 C19.4 15.8 16.3 19.4 12 21.4 C7.7 19.4 4.6 15.8 4.6 11.3 V5.4 L12 2.6 Z" \
fill="none" stroke="#000000" stroke-width="1.9" stroke-linejoin="round" stroke-linecap="round"/>
  <path d="M8.4 9.4 H15.6 M8.4 12.4 H15.6 M8.4 15.4 H12.3" \
fill="none" stroke="#000000" stroke-width="1.9" stroke-linejoin="round" stroke-linecap="round"/>
</svg>

"""

// MARK: - App icon (docs/design.md §5)

enum IconVariant: String, CaseIterable {
    case standard, dark, tinted

    var fileName: String {
        switch self {
        case .standard: "AppIcon.png"
        case .dark: "AppIcon-dark.png"
        case .tinted: "AppIcon-tinted.png"
        }
    }
}

/// 1024 × 1024, opaque, full bleed (the system applies the squircle mask).
func appIcon(_ variant: IconVariant) -> CGContext {
    let side = 1024
    let size = CGFloat(side)
    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    let context = makeContext(width: side, height: side, opaque: true)

    // Background.
    switch variant {
    case .standard:
        // Indigo, #6d7cff (top) to #2a3fd8 (bottom) at 160°.
        linearGradient(context, in: canvas, angle: 160, stops: [(color("#6d7cff"), 0), (color("#2a3fd8"), 1)])
    case .dark:
        // Proposed: near-black with a trace of the indigo, so the coloured shield carries the brand.
        linearGradient(context, in: canvas, angle: 160, stops: [(color("#1a1e3a"), 0), (color("#05060d"), 1)])
    case .tinted:
        // Proposed: grayscale on black, as the system tints it.
        context.setFillColor(color("#000000"))
        context.fill(canvas)
    }

    // A soft white highlight from the top-left: ≈35% white fading out by 60% (of the farthest-corner radius).
    let highlight: CGFloat = switch variant {
    case .standard: 0.35
    case .dark: 0.10
    case .tinted: 0
    }
    if highlight > 0 {
        let radial = CGGradient(
            colorsSpace: sRGB,
            colors: [color("#ffffff", highlight), color("#ffffff", 0)] as CFArray,
            locations: [0, 1]
        )!
        context.drawRadialGradient(
            radial, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 0.6 * size * 2.squareRoot(), options: []
        )
        // Inner top edge light and bottom edge shade, for depth.
        linearGradient(
            context, in: CGRect(x: 0, y: 0, width: size, height: 0.035 * size), angle: 180,
            stops: [(color("#ffffff", highlight * 0.8), 0), (color("#ffffff", 0), 1)]
        )
        linearGradient(
            context, in: CGRect(x: 0, y: 0.95 * size, width: size, height: 0.05 * size), angle: 180,
            stops: [(color("#000000", 0), 0), (color("#000000", 0.16), 1)]
        )
    }

    // The filled shield, ≈62% of the icon's height including the 1.9 stroke, centred.
    let unit = 0.62 * size / (21.4 - 2.6 + 1.9)
    let transform = CGAffineTransform(translationX: size / 2 - 12 * unit, y: size / 2 - 12 * unit).scaledBy(x: unit, y: unit)
    let (shield, lines) = glyphPaths(transform)

    context.saveGState()
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    // Shield body: the outline filled, plus its round-joined stroke so the silhouette matches the glyph.
    let outline = shield.copy(strokingWithWidth: 1.9 * unit, lineCap: .round, lineJoin: .round, miterLimit: 10)
    context.addPath(shield.union(outline))
    context.clip()
    switch variant {
    case .standard:
        context.setFillColor(color("#ffffff"))
        context.fill(canvas)
    case .dark:
        linearGradient(context, in: shield.boundingBox, angle: 160, stops: [(color("#6d7cff"), 0), (color("#2a3fd8"), 1)])
    case .tinted:
        linearGradient(context, in: shield.boundingBox, angle: 180, stops: [(color("#ffffff"), 0), (color("#bdbdbd"), 1)])
    }
    context.resetClip()
    // The three lines of fine print: #2a3fd8 on the standard icon; cut through to the background on the others.
    context.addPath(lines)
    context.setLineWidth(1.9 * unit)
    context.setLineCap(.round)
    if variant == .standard {
        context.setStrokeColor(color("#2a3fd8"))
    } else {
        context.setBlendMode(.clear)
    }
    context.strokePath()
    context.setBlendMode(.normal)
    context.endTransparencyLayer()
    context.restoreGState()
    return context
}

// MARK: - Asset catalog files

func writeJSON(_ object: Any, to url: URL) {
    do {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try (data + Data("\n".utf8)).write(to: url, options: .atomic)
    } catch {
        fail("can't write \(url.path): \(error)")
    }
}

func resetFolder(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
    do {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    } catch {
        fail("can't create \(url.path): \(error)")
    }
}

let catalogInfo: [String: Any] = ["author": "xcode", "version": 1]

func writeImageSet(name: String, in catalog: URL, images: [Int: CGContext]) {
    let folder = catalog.appending(path: "\(name).imageset", directoryHint: .isDirectory)
    resetFolder(folder)
    var entries: [[String: Any]] = []
    for scale in images.keys.sorted() {
        let fileName = "\(name)@\(scale)x.png"
        writePNG(images[scale]!, to: folder.appending(path: fileName))
        entries.append(["filename": fileName, "idiom": "universal", "scale": "\(scale)x"])
    }
    writeJSON(["images": entries, "info": catalogInfo], to: folder.appending(path: "Contents.json"))
}

// MARK: - Run

struct Catalog: Decodable {
    struct Card: Decodable {
        struct Art: Decodable {
            var assetName: String
            var color: String
        }

        var id: String
        var art: Art
    }

    var cards: [Card]
}

let cardsData: Data
do {
    cardsData = try Data(contentsOf: root.appending(path: "data/cards.json"))
} catch {
    fail("can't read data/cards.json: \(error)")
}
let catalog: Catalog
do {
    catalog = try JSONDecoder().decode(Catalog.self, from: cardsData)
} catch {
    fail("can't parse data/cards.json: \(error)")
}

for catalogURL in [sharedCatalog, appCatalog] {
    try? FileManager.default.createDirectory(at: catalogURL, withIntermediateDirectories: true)
    writeJSON(["info": catalogInfo], to: catalogURL.appending(path: "Contents.json"))
}

// Card art: card-<id> (expanded + snippet) and card-<id>-compact.
for card in catalog.cards {
    guard let style = cardStyles[card.id] else { fail("no design.md §6 art for \(card.id)") }
    guard card.art.assetName == "card-\(card.id)" else {
        fail("\(card.id): art.assetName should be card-\(card.id), is \(card.art.assetName)")
    }
    guard card.art.color.lowercased() == style.stops[0].0 else {
        fail("\(card.id): art.color \(card.art.color) doesn't match the gradient's first stop \(style.stops[0].0)")
    }
    var expanded: [Int: CGContext] = [:]
    var compact: [Int: CGContext] = [:]
    for scale in scales {
        expanded[scale] = cardImage(style: style, slot: Slot.expanded, scale: scale)
        compact[scale] = cardImage(style: style, slot: Slot.compact, scale: scale)
    }
    writeImageSet(name: card.art.assetName, in: sharedCatalog, images: expanded)
    writeImageSet(name: "\(card.art.assetName)-compact", in: sharedCatalog, images: compact)
    print("card art: \(card.art.assetName), \(card.art.assetName)-compact")
}

// Glyph: one template vector.
do {
    let folder = sharedCatalog.appending(path: "glyph.imageset", directoryHint: .isDirectory)
    resetFolder(folder)
    try Data(glyphSVG.utf8).write(to: folder.appending(path: "glyph.svg"), options: .atomic)
    writeJSON([
        "images": [["filename": "glyph.svg", "idiom": "universal"]],
        "info": catalogInfo,
        "properties": ["preserves-vector-representation": true, "template-rendering-intent": "template"],
    ], to: folder.appending(path: "Contents.json"))
    print("glyph: template SVG")
} catch {
    fail("can't write the glyph: \(error)")
}

// accent: Any #3f5bf6, Dark #5b74ff (design.md §2).
do {
    let folder = sharedCatalog.appending(path: "accent.colorset", directoryHint: .isDirectory)
    resetFolder(folder)
    func components(_ hex: String) -> [String: Any] {
        let (r, g, b) = rgb(hex)
        func byte(_ v: CGFloat) -> String { String(format: "0x%02X", Int((v * 255).rounded())) }
        return ["color-space": "srgb", "components": ["alpha": "1.000", "red": byte(r), "green": byte(g), "blue": byte(b)]]
    }
    writeJSON([
        "colors": [
            ["color": components("#3f5bf6"), "idiom": "universal"],
            ["appearances": [["appearance": "luminosity", "value": "dark"]], "color": components("#5b74ff"), "idiom": "universal"],
        ],
        "info": catalogInfo,
    ], to: folder.appending(path: "Contents.json"))
    print("accent: #3f5bf6 / dark #5b74ff")
}

// App icon: standard, dark and tinted, 1024 × 1024, no alpha.
do {
    let folder = appCatalog.appending(path: "AppIcon.appiconset", directoryHint: .isDirectory)
    resetFolder(folder)
    var entries: [[String: Any]] = []
    for variant in IconVariant.allCases {
        writePNG(appIcon(variant), to: folder.appending(path: variant.fileName))
        var entry: [String: Any] = ["filename": variant.fileName, "idiom": "universal", "platform": "ios", "size": "1024x1024"]
        if variant != .standard {
            entry["appearances"] = [["appearance": "luminosity", "value": variant.rawValue]]
        }
        entries.append(entry)
    }
    writeJSON(["images": entries, "info": catalogInfo], to: folder.appending(path: "Contents.json"))
    print("app icon: standard, dark, tinted")
}

// Silence for silent.caf: 10 ms of zeros, 16-bit mono 44.1 kHz WAV (afconvert makes the CAF).
do {
    let sampleRate: UInt32 = 44_100
    let samples: UInt32 = 441
    let dataBytes = samples * 2
    var wav = Data()
    func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
    func append(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
    wav.append(contentsOf: Array("RIFF".utf8)); append(36 + dataBytes)
    wav.append(contentsOf: Array("WAVE".utf8))
    wav.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
    append(sampleRate); append(sampleRate * 2); append(UInt16(2)); append(UInt16(16))
    wav.append(contentsOf: Array("data".utf8)); append(dataBytes)
    wav.append(Data(count: Int(dataBytes)))
    do {
        try wav.write(to: silenceURL, options: .atomic)
    } catch {
        fail("can't write \(silenceURL.path): \(error)")
    }
}
