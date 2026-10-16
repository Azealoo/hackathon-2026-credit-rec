import AVFoundation
import Foundation
import ImageIO
import Testing
import UIKit
@testable import Paywise

/// The bundled visual assets (docs/design.md §5–§7, SPEC §6.4), made by ios/tools/make_assets.sh. No snapshots:
/// sizes, presence in both bundles, and a few properties read back from the compiled assets.
struct AssetTests {
    static let widgetBundle: Bundle? = Bundle.main.builtInPlugInsURL.flatMap {
        Bundle(url: $0.appending(path: "PaywiseWidgets.appex"))
    }

    /// The app and the widget extension: both draw card art, the glyph and `accent`, and both carry silent.caf.
    static var bundles: [(name: String, bundle: Bundle)] {
        [("app", Bundle.main)] + (widgetBundle.map { [("widget", $0)] } ?? [])
    }

    /// `ios/` in the source checkout (the simulator can read it; a device can't, so those tests turn off).
    static let iosFolder = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    static let sourceReachable = FileManager.default.fileExists(
        atPath: iosFolder.appending(path: "Shared/Assets.xcassets/Contents.json").path
    )

    /// Pixels a slot allows at a scale, rounded down: no export may be larger than its slot (§6.4).
    static func maxPixels(_ slot: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        (Int((slot.width * scale + 0.001).rounded(.down)), Int((slot.height * scale + 0.001).rounded(.down)))
    }

    @Test func widgetExtensionIsEmbedded() {
        #expect(Self.widgetBundle != nil)
    }

    @Test func slotSizesMatchTheDesign() {
        #expect(Self.maxPixels(CardArt.compactSize, scale: 3) == (157, 110))
        #expect(Self.maxPixels(CardArt.expandedSize, scale: 3) == (156, 98))
        #expect(Self.maxPixels(CardArt.compactSize, scale: 2) == (104, 73))
        #expect(Self.maxPixels(CardArt.expandedSize, scale: 2) == (104, 65))
    }

