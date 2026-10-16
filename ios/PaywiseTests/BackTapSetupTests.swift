import CoreHaptics
import Foundation
import SwiftUI
import Testing
@testable import Paywise

// The Back Tap prompt and the guided setup (owner request, Oct 16; SPEC §5.1 steps 3–4 now lead with Back Tap).

private func freshSettings() -> PaywiseSettings {
    PaywiseSettings(suiteName: "paywise.tests.\(UUID().uuidString)")
}

/// When the prompt shows: in onboarding, once more in the Check tab after the 2nd in-app check if setup was skipped,
/// and never after [Not Now] or a confirmed setup.
struct BackTapPromptRuleTests {
    @Test func showsInOnboardingUntilDeclinedOrConfirmed() {
        let settings = freshSettings()
        #expect(BackTapPrompt.shouldOffer(.onboarding, settings: settings))
        // Showing it in onboarding doesn't use up the Check tab's one re-offer.
        BackTapPrompt.didShow(.onboarding, settings: settings)
        #expect(BackTapPrompt.shouldOffer(.onboarding, settings: settings))
        #expect(!settings.backTapPromptReoffered)
    }

    @Test func checkTabOffersOnceAfterTheSecondCheck() {
        let settings = freshSettings()
        for count in 0...1 {
            settings.inAppCheckCount = count
            #expect(!BackTapPrompt.shouldOffer(.checkTab, settings: settings), "not after \(count) checks")
        }
        settings.inAppCheckCount = 2
        #expect(BackTapPrompt.shouldOffer(.checkTab, settings: settings))
        BackTapPrompt.didShow(.checkTab, settings: settings)
        #expect(settings.backTapPromptReoffered)
        settings.inAppCheckCount = 7
        #expect(!BackTapPrompt.shouldOffer(.checkTab, settings: settings), "offered once, not after every check")
        // Onboarding run again from Settings still shows it: only Not Now or a confirmed setup end it there.
        #expect(BackTapPrompt.shouldOffer(.onboarding, settings: settings))
    }

    @Test func checkTabNeedsSetupSkipped() {
        let settings = freshSettings()
        settings.inAppCheckCount = 2
        settings.triggerSetupDone = true
        #expect(!BackTapPrompt.shouldOffer(.checkTab, settings: settings), "setup was finished, not skipped")
        #expect(BackTapPrompt.shouldOffer(.onboarding, settings: settings))
    }

    @Test func notNowEndsItEverywhereAndPersists() {
        let suite = "paywise.tests.\(UUID().uuidString)"
        let settings = PaywiseSettings(suiteName: suite)
        settings.inAppCheckCount = 2
        BackTapPrompt.notNow(settings: settings)
        // A relaunch reads the same App Group defaults.
        let relaunched = PaywiseSettings(suiteName: suite)
        #expect(relaunched.backTapPromptDeclined)
        #expect(!BackTapPrompt.shouldOffer(.onboarding, settings: relaunched))
        #expect(!BackTapPrompt.shouldOffer(.checkTab, settings: relaunched))
        relaunched.inAppCheckCount = 5
        #expect(!BackTapPrompt.shouldOffer(.checkTab, settings: relaunched))
    }

    @Test func confirmedSetupEndsItAndTheSetupRow() {
        let settings = freshSettings()
        settings.inAppCheckCount = 2
        BackTapPrompt.confirmSetup(settings: settings)
        #expect(settings.triggerSetupConfirmed)
        #expect(settings.triggerSetupDone, "the Check tab's setup row hides too")
        #expect(!BackTapPrompt.shouldOffer(.onboarding, settings: settings))
        #expect(!BackTapPrompt.shouldOffer(.checkTab, settings: settings))
    }

    @MainActor
    @Test func resetStateClearsThePromptKeys() {
        let env = TestEnvironment(reading: .laptopCheckout)
        let settings = env.deps.settings
        settings.backTapPromptDeclined = true
        settings.backTapPromptReoffered = true
        settings.triggerSetupConfirmed = true
        LaunchOptions(resetState: true).apply(deps: env.deps)
        #expect(!settings.backTapPromptDeclined)
        #expect(!settings.backTapPromptReoffered)
        #expect(!settings.triggerSetupConfirmed)
        #expect(BackTapPrompt.shouldOffer(.onboarding, settings: settings))
    }
}

/// The prompt's words, the demo's timing and the haptic that goes with it.
struct BackTapPromptCopyTests {
    @Test func copy() {
        #expect(BackTapPrompt.title == "Check any checkout with a double tap")
        #expect(BackTapPrompt.line == "Double-tap the back of your iPhone on any checkout, and Paywise tells you which card covers it.")
        #expect(BackTapPrompt.setUpTitle == "Set Up Back Tap")
        #expect(BackTapPrompt.notNowTitle == "Not Now")
        #expect(BackTapPrompt.animationLabel == "Animation: a finger double-taps the back of an iPhone")
        // Back Tap leads wherever the trigger is explained.
        #expect(TriggerSetupView.intro.hasPrefix("Double-tap the back of your iPhone on any checkout"))
        #expect(CheckTabView.idleTitle == "Double-tap the back of your iPhone on any checkout")
        #expect(BackTapPath.text == "Settings › Accessibility › Touch › Back Tap › Double Tap › Paywise")
        #expect(TriggerSetupView.shortcutLink == nil, "no made-up iCloud link")
    }

