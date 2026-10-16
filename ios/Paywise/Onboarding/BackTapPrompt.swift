import CoreHaptics
import SwiftUI
import UIKit

/// The Back Tap prompt (owner request, Oct 16): a Paywise sheet, not a system alert, that shows the gesture and asks
/// once whether to set it up. iOS has no Back Tap API, so the app can't turn it on or read whether it's on: the prompt
/// leads to the guided steps (`TriggerSetupView`), and "Try it now" proves it works when a press arrives.
///
/// Where it shows: as the trigger step in onboarding, and once more in the Check tab when the user skipped setup
/// (the "offered again after the 2nd in-app check" hook, SPEC §5.1 step 3). [Not Now] and a confirmed setup end it.
enum BackTapPrompt {
    static let title = "Check any checkout with a double tap"
    static let line = "Double-tap the back of your iPhone on any checkout, and Paywise tells you which card covers it."
    static let setUpTitle = "Set Up Back Tap"
    static let notNowTitle = "Not Now"
    /// VoiceOver: one label for the looping demo.
    static let animationLabel = "Animation: a finger double-taps the back of an iPhone"
    /// VoiceOver under Reduce Motion, where the demo is two still frames.
    static let illustrationLabel = "Illustration: a finger double-taps the back of an iPhone"

    enum Place: Sendable {
        /// The trigger step at the end of onboarding.
        case onboarding
        /// The Check tab, after the 2nd in-app check, when setup was skipped.
        case checkTab
    }

    /// Whether the prompt shows at `place` now.
    static func shouldOffer(_ place: Place, settings: PaywiseSettings) -> Bool {
        guard !settings.backTapPromptDeclined, !settings.triggerSetupConfirmed else { return false }
        switch place {
        case .onboarding:
            return true
        case .checkTab:
            return settings.inAppCheckCount >= 2 && !settings.triggerSetupDone && !settings.backTapPromptReoffered
        }
    }

    /// The prompt is on screen: the Check tab offers it once.
    static func didShow(_ place: Place, settings: PaywiseSettings) {
        if place == .checkTab { settings.backTapPromptReoffered = true }
    }

    /// [Not Now]: never shown again.
    static func notNow(settings: PaywiseSettings) {
        settings.backTapPromptDeclined = true
    }

    /// "Try it now" saw a press: setup is done and confirmed, so neither the prompt nor the Check tab's setup row shows.
    static func confirmSetup(settings: PaywiseSettings) {
        settings.triggerSetupConfirmed = true
        settings.triggerSetupDone = true
    }
}

// MARK: The sheet

/// The prompt as a sheet sized to its content (scrolls when the text is too large to fit).
struct BackTapPromptSheet: View {
    let setUp: () -> Void
    let notNow: () -> Void
    @State private var contentHeight: CGFloat = 600

    var body: some View {
        ScrollView {
            BackTapPromptContent(setUp: setUp, notNow: notNow)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemGroupedBackground))
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
        .accessibilityIdentifier("backTapPrompt")
    }
}

/// The demo, the title and line, and the two buttons.
struct BackTapPromptContent: View {
    let setUp: () -> Void
    let notNow: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            BackTapDemo()
            VStack(spacing: 10) {
                Text(BackTapPrompt.title)
                    .font(.app(28, .bold))
                    .tracking(-0.6)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("backTapPrompt.title")
                Text(BackTapPrompt.line)
                    .font(.app(17))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("backTapPrompt.line")
            }
            VStack(spacing: 10) {
                Button(BackTapPrompt.setUpTitle, action: setUp)
                    .buttonStyle(AppButtonStyle(prominent: true))
                    .accessibilityIdentifier("backTapPrompt.setUp")
                Button(BackTapPrompt.notNowTitle, action: notNow)
                    .buttonStyle(AppButtonStyle(prominent: false))
                    .accessibilityIdentifier("backTapPrompt.notNow")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }
}

// MARK: The motion demo

/// A phone seen from the back in a hand; the index finger taps twice, with a ripple on each tap. Loops with a
/// matching two-tap haptic while visible. Under Reduce Motion: two still frames, no animation and no haptics.
struct BackTapDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var cycle = 0
    @State private var haptics: DoubleTapHaptics?

    var body: some View {
        Group {
            if reduceMotion {
                BackTapStillFrames()
            } else {
                KeyframeAnimator(initialValue: TapPose.rest, trigger: cycle) { pose in
                    BackTapIllustration(pose: pose)
                } keyframes: { _ in
                    TapPose.keyframes
                }
                .task(id: scenePhase == .active) {
                    guard scenePhase == .active else { return }
                    await loop()
                }
                .onDisappear {
                    haptics?.stop()
                    haptics = nil
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: TapPose.canvas.height + 24)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reduceMotion ? BackTapPrompt.illustrationLabel : BackTapPrompt.animationLabel)
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier(reduceMotion ? "backTapPrompt.still" : "backTapPrompt.animation")
    }

    /// One trigger per cycle drives both the keyframes and the haptic, so the buzz lands on the drawn taps.
    private func loop() async {
        let haptics = DoubleTapHaptics.make()
        haptics?.start()
        self.haptics = haptics
        var played = 0
        while !Task.isCancelled {
            cycle &+= 1
            if played < DoubleTapHaptics.cycles {
                haptics?.playDoubleTap()
                played += 1
            }
            try? await Task.sleep(for: .seconds(TapPose.period))
        }
        haptics?.stop()
    }
}

