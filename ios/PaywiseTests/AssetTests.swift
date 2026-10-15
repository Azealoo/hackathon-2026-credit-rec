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

    /// design.md §5: one template vector, drawn by both bundles.
    @Test func glyphIsATemplateVectorThatDraws() throws {
        for (label, bundle) in Self.bundles {
            let image = try #require(UIImage(named: "glyph", in: bundle, with: nil), "glyph missing from \(label)")
            #expect(image.renderingMode == .alwaysTemplate)
            #expect(image.size == CGSize(width: 24, height: 24))
            // The SVG's strokes survived the asset compiler: drawn at 24 pt it covers part of the square, not none.
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            let drawn = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
                image.withTintColor(.black).draw(in: CGRect(origin: .zero, size: image.size))
            }
            let coverage = try Self.opaqueFraction(#require(drawn.cgImage))
            #expect(coverage > 0.15 && coverage < 0.6, "\(label) glyph covers \(coverage)")
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

    /// design.md §7: 1024 × 1024, standard + dark + tinted, no transparency.
    @Test(.enabled(if: sourceReachable))
    func appIconSourcesAreOpaque1024() throws {
        let folder = Self.iosFolder.appending(path: "Paywise/Assets.xcassets/AppIcon.appiconset")
        for name in ["AppIcon.png", "AppIcon-dark.png", "AppIcon-tinted.png"] {
            let url = folder.appending(path: name)
            #expect(try Self.pixelSize(url) == (1024, 1024))
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(
                [.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo),
                "\(name) has an alpha channel (\(image.alphaInfo.rawValue))"
            )
        }
    }

    // MARK: Helpers

    static func pixelSize(_ url: URL) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (
            try #require(properties[kCGImagePropertyPixelWidth] as? Int),
            try #require(properties[kCGImagePropertyPixelHeight] as? Int)
        )
    }

    static func opaqueFraction(_ image: CGImage) throws -> Double {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn)
        let opaque = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 128 }.count
        return Double(opaque) / Double(width * height)
    }

    static func bytes(_ color: UIColor) -> [Int] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue].map { Int(($0 * 255).rounded()) }
    }
}