    /// Every card's art, read with UIImage from the app and the widget bundles: size × scale within the slot, and
    /// exactly the slot @3x (compact 157 × 110, expanded and snippet 156 × 98).
    @Test(arguments: [false, true])
    func compiledCardArtFitsItsSlot(compact: Bool) throws {
        let catalog = CardCatalog.bundled()
        #expect(catalog.cards.count == 5)
        let slot = compact ? CardArt.compactSize : CardArt.expandedSize
        for (label, bundle) in Self.bundles {
            for card in catalog.cards {
                // cards.json `art.assetName` is the expanded asset; the compact one adds "-compact".
                #expect(card.art?.assetName == CardArt.assetName(cardId: card.id))
                let name = CardArt.assetName(cardId: card.id, compact: compact)
                for requested in [2.0, 3.0] as [CGFloat] {
                    let traits = UITraitCollection(displayScale: requested)
                    let image = try #require(
                        UIImage(named: name, in: bundle, compatibleWith: traits), "\(name) missing from the \(label) bundle"
                    )
                    let width = Int((image.size.width * image.scale).rounded())
                    let height = Int((image.size.height * image.scale).rounded())
                    let limit = Self.maxPixels(slot, scale: image.scale)
                    #expect(
                        width <= limit.width && height <= limit.height,
                        "\(label) \(name) @\(image.scale)x is \(width)×\(height), over \(limit.width)×\(limit.height)"
                    )
                    if image.scale == 3 {
                        #expect(width == limit.width && height == limit.height, "\(label) \(name) @3x is \(width)×\(height)")
                    }
                }
            }
        }
    }

    /// The committed PNGs, both scales (a simulator build only carries the @3x ones).
    @Test(.enabled(if: sourceReachable))
    func committedCardArtFitsItsSlot() throws {
        let catalogFolder = Self.iosFolder.appending(path: "Shared/Assets.xcassets")
        let files = try FileManager.default.subpathsOfDirectory(atPath: catalogFolder.path)
            .filter { $0.hasSuffix(".png") && $0.contains("card-") }
        #expect(files.count == 5 * 2 * 2)
        for file in files {
            let scale: CGFloat = file.hasSuffix("@3x.png") ? 3 : file.hasSuffix("@2x.png") ? 2 : 1
            let limit = Self.maxPixels(file.contains("-compact") ? CardArt.compactSize : CardArt.expandedSize, scale: scale)
            let size = try Self.pixelSize(catalogFolder.appending(path: file))
            #expect(size.width <= limit.width && size.height <= limit.height, "\(file) is \(size), over \(limit)")
        }
    }

    /// design.md §5: the glyph is the island mark, a vector in its own colors (not a template), in both bundles. Drawn
    /// at the island's 22 pt @3x: the drawn card opaque in accentDark (#5b74ff) and the two cards behind it in paper
    /// (#f5f5f7) at 62% when dark; accent (#3f5bf6) and ink (#1d1d1f) at 62% when light (the Lock Screen in light).
    @Test func glyphIsTheIslandMarkInBothAppearances() throws {
        for (label, bundle) in Self.bundles {
            for (style, card, stack) in [
                (UIUserInterfaceStyle.dark, [0x5b, 0x74, 0xff], [0xf5, 0xf5, 0xf7]),
                (.light, [0x3f, 0x5b, 0xf6], [0x1d, 0x1d, 0x1f]),
            ] {
                let traits = UITraitCollection(userInterfaceStyle: style)
                let image = try #require(
                    UIImage(named: "glyph", in: bundle, compatibleWith: traits), "glyph missing from \(label)"
                )
                #expect(image.renderingMode != .alwaysTemplate, "\(label) glyph is a template")
                #expect(image.size == CGSize(width: 24, height: 24))
                let format = UIGraphicsImageRendererFormat()
                format.scale = 3
                format.preferredRange = .standard
                let side: CGFloat = 22
                let drawn = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
                    image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
                }
                let pixels = try Self.rgba(#require(drawn.cgImage))
                func near(_ pixel: Pixel, _ rgb: [Int], alpha: ClosedRange<Int>) -> Bool {
                    alpha.contains(pixel.alpha) && zip([pixel.red, pixel.green, pixel.blue], rgb).allSatisfy { abs($0 - $1) <= 4 }
                }
                // About 685 and 590 of the 66 × 66 pixels (CoreSVG on macOS); the rest are edges and empty.
                #expect(pixels.count { near($0, card, alpha: 255...255) } > 400, "\(label) \(style.rawValue): no drawn card")
                #expect(pixels.count { near($0, stack, alpha: 150...165) } > 300, "\(label) \(style.rawValue): no stack at 62%")
            }
        }
    }

    /// design.md §2: `accent` is #3f5bf6, #5b74ff in the dark appearance, in both bundles.
    @Test func accentColorHasBothAppearances() throws {
        for (label, bundle) in Self.bundles {
            let accent = try #require(UIColor(named: "accent", in: bundle, compatibleWith: nil), "accent missing from \(label)")
            #expect(Self.bytes(accent.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))) == [0x3f, 0x5b, 0xf6])
            #expect(Self.bytes(accent.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))) == [0x5b, 0x74, 0xff])
        }
    }

    /// design.md §7: a few ms of true silence, linear PCM, mono, 44.1 kHz, in the app and the widget bundle.
    @Test func silentSoundIsSilentLinearPCMInBothBundles() throws {
        for (label, bundle) in Self.bundles {
            let url = try #require(bundle.url(forResource: "silent", withExtension: "caf"), "silent.caf missing from \(label)")
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: false)
            let format = file.fileFormat
            #expect(format.streamDescription.pointee.mFormatID == kAudioFormatLinearPCM)
            #expect(format.channelCount == 1)
            #expect(format.sampleRate == 44_100)
            let seconds = Double(file.length) / format.sampleRate
            #expect(seconds > 0 && seconds <= 0.05, "\(label) silent.caf is \(seconds) s")
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let channel = try #require(buffer.int16ChannelData?[0])
            let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            #expect(!samples.isEmpty && samples.allSatisfy { $0 == 0 })
        }
    }

    @Test func appIconIsSet() throws {
        let icons = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        let primary = try #require(icons["CFBundlePrimaryIcon"] as? [String: Any])
        #expect(primary["CFBundleIconName"] as? String == "AppIcon")
    }

    static let appIconFolder = iosFolder.appending(path: "Paywise/Assets.xcassets/AppIcon.appiconset")

    /// Logo 08 "Monoline": the set lists standard, dark and tinted, each a 1024 × 1024 iOS icon.
    @Test(.enabled(if: sourceReachable))
    func appIconSetHasStandardDarkAndTinted() throws {
        let contents = try Self.json(Self.appIconFolder.appending(path: "Contents.json"))
        let images = try #require(contents["images"] as? [[String: Any]])
        var byAppearance: [String: String] = [:]
        for image in images {
            #expect(image["size"] as? String == "1024x1024")
            #expect(image["platform"] as? String == "ios")
            let appearance = (image["appearances"] as? [[String: String]])?.first
            if let appearance { #expect(appearance["appearance"] == "luminosity") }
            byAppearance[appearance?["value"] ?? "standard"] = image["filename"] as? String
        }
        #expect(byAppearance == ["standard": "AppIcon.png", "dark": "AppIcon-dark.png", "tinted": "AppIcon-tinted.png"])
    }

    /// The standard icon is the opaque 1024 PNG (the system applies the mask): no alpha channel at all.
    @Test(.enabled(if: sourceReachable))
    func standardAppIconIsOpaque1024() throws {
        let image = try Self.cgImage(Self.appIconFolder.appending(path: "AppIcon.png"))
        #expect((image.width, image.height) == (1024, 1024))
        #expect(
            [.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo),
            "AppIcon.png has an alpha channel (\(image.alphaInfo.rawValue))"
        )
    }

    /// Dark and tinted are the logo's lines on transparent (the system draws the backdrop): 1024 × 1024 with an alpha
    /// channel, transparent corners and background, and the lines opaque.
    @Test(.enabled(if: sourceReachable), arguments: ["AppIcon-dark.png", "AppIcon-tinted.png"])
    func darkAndTintedAppIconsAreLinesOnTransparent(name: String) throws {
        let image = try Self.cgImage(Self.appIconFolder.appending(path: name))
        #expect((image.width, image.height) == (1024, 1024))
        #expect(![.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo), "\(name) has no alpha channel")
        let pixels = try Self.rgba(image)
        for (x, y) in [(0, 0), (1023, 0), (0, 1023), (1023, 1023), (512, 512)] {
            #expect(pixels.alpha(x, y) == 0, "\(name) is not transparent at \(x),\(y)")
        }
        let coverage = Double(pixels.count { $0.alpha > 250 }) / Double(1024 * 1024)
        #expect(coverage > 0.05 && coverage < 0.3, "\(name): lines cover \(coverage)")
    }

    /// Tinted is grayscale (the system tints it by luminance) with the drawn card white; dark draws the stack in paper
    /// and the drawn card in accentDark (#5b74ff), mark-dark.svg's colors.
    @Test(.enabled(if: sourceReachable))
    func darkAndTintedAppIconColors() throws {
        let tinted = try Self.rgba(Self.cgImage(Self.appIconFolder.appending(path: "AppIcon-tinted.png")))
        #expect(tinted.count { $0.alpha > 0 && (abs($0.red - $0.green) > 1 || abs($0.green - $0.blue) > 1) } == 0)
        #expect(tinted.count { $0.alpha == 255 && $0.red == 255 } > 10_000, "tinted has no white card")
        #expect(tinted.count { $0.alpha == 255 && (150...165).contains($0.red) } > 10_000, "tinted has no grey stack")

        let dark = try Self.rgba(Self.cgImage(Self.appIconFolder.appending(path: "AppIcon-dark.png")))
        #expect(dark.count { $0.alpha == 255 && [$0.red, $0.green, $0.blue] == [0x5b, 0x74, 0xff] } > 10_000)
        #expect(dark.count { $0.alpha == 255 && [$0.red, $0.green, $0.blue] == [0xf5, 0xf5, 0xf7] } > 10_000)
    }

    /// The logo for app screens (`mark`: mark.svg, mark-dark.svg) and the Live Activity's glyph (`glyph`: the island
    /// mark, glyph.svg, glyph-dark.svg): each one vector image set in its own colors, an SVG for Any and one for Dark.
    @Test(.enabled(if: sourceReachable), arguments: ["Paywise/Assets.xcassets/mark", "Shared/Assets.xcassets/glyph"])
    func vectorImageSetHasAnyAndDark(_ path: String) throws {
        let name = URL(filePath: path).lastPathComponent
        let folder = Self.iosFolder.appending(path: "\(path).imageset")
        let contents = try Self.json(folder.appending(path: "Contents.json"))
        let images = try #require(contents["images"] as? [[String: Any]])
        #expect(images.count == 2)
        let any = images.filter { $0["appearances"] == nil }
        let dark = images.filter {
            ($0["appearances"] as? [[String: String]]) == [["appearance": "luminosity", "value": "dark"]]
        }
        #expect(any.map { $0["filename"] as? String } == ["\(name).svg"])
        #expect(dark.map { $0["filename"] as? String } == ["\(name)-dark.svg"])
        let properties = try #require(contents["properties"] as? [String: Any])
        #expect(properties["preserves-vector-representation"] as? Bool == true)
        #expect(properties["template-rendering-intent"] as? String == "original")
        for file in ["\(name).svg", "\(name)-dark.svg"] {
            #expect(FileManager.default.fileExists(atPath: folder.appending(path: file).path), "\(file) missing")
        }
    }

    /// The compiled `mark` draws in both appearances: ink and accent (#3f5bf6) lines on light, paper and accentDark
    /// (#5b74ff) lines on dark.
    @Test func compiledMarkDrawsBothAppearances() throws {
        for (style, stack, card) in [
            (UIUserInterfaceStyle.light, [0x1d, 0x1d, 0x1f], [0x3f, 0x5b, 0xf6]),
            (.dark, [0xf5, 0xf5, 0xf7], [0x5b, 0x74, 0xff]),
        ] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let image = try #require(UIImage(named: "mark", in: .main, compatibleWith: traits), "mark missing (\(style))")
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.preferredRange = .standard
            let side: CGFloat = 512
            let drawn = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
                image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
            }
            let pixels = try Self.rgba(#require(drawn.cgImage))
            func near(_ pixel: Pixel, _ rgb: [Int]) -> Bool {
                pixel.alpha == 255 && zip([pixel.red, pixel.green, pixel.blue], rgb).allSatisfy { abs($0 - $1) <= 3 }
            }
            #expect(pixels.count { near($0, stack) } > 2_000, "\(style.rawValue): no stack lines")
            #expect(pixels.count { near($0, card) } > 2_000, "\(style.rawValue): no drawn card")
        }
    }

    // MARK: Helpers

    struct Pixel {
        var red: Int
        var green: Int
        var blue: Int
        var alpha: Int
    }

    /// Unpremultiplied sRGB pixels, top row first.
    struct Pixels {
        let width: Int
        let bytes: [UInt8]

        func pixel(_ x: Int, _ y: Int) -> Pixel {
            let i = (y * width + x) * 4
            let alpha = Int(bytes[i + 3])
            func channel(_ value: UInt8) -> Int {
                alpha == 0 ? 0 : min(255, Int((Double(value) * 255 / Double(alpha)).rounded()))
            }
            return Pixel(red: channel(bytes[i]), green: channel(bytes[i + 1]), blue: channel(bytes[i + 2]), alpha: alpha)
        }

        func alpha(_ x: Int, _ y: Int) -> Int { Int(bytes[(y * width + x) * 4 + 3]) }

        func count(where predicate: (Pixel) -> Bool) -> Int {
            var total = 0
            for index in 0..<(bytes.count / 4) where predicate(pixel(index % width, index / width)) {
                total += 1
            }
            return total
        }
    }

    static func rgba(_ image: CGImage) throws -> Pixels {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn)
        return Pixels(width: width, bytes: bytes)
    }

    static func cgImage(_ url: URL) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "can't read \(url.lastPathComponent)")
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    static func json(_ url: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    static func pixelSize(_ url: URL) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (
            try #require(properties[kCGImagePropertyPixelWidth] as? Int),
            try #require(properties[kCGImagePropertyPixelHeight] as? Int)
        )
    }

    static func bytes(_ color: UIColor) -> [Int] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue].map { Int(($0 * 255).rounded()) }
    }
}
