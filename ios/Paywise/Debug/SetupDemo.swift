#if DEBUG
import AppIntents
import os
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Debug-only hooks for the Back Tap prompt and setup (screenshots and UI tests):
///
/// | Launch argument | Does |
/// |---|---|
/// | `-showBackTapPrompt` | The Check tab opens with the Back Tap prompt up (use with `-skipOnboarding -tab check`). |
/// | `-forceReduceMotion` | Every view reads `accessibilityReduceMotion` as on: the prompt's still frames, a still breadcrumb. |
/// | `-simulateBackTap` | "Try it now" gets a press 1.5 s after it opens: the real check (`CheckFlow`) on a render of its own screen, as the Shortcut would run it, so the screen turns to "Back Tap works ✓". |
/// | `-simulateDoubleTap` | At launch, one Back Tap that fires the Shortcut twice 1.5 s apart (docs/spikes.md › Results › Back Tap): two `CheckCheckoutIntent` runs on the sample checkout render. Settings › What we sent then shows one row (`PressGate`). |
enum SetupDemo {
    static let log = Logger(subsystem: "com.azealoo.paywise", category: "demo")

    static var showBackTapPrompt: Bool { ProcessInfo.processInfo.arguments.contains("-showBackTapPrompt") }
    static var forceReduceMotion: Bool { ProcessInfo.processInfo.arguments.contains("-forceReduceMotion") }
    static var simulateBackTap: Bool { ProcessInfo.processInfo.arguments.contains("-simulateBackTap") }
    static var simulateDoubleTap: Bool { ProcessInfo.processInfo.arguments.contains("-simulateDoubleTap") }

    /// `-simulateDoubleTap`: two intent runs `gap` apart, as a double-firing Back Tap makes them.
    @MainActor
    static func simulateDoubleTap(gap: Duration = .milliseconds(1500)) async {
        guard let png = SampleCheckoutRender.png() else {
            log.error("-simulateDoubleTap: couldn't render the sample checkout")
            return
        }
        let first = Task { @MainActor in await press(png) }
        try? await Task.sleep(for: gap)
        await press(png)
        await first.value
        log.notice("-simulateDoubleTap: \(Dependencies.current.checkStore.all().count, privacy: .public) check record(s)")
    }

    @MainActor
    private static func press(_ png: Data) async {
        let intent = CheckCheckoutIntent(image: IntentFile(data: png, filename: "screenshot.png", type: .png))
        _ = try? await intent.perform(trace: CheckTrace(source: .intent))
    }

    /// A press on "Try it now": the check chain a Back Tap runs (read on the phone, `/v1/check`, the `CheckRecord`),
    /// on the sample checkout as the screen shows it, without the island.
    @MainActor
    static func simulatePress(after delay: Duration = .milliseconds(1500)) async {
        try? await Task.sleep(for: delay)
        guard let png = SampleCheckoutRender.png() else {
            log.error("-simulateBackTap: couldn't render the sample checkout")
            return
        }
        var deps = Dependencies.current
        deps.island = NoIsland()
        let outcome = await CheckFlow(deps: deps).run(imageData: png, trace: CheckTrace(source: .inApp))
        log.notice("-simulateBackTap: \(String(describing: outcome), privacy: .public)")
    }
}

/// "Try it now" as a screenshot of it would be: the instruction and the sample checkout below the navigation bar, at
/// the iPhone 18 Pro's 402 × 874 pt and @3x. Used by `-simulateBackTap` and by the unit test that runs it through
/// `VisionScreenReader` and `CheckoutGate`. (The spinner and the Safari link are left out: `ImageRenderer` draws no
/// UIKit-backed views.)
@MainActor
enum SampleCheckoutRender {
    static let screen = CGSize(width: 402, height: 874)
    /// Status bar and the inline navigation bar.
    static let topInset: CGFloat = 116

    static func view(typeSize: DynamicTypeSize = .large) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            TryItNowHeader()
            SampleCheckoutCard()
        }
        .padding(.horizontal, 16)
        .padding(.top, topInset)
        .frame(width: screen.width, height: screen.height, alignment: .top)
        .background(Color(.systemGroupedBackground))
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, typeSize)
    }

    static func png(scale: CGFloat = 3, typeSize: DynamicTypeSize = .large) -> Data? {
        let renderer = ImageRenderer(content: view(typeSize: typeSize))
        renderer.scale = scale
        return renderer.uiImage?.pngData()
    }
}
#endif