/// One moment of the demo: how far the finger is down, and each ripple's progress (0 = not started, 1 = gone).
struct TapPose: Equatable, Sendable {
    var press: Double = 0
    var ring1: Double = 0
    var ring2: Double = 0

    static let rest = TapPose()
    /// Seconds per loop.
    static let period: Double = 2.4
    /// When the first tap lands, from the start of a loop; the second lands `DoubleTapHaptics.gap` later.
    static let firstTap: Double = 0.5
    static let canvas = CGSize(width: 240, height: 190)

    @KeyframesBuilder<TapPose>
    static var keyframes: some Keyframes<TapPose> {
        let gap = DoubleTapHaptics.gap
        let ringLife = 0.7
        KeyframeTrack(\.press) {
            LinearKeyframe(0, duration: firstTap - 0.12)
            CubicKeyframe(1, duration: 0.12)
            LinearKeyframe(0.4, duration: gap / 2)
            LinearKeyframe(1, duration: gap / 2)
            CubicKeyframe(0, duration: 0.3)
            LinearKeyframe(0, duration: period - firstTap - gap - 0.3)
        }
        KeyframeTrack(\.ring1) {
            LinearKeyframe(0, duration: firstTap)
            LinearKeyframe(1, duration: ringLife)
            LinearKeyframe(1, duration: period - firstTap - ringLife)
        }
        KeyframeTrack(\.ring2) {
            LinearKeyframe(0, duration: firstTap + gap)
            LinearKeyframe(1, duration: ringLife)
            LinearKeyframe(1, duration: period - firstTap - gap - ringLife)
        }
    }
}

/// The drawing, in design.md tokens: system greys for the phone and hand, the `accent` asset for the ripples.
struct BackTapIllustration: View {
    let pose: TapPose

    /// Where the fingertip touches the back, in the canvas.
    private static let tapPoint = CGPoint(x: 140, y: 78)

    var body: some View {
        ZStack {
            phone
            // The holding hand: the palm round the left edge, three fingers across the back.
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color(.systemGray3))
                .frame(width: 74, height: 132)
                .rotationEffect(.degrees(8))
                .position(x: 62, y: 166)
            ForEach(Array(Self.fingers.enumerated()), id: \.offset) { _, finger in
                Capsule()
                    .fill(Color(.systemGray3))
                    .overlay(Capsule().stroke(Color(.systemGray2), lineWidth: 1))
                    .frame(width: finger.width, height: 22)
                    .rotationEffect(.degrees(finger.angle))
                    .position(x: 70 + finger.width / 2, y: finger.y)
            }
            ripple(pose.ring1)
            ripple(pose.ring2)
            indexFinger
        }
        .frame(width: TapPose.canvas.width, height: TapPose.canvas.height)
    }

    private static let fingers: [(width: CGFloat, y: CGFloat, angle: Double)] = [
        (78, 118, -4), (72, 142, -2), (62, 165, 0),
    ]

    private var phone: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.systemGray5))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color(.systemGray3), lineWidth: 1.5)
                )
            // The camera bump, top left as seen from the back.
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(.systemGray4))
                .frame(width: 38, height: 38)
                .overlay {
                    ZStack {
                        lens.position(x: 11, y: 11)
                        lens.position(x: 11, y: 27)
                        lens.position(x: 27, y: 19)
                        Circle().fill(Color(.systemGray3)).frame(width: 5, height: 5).position(x: 28, y: 31)
                    }
                }
                .padding(9)
        }
        .frame(width: 100, height: 186)
        .position(x: 132, y: 100)
    }

    private var lens: some View {
        Circle()
            .fill(Color(.systemGray))
            .frame(width: 11, height: 11)
            .overlay(Circle().stroke(Color(.systemGray2), lineWidth: 1.5))
    }

    /// The tapping finger: lifted toward the viewer (larger, with a looser shadow) at `press` 0, on the back at 1.
    private var indexFinger: some View {
        let lift = 1 - pose.press
        return Capsule()
            .fill(Color(.systemGray3))
            .overlay(Capsule().stroke(Color(.systemGray2), lineWidth: 1))
            // The nail faces the viewer: the fingertip's pad is on the phone.
            .overlay(alignment: .trailing) {
                Capsule()
                    .fill(Color(.systemGray4))
                    .overlay(Capsule().stroke(Color(.systemGray2), lineWidth: 0.75))
                    .frame(width: 16, height: 13)
                    .padding(.trailing, 5)
            }
            .frame(width: 84, height: 24)
            // The tip is the trailing end; rotate about it so it stays on the tap point.
            .rotationEffect(.degrees(-28), anchor: .trailing)
            .scaleEffect(1 + 0.07 * lift, anchor: .trailing)
            .shadow(color: .black.opacity(0.10 + 0.10 * lift), radius: 1.5 + 5 * lift, x: 1 + 4 * lift, y: 1 + 6 * lift)
            .offset(x: -5 * lift, y: -7 * lift)
            .position(x: Self.tapPoint.x - 42 + 10, y: Self.tapPoint.y)
    }

    private func ripple(_ progress: Double) -> some View {
        Circle()
            .stroke(Color("accent"), lineWidth: 2.5)
            .frame(width: 44, height: 44)
            .scaleEffect(0.3 + 1.5 * progress)
            .opacity(progress > 0 && progress < 1 ? 1 - progress : 0)
            .position(Self.tapPoint)
    }
}

