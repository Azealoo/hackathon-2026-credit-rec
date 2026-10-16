import SwiftUI
import Testing
import UIKit
@testable import Paywise

/// SPEC §6.4: a stale Live Activity (`context.isStale`) is the bare Paywise glyph (the island mark), whatever state it
/// went stale in: no card art, no last 4, no lines, no Lock Screen text. Renders the Shared pieces `PaywiseLiveActivity`
/// places, with `isStale = true`, through `ImageRenderer` at @3x on the island's black. When the source checkout is
/// reachable (the simulator), also writes a labeled composite to docs/overnight-shots/live-activity/stale-rendered.png.
@MainActor
struct StaleRenderTests {
    typealias State = PaywiseActivityAttributes.ContentState

    static let scale: CGFloat = 3
    /// design.md §2 accentDark, the island mark's drawn card.
    static let accentDark: (r: Int, g: Int, b: Int) = (0x5b, 0x74, 0xff)
    /// The island mark's two cards behind: paper #f5f5f7 at 62% over the island's black.
    static let stack: (r: Int, g: Int, b: Int) = (152, 152, 153)

    /// States a press can leave in the island: *Checking* (what `-demoActivity stale` shows), Keep with card art, the
    /// switch fallback with art and last 4, and Couldn't check with its ⚠.
    static func states() -> [(name: String, state: State)] {
        let deps = TestEnvironment(reading: .laptopCheckout).deps
        return [
            ("Checking", DemoActivity.checking.state(deps: deps)),
            ("Keep", DemoActivity.keep.state(deps: deps)),
            ("Switch fallback", DemoActivity.switchFallback.state(deps: deps)),
            ("Couldn't check", DemoActivity.couldntCheck.state(deps: deps)),
        ]
    }

    enum Part: String, CaseIterable {
        case compactLeading = "Compact leading"
        case compactTrailing = "Compact trailing"
        case minimal = "Minimal"
        case expandedLeading = "Expanded leading"
        case expandedTrailing = "Expanded trailing"
        case expandedBottom = "Expanded bottom"
        case lockScreen = "Lock Screen"

        /// The slot, in points (compact: the 393-pt screen's 52.33 × 36.67; minimal: the 36.67-pt circle's box).
        var size: CGSize {
            switch self {
            case .compactLeading, .compactTrailing: CardArt.compactSize
            case .minimal: CGSize(width: 110.0 / 3, height: 110.0 / 3)
            case .expandedLeading, .expandedTrailing: CGSize(width: 64, height: 48)
            case .expandedBottom: CGSize(width: 340, height: 64)
            case .lockScreen: CGSize(width: 360, height: 64)
            }
        }

        /// Parts that draw nothing at all when stale.
        var emptyWhenStale: Bool {
            self == .compactTrailing || self == .expandedTrailing || self == .expandedBottom
        }
    }

    @ViewBuilder
    static func view(_ part: Part, state: State, isStale: Bool) -> some View {
        switch part {
        case .compactLeading: IslandLeadingMark(state: state, isStale: isStale, slot: .compact)
        case .compactTrailing: IslandStatusMark(state: state, isStale: isStale, slot: .compact)
        case .minimal: IslandMinimalMark(state: state, isStale: isStale)
        case .expandedLeading: IslandLeadingMark(state: state, isStale: isStale, slot: .expanded)
        case .expandedTrailing: IslandStatusMark(state: state, isStale: isStale, slot: .expanded)
        case .expandedBottom: IslandExpandedBottom(state: state, isStale: isStale)
        case .lockScreen: LockScreenContent(state: state, isStale: isStale)
        }
    }

    /// One part in its slot on black, in the dark appearance (as the widget's `islandAppearance()` draws it). The black
    /// is a ZStack layer, not a background, so a part that draws nothing still fills its slot.
    static func cell(_ part: Part, state: State, isStale: Bool) -> some View {
        ZStack {
            Color.black
            view(part, state: state, isStale: isStale)
        }
        .frame(width: part.size.width, height: part.size.height)
        .environment(\.colorScheme, .dark)
    }

