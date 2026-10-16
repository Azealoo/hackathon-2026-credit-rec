import XCTest

/// The Back Tap prompt (owner request, Oct 16): it is onboarding's trigger step, with [Set Up Back Tap] and
/// [Not Now]; [Not Now] holds across relaunches and the Check tab's re-offer; the re-offer after the 2nd in-app check
/// shows once. Against the LIVE backend (the first result and the checks), with the laptop checkout as the newest photo
/// (`ios/tools/run_ui_tour.sh` adds it; or `xcrun simctl addmedia <udid> fixtures/screenshots/laptop-checkout.png`).
final class BackTapPromptUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testNotNowInOnboardingPersists() throws {
        let app = Launch.app(["-resetState"])
        XCTAssertTrue(app.buttons["onboarding.consent.continue"].waitForExistence(timeout: 10))
        app.buttons["onboarding.consent.continue"].tap()
        XCTAssertTrue(app.buttons["onboarding.cards.demoWallet"].waitForExistence(timeout: 5))
        app.buttons["onboarding.cards.demoWallet"].tap()
        app.buttons["onboarding.cards.continue"].tap()
        XCTAssertTrue(app.staticTexts["result.line1"].waitForExistence(timeout: 30), "the first result arrives")
        app.buttons["onboarding.firstResult.continue"].tap()

        // The trigger step leads with the prompt: both buttons, the copy, the demo's one VoiceOver label.
        let setUp = app.buttons["backTapPrompt.setUp"]
        let notNow = app.buttons["backTapPrompt.notNow"]
        XCTAssertTrue(setUp.waitForExistence(timeout: 5), "the Back Tap prompt shows in onboarding")
        XCTAssertTrue(notNow.exists)
        XCTAssertEqual(setUp.label, "Set Up Back Tap")
        XCTAssertEqual(notNow.label, "Not Now")
        XCTAssertEqual(app.staticTexts["backTapPrompt.title"].label, "Check any checkout with a double tap")
        XCTAssertEqual(
            app.staticTexts["backTapPrompt.line"].label,
            "Double-tap the back of your iPhone on any checkout, and Paywise tells you which card covers it."
        )
        let demo = app.descendants(matching: .any)["backTapPrompt.animation"]
        XCTAssertTrue(demo.exists, "the looping demo (Reduce Motion is off)")
        XCTAssertEqual(demo.label, "Animation: a finger double-taps the back of an iPhone")
        attach("prompt")

        notNow.tap()
        XCTAssertTrue(app.buttons["check.pickScreenshot"].waitForExistence(timeout: 5), "Not Now ends onboarding")
        XCTAssertTrue(setUp.waitForAbsence(timeout: 3))
        app.terminate()

        // A relaunch reads Not Now back from the App Group.
        let relaunched = Launch.app(["-tab", "check"])
        XCTAssertTrue(relaunched.buttons["check.pickScreenshot"].waitForExistence(timeout: 10))
        XCTAssertFalse(relaunched.buttons["backTapPrompt.setUp"].waitForExistence(timeout: 3), "Not Now holds after a relaunch")

        // Two in-app checks, each closed with the in-app [Done]: the re-offer stays quiet.
        for check in 1...2 {
            checkAndClose(relaunched, check: check)
        }
        XCTAssertFalse(relaunched.buttons["backTapPrompt.setUp"].waitForExistence(timeout: 4), "not after the 2nd check")
        relaunched.terminate()

