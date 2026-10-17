import XCTest

/// The screenshot tour (SPEC finish-line item F10): every app screen and state, plus the `-gallery` snippet states,
/// against the LIVE backend. Each screen is saved as a PNG to
///
///     docs/overnight-shots/<appearance>-<size>/<NN>-<name>.png
///
/// `<appearance>-<size>` comes from the `PAYWISE_SHOTS` environment variable (set it on the xcodebuild command line as
/// `TEST_RUNNER_PAYWISE_SHOTS=dark-default`); without it, the simulator's appearance and "default". Each image is also
/// attached to the result bundle. `ios/tools/run_ui_tour.sh` runs the tour four times: light, dark, and light at
/// Dynamic Type extra-large (XL) and extra-extra-large. Needs the laptop checkout in Photos (`xcrun simctl addmedia`,
/// see AppShellUITests).
final class ScreenshotTourUITests: XCTestCase {
    private var shots: Shots!

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testScreenshotTour() throws {
        shots = Shots(testCase: self)
        onboarding()
        checkAndSave()
        checkStates()
        claims()
        settings()
        emptyStates()
        backTapSetup()
        gallery()
        print("PAYWISE_UI tour: \(shots.count) screenshots in \(shots.dir.path)")
    }

    // MARK: Onboarding (follows the system appearance)

    @MainActor
    private func onboarding() {
        let app = Launch.app(["-resetState"])
        XCTAssertTrue(app.buttons["onboarding.consent.continue"].waitForExistence(timeout: 10))
        shots.snap("onboarding-consent")
        app.buttons["onboarding.consent.continue"].tap()

        XCTAssertTrue(app.buttons["onboarding.cards.demoWallet"].waitForExistence(timeout: 5))
        shots.snap("onboarding-cards-empty")
        app.buttons["onboarding.cards.demoWallet"].tap()
        shots.snap("onboarding-cards-demo-wallet")
        app.swipeUp()
        shots.snapIfScrolled("onboarding-cards-demo-wallet-bottom")
        app.buttons["onboarding.cards.continue"].tap()

        // The sample check runs on arrival: Checking (if still on screen), then the real first result.
        if app.descendants(matching: .any)["check.progress"].waitForExistence(timeout: 3) {
            shots.snap("onboarding-first-result-checking", settle: 0)
        }
        XCTAssertTrue(app.staticTexts["result.line1"].waitForExistence(timeout: 30), "the first result arrives")
        XCTAssertEqual(app.staticTexts["result.line1"].label, Expected.switchLine1)
        shots.snap("onboarding-first-result")
        app.buttons["onboarding.firstResult.continue"].tap()

        // The trigger step leads with the Back Tap prompt (owner request, Oct 16).
        let setUp = app.buttons["backTapPrompt.setUp"]
        XCTAssertTrue(setUp.waitForExistence(timeout: 5), "the Back Tap prompt")
        XCTAssertTrue(app.buttons["backTapPrompt.notNow"].exists)
        shots.snap("onboarding-backtap-prompt", settle: 1.2)
        setUp.tap()

        XCTAssertTrue(app.buttons["trigger.skip"].waitForExistence(timeout: 5))
        shots.snap("onboarding-set-up-back-tap")
        app.swipeUp()
        shots.snapIfScrolled("onboarding-set-up-back-tap-bottom")

        let tryIt = app.buttons["trigger.tryItNow"]
        XCTAssertTrue(app.scrollTo(tryIt), "Try it now")
        tryIt.tap()
        XCTAssertTrue(app.staticTexts["tryItNow.instruction"].waitForExistence(timeout: 5))
        shots.snap("onboarding-try-it-now")
        app.swipeUp()
        shots.snapIfScrolled("onboarding-try-it-now-bottom")
        app.goBack()

        let steps = app.buttons["trigger.shortcutSteps"]
        XCTAssertTrue(app.scrollTo(steps), "Show the steps")
        steps.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trigger.guide"].waitForExistence(timeout: 5))
        shots.snap("onboarding-shortcut-steps")
        // The sheet's own Done (the screen behind it has a Done button too).
        app.navigationBars.buttons["Done"].firstMatch.tap()
        let skip = app.buttons["trigger.skip"]
        XCTAssertTrue(app.scrollTo(skip))
        skip.tap()

        XCTAssertTrue(app.buttons["check.pickScreenshot"].waitForExistence(timeout: 5))
        shots.snap("check-idle")
        app.terminate()
    }