    @Test func hapticTapsLandOnTheDrawnTaps() throws {
        // Two transient events ~120 ms apart, at the keyframes' tap times.
        #expect(DoubleTapHaptics.tapTimes == [TapPose.firstTap, TapPose.firstTap + 0.12])
        #expect(DoubleTapHaptics.gap == 0.12)
        let pattern = try DoubleTapHaptics.pattern()
        #expect(abs(pattern.duration - DoubleTapHaptics.tapTimes[1]) < 0.05)
        #expect(DoubleTapHaptics.tapTimes[1] < TapPose.period, "both taps inside one loop")
    }

    @MainActor
    @Test func noHapticsWithoutHardware() {
        // The simulator has no haptics: the demo runs without them rather than failing.
        if !CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            #expect(DoubleTapHaptics.make() == nil)
        }
    }
}

/// "Try it now": a check stored after the step opened means the press arrived.
struct TryItNowDetectionTests {
    @Test func onlyNewChecksCount() throws {
        let env = TestEnvironment(reading: .laptopCheckout)
        let store = env.deps.checkStore
        try store.write(try Fixtures.recordExample(), now: Fixtures.demoNow)
        let watch = NewCheckWatch(baseline: store.storedCheckIds())
        #expect(watch.baseline == ["5f0c0000-aaaa-4bbb-8ccc-ddddeeeeffff"])
        #expect(!watch.arrived(in: store.storedCheckIds()), "a check from before the step doesn't count")

        var later = try Fixtures.recordExample()
        later.checkId = "6a1d0000-aaaa-4bbb-8ccc-ddddeeeeffff"
        try store.write(later, now: Fixtures.demoNow)
        #expect(watch.newCheckIds(in: store.storedCheckIds()) == ["6a1d0000-aaaa-4bbb-8ccc-ddddeeeeffff"])
        #expect(watch.arrived(in: store.storedCheckIds()))
    }

    @Test func emptyFolderHasNoIds() {
        let env = TestEnvironment(reading: .laptopCheckout)
        #expect(env.deps.checkStore.storedCheckIds().isEmpty)
    }
}

/// The sample checkout on "Try it now", as a screenshot of it reads on the phone: it must pass the on-device gate so a
/// Back Tap there sends it and stores a check, and read like the S1 laptop.
@Suite(.serialized)
@MainActor
struct SampleCheckoutReadingTests {
    @Test func renderedSampleCardPassesTheGate() async throws {
        let png = try #require(SampleCheckoutRender.png(), "the Try it now screen renders")
        let reading = try await VisionScreenReader().read(png)
        let text = reading.redactedText
        print("PAYWISE_OCR sample-card checkout=\(reading.isCheckout) confidence=\(String(format: "%.2f", reading.ocrConfidence)) redactions=\(reading.redactions)\n\(text)\nPAYWISE_OCR_END")

        #expect(reading.isCheckout, "the on-device gate passes")
        let verdict = CheckoutGate.evaluate(text: text)
        #expect(verdict.total == "$1,499.00", "the total line reads $1,499.00")
        #expect(verdict.keyword != nil)
        #expect(text.localizedCaseInsensitiveContains("Northbay Electronics"), "merchant kept")
        #expect(text.contains("Aero 14 Laptop"))
        #expect(text.contains("Total  $1,499.00"))
        #expect(!text.contains("5678"), "the sample's last 4 never leaves")
        #expect(Redactor.longestDigitRun(in: text) < 12)
    }

    /// Up to XXL the item's name and price share one line: with "Aero 14" and "Laptop" on separate lines the backend's
    /// parser called the real XXL screenshot not a checkout in 5 of 10 tries (0 of 10 on one line, Oct 16).
    @Test(arguments: [DynamicTypeSize.large, .xLarge, .xxLarge])
    func itemStaysOnOneLine(_ typeSize: DynamicTypeSize) async throws {
        let png = try #require(SampleCheckoutRender.png(typeSize: typeSize))
        let reading = try await VisionScreenReader().read(png)
        let lines = reading.redactedText.components(separatedBy: "\n")
        #expect(reading.isCheckout, "\(typeSize)")
        #expect(lines.contains("Aero 14 Laptop  $1,499.00"), "\(typeSize): \(lines)")
        #expect(lines.contains("Total  $1,499.00"), "\(typeSize)")
    }

    /// The whole press on that screen: the intent reads the render with Vision, sends it (the stub answers with the
    /// S1 response), stores the check, and "Try it now" sees the new record.
    @Test func aPressOnTheSampleCardIsSeenByTryItNow() async throws {
        let png = try #require(SampleCheckoutRender.png())
        let env = TestEnvironment(
            reading: .laptopCheckout,
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample()))
        )
        var deps = env.deps
        deps.screenReader = VisionScreenReader()
        let watch = NewCheckWatch(baseline: deps.checkStore.storedCheckIds())

        let intent = CheckCheckoutIntent(image: .init(data: png, filename: "screenshot.png", type: .png))
        try await env.perform(intent, trace: CheckTrace(source: .intent), deps: deps)

        #expect(watch.arrived(in: deps.checkStore.storedCheckIds()), "Try it now sees the press")
        let sent = try #require(env.requests.first, "the sample was sent")
        let request = try JSONDecoder().decode(CheckRequest.self, from: sent)
        #expect(request.screen.ocrText.contains("Northbay Electronics"))
        #expect(request.screen.ocrText.contains("$1,499.00"))
        #expect(!request.screen.ocrText.contains("5678"))
        let record = try #require(deps.checkStore.latest(now: Fixtures.demoNow))
        #expect(record.filledCopy.line1 == "Use Freedom ••1234")
    }
}