        let again = Launch.app(["-tab", "check"])
        XCTAssertTrue(again.buttons["check.pickScreenshot"].waitForExistence(timeout: 10))
        XCTAssertFalse(again.buttons["backTapPrompt.setUp"].waitForExistence(timeout: 4), "nor on the next launch")
    }

    /// Setup never done (onboarding skipped): after the 2nd in-app check, back at the tab's start, the prompt shows,
    /// and only once. The setup row stays until setup is done.
    @MainActor
    func testPromptOfferedOnceAfterTheSecondCheck() throws {
        let app = Launch.app(["-resetState", "-skipOnboarding", "-tab", "check"])
        checkAndClose(app, check: 1)
        XCTAssertFalse(app.buttons["backTapPrompt.setUp"].waitForExistence(timeout: 3), "not after one check")
        checkAndClose(app, check: 2)
        let setUp = app.buttons["backTapPrompt.setUp"]
        XCTAssertTrue(setUp.waitForExistence(timeout: 6), "offered again after the 2nd check")
        attach("prompt-again")
        // Swiped away: it counts as shown.
        app.descendants(matching: .any)["backTapPrompt.animation"].swipeDown(velocity: .fast)
        XCTAssertTrue(setUp.waitForAbsence(timeout: 5))
        app.terminate()

        let relaunched = Launch.app(["-tab", "check"])
        XCTAssertTrue(relaunched.buttons["check.pickScreenshot"].waitForExistence(timeout: 10))
        XCTAssertFalse(relaunched.buttons["backTapPrompt.setUp"].waitForExistence(timeout: 4), "offered once")

        // The quiet row still leads to setup, in a sheet; [Done] there hides the row.
        let row = relaunched.buttons["check.triggerSetup"]
        XCTAssertTrue(relaunched.scrollTo(row), "the setup row after the 2nd check")
        XCTAssertEqual(row.label, "Set Up Back Tap")
        row.tap()
        let done = relaunched.buttons["trigger.done"]
        XCTAssertTrue(relaunched.scrollTo(done), "the setup screen")
        XCTAssertTrue(relaunched.buttons["trigger.tryItNow"].exists || relaunched.staticTexts["trigger.works"].exists)
        done.tap()
        XCTAssertTrue(done.waitForAbsence(timeout: 5))
        XCTAssertTrue(row.waitForAbsence(timeout: 5), "setup done: the row goes")
    }

    /// Settings › Set Up Back Tap › Try it now, a press (`-simulateBackTap`: the real check on a render of the screen)
    /// → "Back Tap works ✓" → [Done] closes the whole setup, back to Settings (it once did nothing on this path).
    @MainActor
    func testSettingsTryItNowDoneClosesSetup() throws {
        let app = Launch.app(["-resetState", "-skipOnboarding", "-tab", "settings", "-simulateBackTap"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        let trigger = app.buttons["settings.trigger"]
        XCTAssertTrue(app.scrollTo(trigger), "Settings › Set Up Back Tap")
        let tryIt = app.buttons["trigger.tryItNow"]
        XCTAssertTrue(app.tap(trigger, until: tryIt), "the setup sheet")
        XCTAssertTrue(app.scrollTo(tryIt), "Try it now")
        tryIt.tap()
        XCTAssertTrue(app.staticTexts["tryItNow.instruction"].waitForExistence(timeout: 5))
        let works = app.staticTexts["trigger.works"]
        XCTAssertTrue(works.waitForExistence(timeout: 25), "the press arrives: Back Tap works")
        let done = app.buttons["tryItNow.done"]
        XCTAssertTrue(app.scrollTo(done), "Try it now › Done")
        attach("settings-try-it-now-works")

        done.tap()
        XCTAssertTrue(done.waitForAbsence(timeout: 5), "Done leaves Try it now")
        XCTAssertTrue(app.buttons["trigger.done"].waitForAbsence(timeout: 5), "and closes the setup, not just a pop")
        XCTAssertTrue(trigger.waitForExistence(timeout: 5), "back to Settings")
        XCTAssertTrue(trigger.isHittable, "Settings in front, not under a sheet")
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }

    /// "Check a screenshot" → the newest photo → [Paying with Freedom] → Saved, with [What we sent] and [Done] side by
    /// side → [Done] → the tab's start.
    @MainActor
    private func checkAndClose(_ app: XCUIApplication, check: Int) {
        app.pickNewestPhoto()
        let save = app.buttons["result.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 15), "check \(check): the Switch result")
        save.tap()
        let sent = app.buttons["result.whatWeSent"]
        let done = app.buttons["result.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 8), "check \(check): Saved has [Done]")
        XCTAssertTrue(sent.exists)
        XCTAssertEqual(sent.frame.minY, done.frame.minY, accuracy: 1, "side by side")
        XCTAssertEqual(sent.frame.width, done.frame.width, accuracy: 1, "equal widths")
        XCTAssertEqual(done.frame.minX - sent.frame.maxX, 10, accuracy: 1, "10 pt apart")
        done.tap()
        XCTAssertTrue(done.waitForAbsence(timeout: 5), "check \(check): Done goes back to the start")
        XCTAssertTrue(app.buttons["check.pickScreenshot"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