    static func render(_ view: some View) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return try #require(renderer.cgImage)
    }

    /// The image as sRGB RGBA8, row by row.
    static func pixels(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        try #require(drawn)
        return bytes
    }

    /// Pixels brighter than the black background.
    static func litPixels(_ bytes: [UInt8]) -> Int {
        stride(from: 0, to: bytes.count, by: 4).count { bytes[$0] > 8 || bytes[$0 + 1] > 8 || bytes[$0 + 2] > 8 }
    }

    /// Pixels within `tolerance` of `color`.
    static func pixels(_ bytes: [UInt8], near color: (r: Int, g: Int, b: Int), tolerance: Int = 10) -> Int {
        stride(from: 0, to: bytes.count, by: 4).count {
            abs(Int(bytes[$0]) - color.r) <= tolerance && abs(Int(bytes[$0 + 1]) - color.g) <= tolerance
                && abs(Int(bytes[$0 + 2]) - color.b) <= tolerance
        }
    }

    /// Every part renders the same pixels whichever state went stale: nothing of the state shows. The leading,
    /// minimal and Lock Screen parts draw the island mark (accentDark card, paper stack at 62%), the rest draw nothing.
    @Test(arguments: Part.allCases)
    func staleIsTheBareGlyphInEveryState(_ part: Part) throws {
        let states = Self.states()
        let image = try Self.render(Self.cell(part, state: states[0].state, isStale: true))
        // The whole slot was drawn, at @3x.
        #expect(image.width == Int((part.size.width * Self.scale).rounded()), "\(part.rawValue) width")
        #expect(image.height == Int((part.size.height * Self.scale).rounded()), "\(part.rawValue) height")
        let reference = try Self.pixels(image)
        for (name, state) in states.dropFirst() {
            let stale = try Self.pixels(Self.render(Self.cell(part, state: state, isStale: true)))
            #expect(stale == reference, "\(part.rawValue), stale from \(name), differs from stale Checking")
        }
        if part.emptyWhenStale {
            #expect(Self.litPixels(reference) == 0, "\(part.rawValue) draws something when stale")
        } else {
            // The island mark alone: lit pixels, the solid ones the accentDark card or the paper stack at 62% (text
            // or card art would add other colors). On macOS CoreSVG at 22 pt they are 39% and 33% of the lit pixels.
            let lit = Self.litPixels(reference)
            #expect(lit > 0, "\(part.rawValue) draws nothing when stale")
            let card = Self.pixels(reference, near: Self.accentDark)
            let stack = Self.pixels(reference, near: Self.stack)
            #expect(card > lit / 4, "\(part.rawValue)'s stale mark has no accentDark card (\(card) of \(lit))")
            #expect(stack > lit / 8, "\(part.rawValue)'s stale mark has no paper stack (\(stack) of \(lit))")
            #expect(card + stack > lit / 2, "\(part.rawValue)'s stale mark has other colors (\(card + stack) of \(lit))")
        }
    }

    /// The comparison above means something: the same parts do show the state when not stale.
    @Test func freshStatesDrawMoreThanTheGlyph() throws {
        let states = Self.states()
        let keep = try #require(states.first { $0.name == "Keep" }?.state)
        let fallback = try #require(states.first { $0.name == "Switch fallback" }?.state)
        for (part, state) in [(Part.compactLeading, keep), (.compactTrailing, keep), (.minimal, keep),
                              (.compactTrailing, fallback), (.expandedBottom, fallback), (.lockScreen, keep)] {
            let fresh = try Self.pixels(Self.render(Self.cell(part, state: state, isStale: false)))
            let stale = try Self.pixels(Self.render(Self.cell(part, state: state, isStale: true)))
            #expect(fresh != stale, "\(part.rawValue) looks the same fresh and stale")
        }
    }

    /// docs/overnight-shots/live-activity/stale-rendered.png: every part, for every state, stale, on black at @3x.
    @Test func writesTheLabeledComposite() throws {
        let image = try Self.render(StaleComposite(states: Self.states()))
        #expect(image.width > 0 && image.height > 0)
        guard AssetTests.sourceReachable else { return }
        let folder = AssetTests.iosFolder.deletingLastPathComponent().appending(path: "docs/overnight-shots/live-activity")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let png = try #require(UIImage(cgImage: image, scale: Self.scale, orientation: .up).pngData())
        let url = folder.appending(path: "stale-rendered.png")
        try png.write(to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

/// The composite: one block per state, each slot framed, captioned under it. The captions are this test's labels;
/// the framed slots are the app's own views.
private struct StaleComposite: View {
    typealias Part = StaleRenderTests.Part
    let states: [(name: String, state: PaywiseActivityAttributes.ContentState)]

    private static let islandParts: [Part] = [
        .compactLeading, .compactTrailing, .minimal, .expandedLeading, .expandedTrailing,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Live Activity with isStale = true · ImageRenderer @3x")
                    .font(.system(size: 17, weight: .semibold))
                Text("Each outlined box is one widget slot, drawn on the island's black. Captions are test labels.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(states.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 10) {
                    Text("Went stale as: \(entry.name)")
                        .font(.system(size: 14, weight: .semibold))
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Self.islandParts, id: \.self) { part in
                            slot(part, state: entry.state)
                        }
                    }
                    HStack(alignment: .top, spacing: 14) {
                        slot(.expandedBottom, state: entry.state)
                        slot(.lockScreen, state: entry.state)
                    }
                }
            }
        }
        .padding(24)
        .background(Color.black)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private func slot(_ part: Part, state: PaywiseActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            StaleRenderTests.cell(part, state: state, isStale: true)
                .padding(2)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(uiColor: .systemGray3), lineWidth: 0.5))
            Text(part.rawValue)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}