/// Reduce Motion: the two taps as two numbered still frames.
private struct BackTapStillFrames: View {
    var body: some View {
        HStack(spacing: 4) {
            frame(1, TapPose(press: 1, ring1: 0.3))
            frame(2, TapPose(press: 1, ring1: 0.62, ring2: 0.3))
        }
    }

    /// Two frames fit a 335-pt panel (a 375-pt-wide iPhone, less the sheet's margins).
    private static let scale: CGFloat = 0.68

    private func frame(_ number: Int, _ pose: TapPose) -> some View {
        // Nudged down, so the hand runs off the panel's edge as in the animated demo.
        BackTapIllustration(pose: pose)
            .scaleEffect(Self.scale)
            .frame(width: TapPose.canvas.width * Self.scale, height: TapPose.canvas.height + 24)
            .offset(y: 20)
            .overlay(alignment: .topLeading) {
                Text("\(number)")
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color("accent"), in: Circle())
                    .padding(.top, 14)
                    .padding(.leading, 10)
            }
    }
}

// MARK: Haptics

/// Two transient taps `gap` apart, played with each demo loop (`TapPose.firstTap` into the loop) for the first
/// `cycles` loops. Only on hardware with haptics (`supportsHaptics`); the engine stops when the demo goes away.
@MainActor
final class DoubleTapHaptics {
    /// Seconds between the two taps.
    nonisolated static let gap: Double = 0.12
    /// Loops that carry the haptic; later loops are silent (iOS gives no way to read the System Haptics switch, so
    /// the demo doesn't buzz for as long as the sheet stays open).
    nonisolated static let cycles = 3

    /// When each tap plays, from the start of a loop.
    nonisolated static var tapTimes: [TimeInterval] { [TapPose.firstTap, TapPose.firstTap + gap] }

    nonisolated static func pattern() throws -> CHHapticPattern {
        let events = tapTimes.map { time in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.75),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.55),
                ],
                relativeTime: time
            )
        }
        return try CHHapticPattern(events: events, parameters: [])
    }

    /// nil when the hardware can't play haptics (the simulator, older iPads).
    static func make() -> DoubleTapHaptics? {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let pattern = try? pattern(),
              let engine = try? CHHapticEngine()
        else { return nil }
        return DoubleTapHaptics(engine: engine, pattern: pattern)
    }

    private var engine: CHHapticEngine?
    private let pattern: CHHapticPattern

    private init(engine: CHHapticEngine, pattern: CHHapticPattern) {
        self.engine = engine
        self.pattern = pattern
        engine.playsHapticsOnly = true
    }

    func start() {
        try? engine?.start()
    }

    /// Plays one loop's two taps, starting now.
    func playDoubleTap() {
        guard let engine else { return }
        do {
            // The engine stops when the app goes to the background; start it again if needed.
            try engine.start()
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            // No haptic this loop; the drawn taps still show the gesture.
        }
    }

    func stop() {
        engine?.stop(completionHandler: nil)
        engine = nil
    }
}

// MARK: System appearance for sheets in the Check tab

/// The phone's own light/dark setting. The Check tab pins the window light (design.md §1), and a sheet inherits that;
/// setup screens follow the system (R18), so sheets opened from the Check tab ask the screen, which a window's
/// override doesn't change.
@MainActor
enum SystemAppearance {
    static var current: ColorScheme {
        let style = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.traitCollection.userInterfaceStyle
        return style == .dark ? .dark : .light
    }
}

/// Draws the content (and its presentation) in the system appearance, whatever the presenting screen pins.
struct FollowsSystemAppearance: ViewModifier {
    @State private var scheme = SystemAppearance.current

    func body(content: Content) -> some View {
        content
            .environment(\.colorScheme, scheme)
            .preferredColorScheme(scheme)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                scheme = SystemAppearance.current
            }
    }
}

extension View {
    func followsSystemAppearance() -> some View {
        modifier(FollowsSystemAppearance())
    }
}

#Preview("Prompt") {
    Color.clear.sheet(isPresented: .constant(true)) {
        BackTapPromptSheet(setUp: {}, notNow: {})
    }
}