    // MARK: Check → Saved → Sent → Purchases (Check light, Purchases dark)

    @MainActor
    private func checkAndSave() {
        let app = Launch.app(["-resetState", "-skipOnboarding", "-dateOverride", Launch.purchaseDay, "-tab", "check"])
        let pick = app.buttons["check.pickScreenshot"]
        XCTAssertTrue(pick.waitForExistence(timeout: 10))
        pick.tap()
        let photo = app.newestPhoto
        XCTAssertTrue(photo.waitForExistence(timeout: 15), "the picker shows the laptop screenshot (simctl addmedia)")
        shots.snap("check-photo-picker")
        photo.tap()

        if app.descendants(matching: .any)["check.progress"].waitForExistence(timeout: 3) {
            shots.snap("check-checking", settle: 0)
        } else {
            print("PAYWISE_UI tour: Checking was gone before the screenshot")
        }
        let save = app.buttons["result.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["result.line1"].label, Expected.switchLine1)
        shots.snap("check-result-switch")

        save.tap()
        // Saved in the app: [What we sent] and [Done] side by side.
        XCTAssertTrue(app.buttons["result.done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["result.whatWeSent"].exists)
        shots.snap("check-saved")
        app.buttons["result.whatWeSent"].tap()
        XCTAssertTrue(app.staticTexts["result.sentText"].waitForExistence(timeout: 5))
        shots.snap("check-sent")

        app.buttons["check.whatWeSent"].tap()
        XCTAssertTrue(app.staticTexts["sent.text"].firstMatch.waitForExistence(timeout: 5))
        shots.snap("what-we-sent")
        app.goBack()

        // The in-app Done: back to the tab's start.
        let done = app.buttons["result.done"]
        XCTAssertTrue(app.scrollTo(done))
        done.tap()
        XCTAssertTrue(done.waitForAbsence(timeout: 5))
        shots.snap("check-idle-after-done")

        // §5.1 step 3: the setup is offered again after the 2nd in-app check.
        XCTAssertTrue(app.buttons["check.pickScreenshot"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["check.triggerSetup"].exists, "not offered after one check")
        app.buttons["check.pickScreenshot"].tap()
        XCTAssertTrue(app.newestPhoto.waitForExistence(timeout: 15))
        app.newestPhoto.tap()
        XCTAssertTrue(app.buttons["result.save"].waitForExistence(timeout: 10))
        let offer = app.buttons["check.triggerSetup"]
        XCTAssertTrue(app.scrollTo(offer), "Set Up Back Tap is offered after the 2nd check")
        shots.snap("check-second-check-setup-offer")

        app.tabBars.buttons["Purchases"].tap()
        let row = app.buttons.matching(identifier: "purchase.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, Expected.purchaseLine)
        shots.snap("purchases-list")
        row.tap()
        XCTAssertTrue(app.buttons["purchase.somethingHappened"].waitForExistence(timeout: 5))
        shots.snap("purchase-detail-planned")
        app.terminate()

        // Back at the Check tab's start on the next launch: the Back Tap prompt, offered once more (setup was never
        // done here). The prompt and the setup it opens follow the system appearance over the light tab.
        let again = Launch.app(["-tab", "check"])
        let setUp = again.buttons["backTapPrompt.setUp"]
        XCTAssertTrue(setUp.waitForExistence(timeout: 10), "the prompt after the 2nd check")
        shots.snap("check-backtap-prompt-again", settle: 1.2)
        setUp.tap()
        XCTAssertTrue(again.buttons["trigger.tryItNow"].waitForExistence(timeout: 5), "setup in a sheet")
        shots.snap("check-set-up-back-tap-sheet")
        again.terminate()
    }

    // MARK: The Back Tap prompt and Try it now (`-showBackTapPrompt`, `-forceReduceMotion`, `-simulateBackTap`)

    @MainActor
    private func backTapSetup() {
        let app = Launch.app(["-resetState", "-skipOnboarding", "-tab", "check", "-forceReduceMotion", "-showBackTapPrompt"])
        XCTAssertTrue(app.descendants(matching: .any)["backTapPrompt.still"].waitForExistence(timeout: 10), "Reduce Motion: still frames")
        XCTAssertEqual(
            app.descendants(matching: .any)["backTapPrompt.still"].label,
            "Illustration: a finger double-taps the back of an iPhone"
        )
        shots.snap("backtap-prompt-reduce-motion")
        app.terminate()

        // A press on Try it now (simulated: the real check on a render of the screen) → "Back Tap works ✓".
        let press = Launch.app(["-skipOnboarding", "-tab", "check", "-showBackTapPrompt", "-simulateBackTap"])
        let setUp = press.buttons["backTapPrompt.setUp"]
        XCTAssertTrue(setUp.waitForExistence(timeout: 10))
        setUp.tap()
        let tryIt = press.buttons["trigger.tryItNow"]
        XCTAssertTrue(press.scrollTo(tryIt))
        tryIt.tap()
        XCTAssertTrue(press.staticTexts["tryItNow.instruction"].waitForExistence(timeout: 5))
        let works = press.staticTexts["trigger.works"]
        XCTAssertTrue(works.waitForExistence(timeout: 25), "the press arrives: Back Tap works")
        XCTAssertEqual(works.label, "Back Tap works")
        shots.snap("try-it-now-works")
        press.buttons["tryItNow.done"].tap()
        XCTAssertTrue(press.buttons["check.pickScreenshot"].waitForExistence(timeout: 5), "Done closes the setup")
        press.terminate()

        // Confirmed: the prompt never shows again on its own, and the setup screen says it works.
        let after = Launch.app(["-tab", "settings"])
        let trigger = after.buttons["settings.trigger"]
        XCTAssertTrue(after.scrollTo(trigger))
        XCTAssertTrue(after.tap(trigger, until: after.buttons["trigger.done"]))
        XCTAssertTrue(after.staticTexts["trigger.works"].waitForExistence(timeout: 5))
        shots.snap("settings-set-up-back-tap-confirmed")
        after.terminate()
    }

    // MARK: The island's answers, as the Check tab shows them (`-checkState`, light)

    /// SPEC §6.3 lines 1 and 2 for each state on the demo wallet (Apple Card ••5678 default).
    private static let checkStates: [(state: String, line1: String, line2: String)] = [
        ("keepDefault", "✓ Keep Apple Card ••5678", "Best of your 3 cards here"),
        ("keepMethod", "✓ Apple Card: use Apple Pay", "3% ($5.40) with Apple Pay vs 1% typed"),
        ("keepItemsUnreadable", "✓ Keep Apple Card ••5678", "Couldn't read the items, so no switch"),
        ("noCheckoutOnDevice", "No checkout total found", "Nothing left your phone"),
        ("noCheckoutFromBackend", "No checkout total found", "Scroll to the total and press again"),
        ("alreadyPaid", "Already paid?", "Press on the checkout, before you pay"),
        ("couldntCheck", "Couldn't check this time", "No connection · press again"),
        ("tookTooLong", "Couldn't check this time", "Took too long · press again"),
    ]

    @MainActor
    private func checkStates() {
        for (state, line1, line2) in Self.checkStates {
            let app = Launch.app(["-skipOnboarding", "-tab", "check", "-checkState", state])
            let result = app.descendants(matching: .any)["check.result"].firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 10), "check state \(state)")
            let shown = app.staticTexts["result.line1"]
            if shown.exists {
                XCTAssertEqual(shown.label, line1, state)
                XCTAssertEqual(app.staticTexts["result.line2"].label, line2, state)
                XCTAssertFalse(app.buttons["result.save"].exists, "\(state) has no [Paying with …]")
            } else {
                // No record (nothing was sent): the island's lines in one element.
                XCTAssertTrue(result.label.contains(line1) || app.staticTexts[line1].exists, "\(state): \(result.label)")
            }
            shots.snap("check-\(state)")
            app.terminate()
        }
    }

    // MARK: Claim input and verdicts, 14 months later (dark)

    @MainActor
    private func claims() {
        let app = Launch.app(["-dateOverride", Launch.claimDay, "-tab", "purchases"])
        let row = app.buttons.matching(identifier: "purchase.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["purchase.somethingHappened"].waitForExistence(timeout: 5))
        app.buttons["purchase.somethingHappened"].tap()
        XCTAssertTrue(app.staticTexts["claim.paid.question"].waitForExistence(timeout: 5))
        shots.snap("claim-input")

        // [No, another card]: the wallet's other cards to pick from (not picked here).
        app.buttons["claim.paid.otherCard"].tap()
        XCTAssertTrue(app.buttons["claim.otherCard.wf-active-cash"].waitForExistence(timeout: 5))
        shots.snap("claim-input-another-card")

        // Case 1 ([Yes] puts the card back to Freedom).
        app.buttons["claim.paid.yes"].tap()
        app.buttons["claim.paidWith.card_full"].tap()
        app.buttons["claim.warranty.oneYear"].tap()
        let description = app.claimDescription
        description.tap()
        description.typeText(Expected.case1Text)
        shots.snap("claim-input-typing")
        app.dismissKeyboard()
        let failure = app.buttons["claim.cause.failure"]
        if !failure.waitForSelected(timeout: 12) { failure.tap() }
        shots.snap("claim-input-case1")
        app.buttons["claim.check"].tap()
        XCTAssertTrue(app.verdictWeb.waitForExistence(timeout: 25))
        XCTAssertTrue(app.verdictText(containing: "May be eligible", timeout: 15), app.verdictDump)
        shots.snap("verdict-case1-may-be-eligible")
        app.verdictWeb.swipeUp()
        shots.snapIfScrolled("verdict-case1-may-be-eligible-more")
        app.verdictWeb.swipeUp()
        shots.snapIfScrolled("verdict-case1-may-be-eligible-end")

        // Case 2, a fresh claim from the detail.
        app.goBack()
        XCTAssertTrue(app.buttons["claim.check"].waitForExistence(timeout: 5))
        app.goBack()
        XCTAssertTrue(app.buttons["purchase.somethingHappened"].waitForExistence(timeout: 5))
        shots.snap("purchase-detail-confirmed")
        app.buttons["purchase.somethingHappened"].tap()
        XCTAssertTrue(app.staticTexts["claim.paid.question"].waitForExistence(timeout: 5))
        app.buttons["claim.paid.yes"].tap()
        app.buttons["claim.paidWith.card_full"].tap()
        app.buttons["claim.warranty.oneYear"].tap()
        app.claimDescription.tap()
        app.claimDescription.typeText(Expected.case2Text)
        app.dismissKeyboard()
        let damage = app.buttons["claim.cause.accidental_damage"]
        damage.tap()
        XCTAssertTrue(damage.waitForSelected(timeout: 2))
        shots.snap("claim-input-case2")
        app.buttons["claim.check"].tap()
        XCTAssertTrue(app.verdictWeb.waitForExistence(timeout: 25))
        XCTAssertTrue(app.verdictText(containing: "Not covered", timeout: 15), app.verdictDump)
        shots.snap("verdict-case2-not-covered")
        app.verdictWeb.swipeUp()
        shots.snapIfScrolled("verdict-case2-not-covered-more")

        // Case 1 with [Don't know]: §5.5 uses 12 months and labels the result "assumed".
        app.goBack()
        XCTAssertTrue(app.buttons["claim.check"].waitForExistence(timeout: 5))
        app.goBack()
        XCTAssertTrue(app.buttons["purchase.somethingHappened"].waitForExistence(timeout: 5))
        app.buttons["purchase.somethingHappened"].tap()
        XCTAssertTrue(app.staticTexts["claim.paid.question"].waitForExistence(timeout: 5))
        app.buttons["claim.paid.yes"].tap()
        app.buttons["claim.paidWith.card_full"].tap()
        app.buttons["claim.warranty.unknown"].tap()
        app.claimDescription.tap()
        app.claimDescription.typeText(Expected.case1Text)
        app.dismissKeyboard()
        if !failure.waitForSelected(timeout: 12) { failure.tap() }
        XCTAssertTrue(failure.waitForSelected(timeout: 2))
        shots.snap("claim-input-dont-know")
        app.buttons["claim.check"].tap()
        XCTAssertTrue(app.verdictWeb.waitForExistence(timeout: 25))
        XCTAssertTrue(app.verdictText(containing: "May be eligible", timeout: 15), app.verdictDump)
        XCTAssertTrue(app.verdictText(containing: "Assumed", timeout: 2), "Don't know is labelled: \(app.verdictDump)")
        shots.snap("verdict-dont-know-assumed")

        // Delete: the context menu, then the confirmation. Cancelled, so the purchase stays.
        app.goBack()
        XCTAssertTrue(app.buttons["claim.check"].waitForExistence(timeout: 5))
        app.goBack()
        XCTAssertTrue(app.buttons["purchase.somethingHappened"].waitForExistence(timeout: 5))
        app.goBack()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1.2)
        let menuDelete = app.buttons["Delete purchase"].firstMatch
        XCTAssertTrue(menuDelete.waitForExistence(timeout: 5), "the row's context menu")
        shots.snap("purchases-delete-menu")
        menuDelete.tap()
        XCTAssertTrue(app.staticTexts["Delete this purchase?"].waitForExistence(timeout: 5), "the delete confirmation")
        shots.snap("purchases-delete-confirm")
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists && cancel.isHittable {
            cancel.tap()
        } else {
            // A dialog without its own Cancel closes on a tap outside it.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        }
        XCTAssertTrue(app.staticTexts["Delete this purchase?"].waitForAbsence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "purchase.row").count, 1, "cancelled: the purchase stays")
        app.terminate()
    }

    // MARK: Settings (follows the system appearance)

    @MainActor
    private func settings() {
        let app = Launch.app(["-tab", "settings"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        shots.snap("settings")
        for page in ["settings-more", "settings-privacy", "settings-end", "settings-end-2"] {
            app.swipeUp()
            shots.snapIfScrolled(page)
        }
        let wallet = app.buttons["settings.wallet"]
        XCTAssertTrue(app.scrollTo(wallet), "Settings › Your cards")
        XCTAssertTrue(app.tap(wallet, until: app.buttons["wallet.save"]))
        shots.snap("settings-wallet")
        app.goBack()

        let trigger = app.buttons["settings.trigger"]
        XCTAssertTrue(app.scrollTo(trigger), "Settings › Set Up Back Tap")
        let setupDone = app.buttons["trigger.done"]
        XCTAssertTrue(app.tap(trigger, until: setupDone))
        shots.snap("settings-set-up-back-tap")
        // A sheet, as from the Check tab: [Done] closes it.
        XCTAssertTrue(app.scrollTo(setupDone), "Set Up Back Tap › Done")
        setupDone.tap()
        XCTAssertTrue(setupDone.waitForAbsence(timeout: 5), "Done closes the setup sheet")

        let sent = app.buttons["settings.whatWeSent"]
        XCTAssertTrue(app.scrollTo(sent), "Settings › What we sent")
        XCTAssertTrue(app.tap(sent, until: app.staticTexts["sent.text"].firstMatch))
        shots.snap("settings-what-we-sent")
        app.goBack()

        // The tab bar after visiting the dark Purchases tab: Settings goes back to the system appearance.
        app.tabBars.buttons["Purchases"].tap()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        shots.snap("settings-after-purchases")
        app.terminate()
    }

    // MARK: Empty states

    @MainActor
    private func emptyStates() {
        let app = Launch.app(["-resetState", "-skipOnboarding", "-tab", "purchases"])
        XCTAssertTrue(app.descendants(matching: .any)["purchases.empty"].waitForExistence(timeout: 10))
        shots.snap("purchases-empty")
        app.tabBars.buttons["Check"].tap()
        app.buttons["check.whatWeSent"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["sent.empty"].waitForExistence(timeout: 5))
        shots.snap("what-we-sent-empty")
        app.terminate()
    }

    // MARK: Snippet states (`-gallery`, follows the system like the system-presented snippet)

    @MainActor
    private func gallery() {
        for state in [
            "result", "resultCashBest", "resultCash", "keepProtected", "saved", "savedEarbuds", "savedLongName", "sent",
            "notSetUp",
        ] {
            let app = Launch.app(["-gallery", state])
            XCTAssertTrue(app.staticTexts["Paywise"].firstMatch.waitForExistence(timeout: 10), "gallery \(state)")
            shots.snap("gallery-\(state)")
            app.terminate()
        }
    }
}

/// Numbered PNGs of the whole screen, written into the checkout and attached to the result bundle.
@MainActor
final class Shots {
    let dir: URL
    private(set) var count = 0
    private weak var testCase: XCTestCase?

    init(testCase: XCTestCase) {
        self.testCase = testCase
        let environment = ProcessInfo.processInfo.environment
        let label = environment["PAYWISE_SHOTS"].flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultLabel
        dir = Repo.root.appendingPathComponent("docs/overnight-shots/\(label)", isDirectory: true)
        let files = FileManager.default
        try? files.createDirectory(at: dir, withIntermediateDirectories: true)
        // A rerun replaces this tour's own numbered PNGs (NN-name.png), so no stale screen is left behind.
        for name in (try? files.contentsOfDirectory(atPath: dir.path)) ?? []
        where name.range(of: #"^\d\d-[A-Za-z0-9-]+\.png$"#, options: .regularExpression) != nil {
            try? files.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    private static var defaultLabel: String {
        let appearance = XCUIDevice.shared.appearance == .dark ? "dark" : "light"
        return "\(appearance)-default"
    }

    private var lastPNG: Data?

    /// Waits `settle` seconds for animations, then saves `NN-name.png`.
    func snap(_ name: String, settle: TimeInterval = 0.8) {
        if settle > 0 { Thread.sleep(forTimeInterval: settle) }
        let screenshot = XCUIScreen.main.screenshot()
        lastPNG = screenshot.pngRepresentation
        save(screenshot, name)
    }

    /// After a swipe: saves `NN-name.png` only if the screen changed (a page that already fits doesn't scroll).
    func snapIfScrolled(_ name: String) {
        Thread.sleep(forTimeInterval: 1.5)
        let screenshot = XCUIScreen.main.screenshot()
        let png = screenshot.pngRepresentation
        guard png != lastPNG else {
            print("PAYWISE_UI tour: \(name) skipped, the screen didn't scroll")
            return
        }
        lastPNG = png
        save(screenshot, name)
    }

    private func save(_ screenshot: XCUIScreenshot, _ name: String) {
        count += 1
        let file = dir.appendingPathComponent(String(format: "%02d-%@.png", count, name))
        do {
            try screenshot.pngRepresentation.write(to: file)
        } catch {
            XCTFail("couldn't write \(file.path): \(error)")
        }
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = String(format: "%02d-%@", count, name)
        attachment.lifetime = .keepAlways
        testCase?.add(attachment)
    }
}
