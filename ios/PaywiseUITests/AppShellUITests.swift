import XCTest

/// End-to-end UI tests against the LIVE backend (https://paywise-api-n0f9.onrender.com): SPEC finish-line item F6.
///
/// Before running, add the demo laptop checkout to the simulator's Photos so it is the newest photo:
///
///     xcrun simctl addmedia <udid> fixtures/screenshots/laptop-checkout.png
///
/// then run `ios/tools/run_ui_tour.sh` (adds the photo, warms Render, runs these and the screenshot tour), or:
///
///     xcodebuild -project ios/Paywise.xcodeproj -scheme Paywise \
///       -destination 'platform=iOS Simulator,name=Paywise Dev 18' -only-testing:PaywiseUITests/AppShellUITests test
///
/// The tests are in the Paywise scheme's test action, so a plain `test` runs them too (network needed); pick a suite
/// with `-only-testing:PaywiseTests` for the offline unit tests.
/// Launch arguments (debug builds): -resetState, -skipOnboarding, -dateOverride YYYY-MM-DD, -tab, -doubleSave.
final class AppShellUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// "Check a screenshot" → the newest photo → the exact §6.3 *Switch, protection* copy within 6 s of the pick.
    @MainActor
    func testCheckAScreenshotLive() throws {
        let app = Launch.app(["-resetState", "-skipOnboarding", "-tab", "check"])
        let picked = app.pickNewestPhoto()

        let line1 = app.staticTexts["result.line1"]
        let instruction = app.staticTexts["result.instruction"]
        XCTAssertTrue(line1.waitForExistence(timeout: 6), "a result within 6 s of the pick")
        XCTAssertTrue(instruction.waitForExistence(timeout: max(0.1, 6 - Date().timeIntervalSince(picked))))
        let elapsed = Date().timeIntervalSince(picked)
        print(String(format: "PAYWISE_UI testCheckAScreenshotLive: Switch copy on screen %.2f s after the pick", elapsed))
        XCTAssertLessThanOrEqual(elapsed, 6, "§6.3 copy within 6 s of the pick")

        XCTAssertEqual(line1.label, Expected.switchLine1)
        XCTAssertEqual(app.staticTexts["result.line2"].label, Expected.switchLine2)
        XCTAssertEqual(app.staticTexts["result.line3"].label, Expected.switchLine3)
        XCTAssertEqual(instruction.label, Expected.switchInstruction)
        XCTAssertEqual(app.buttons["result.save"].label, Expected.saveButton)
        attach(app, "switch")
    }

    /// [Paying with Freedom] with two saves racing on one check → *Saved* → Purchases shows exactly one row, the
    /// §15.7 step 12a line word for word, dated from the day the test runs (a check's `clientDate` is the phone's date).
    ///
    /// A synthesized double tap reaches a SwiftUI button as ONE action (checked: one save ran), so it can't show
    /// idempotency. `-doubleSave` makes the in-app button start two saves at once instead, and the app reports what
    /// each returned (`debug.saveOutcomes`): one "saved" and one "alreadySaved" prove the second save really ran and
    /// took the idempotent path. The unit tests race saves too (SavePurchaseTests
    /// `doubleTapRacingSavesExactlyOnePurchase`, InAppCheckTests `switchResultSavesOncePerDoubleTapAndShowsSent`);
    /// a double tap on the system snippet's button is the on-device check in §15.7 step 12a.
    @MainActor
    func testSaveIsIdempotent() throws {
        let app = Launch.app(["-resetState", "-skipOnboarding", "-tab", "check", "-doubleSave"])
        let checked = app.pickNewestPhoto()

        let save = app.buttons["result.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertEqual(save.label, Expected.saveButton)
        save.tap()

        let saved = app.descendants(matching: .any)["result.saved"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "the view reloads to Saved")
        XCTAssertTrue(saved.label.hasPrefix(Expected.savedLine1), "Saved line 1 is \(Expected.savedLine1); got \(saved.label)")
        print("PAYWISE_UI testSaveIsIdempotent: Saved reads \"\(saved.label)\"")
        attach(app, "saved")

        // Both saves ran: one made the purchase, the other found it.
        let outcomes = app.descendants(matching: .any)["debug.saveOutcomes"]
        XCTAssertTrue(outcomes.waitForExistence(timeout: 5), "-doubleSave reports the outcomes")
        let finished = NSPredicate(format: "label CONTAINS ','")
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: finished, object: outcomes)], timeout: 5)
        let results = outcomes.label.split(separator: ",").map(String.init).sorted()
        print("PAYWISE_UI testSaveIsIdempotent: the two saves returned \(outcomes.label)")
        XCTAssertEqual(results, ["alreadySaved", "saved"], "two saves ran on one check: one saved, one already saved")

        app.tabBars.buttons["Purchases"].tap()
        let rows = app.buttons.matching(identifier: "purchase.row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1, "two racing saves make one purchase")
        XCTAssertEqual(rows.firstMatch.label, Expected.purchaseLine(checkedOn: checked))
        attach(app, "purchases")

        // Read the store again from a fresh launch: a late second save would show here.
        app.terminate()
        let relaunched = Launch.app(["-tab", "purchases"])
        let again = relaunched.buttons.matching(identifier: "purchase.row")
        XCTAssertTrue(again.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(again.count, 1, "still one purchase after a relaunch")
        XCTAssertEqual(again.firstMatch.label, Expected.purchaseLine(checkedOn: checked))
        print("PAYWISE_UI testSaveIsIdempotent: \(again.count) row after relaunch: \"\(again.firstMatch.label)\"")
    }

    /// §15.4 claim cases 1 and 2 on "14 months later" (Dec 18, 2027 for the spec's Oct 17, 2026), from the S1 purchase
    /// checked and saved today through the live backend. The verdict is the backend's HTML in the in-app web view.
    @MainActor
    func testClaimCases1and2() throws {
        let checked = savePurchase()

        // 14 months later.
        let app = Launch.app(["-dateOverride", Launch.claimDay(after: checked), "-tab", "purchases"])
        let row = app.buttons.matching(identifier: "purchase.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["purchase.somethingHappened"].waitForExistence(timeout: 5))
        app.buttons["purchase.somethingHappened"].tap()

        // Case 1: "Lines across the screen. Never dropped." → May be eligible: Extended warranty.
        XCTAssertTrue(app.staticTexts["claim.paid.question"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["claim.paid.question"].label, Expected.paidQuestion(checkedOn: checked))
        fillClaim(app, text: Expected.case1Text, cause: "failure", acceptSuggestion: true)
        app.buttons["claim.check"].tap()
        XCTAssertTrue(app.verdictWeb.waitForExistence(timeout: 25), "the verdict web view opens")
        XCTAssertTrue(app.verdictText(containing: "May be eligible", timeout: 15), "case 1 verdict: \(app.verdictDump)")
        XCTAssertTrue(app.verdictText(containing: "Extended warranty", timeout: 2), "case 1 benefit: \(app.verdictDump)")
        print("PAYWISE_UI testClaimCases1and2 case 1: \(app.verdictDump.prefix(400))")
        attach(app, "case1")

        // Case 2: "Cracked it when I dropped it" + Dropped or damaged → Not covered. A fresh claim from the detail.
        app.goBack()
        XCTAssertTrue(app.buttons["claim.check"].waitForExistence(timeout: 5))
        app.goBack()
        XCTAssertTrue(app.buttons["purchase.somethingHappened"].waitForExistence(timeout: 5))
        app.buttons["purchase.somethingHappened"].tap()
        XCTAssertTrue(app.staticTexts["claim.paid.question"].waitForExistence(timeout: 5))
        fillClaim(app, text: Expected.case2Text, cause: "accidental_damage", acceptSuggestion: false)
        app.buttons["claim.check"].tap()
        XCTAssertTrue(app.verdictWeb.waitForExistence(timeout: 25))
        XCTAssertTrue(app.verdictText(containing: "Not covered", timeout: 15), "case 2 verdict: \(app.verdictDump)")
        XCTAssertFalse(app.verdictText(containing: "May be eligible", timeout: 0.5), "case 2 is not eligible")
        print("PAYWISE_UI testClaimCases1and2 case 2: \(app.verdictDump.prefix(400))")
        attach(app, "case2")
    }

    /// SPEC §5.5 payout cap (coverage case 12) on the live backend: [Part of it] with $1,000 of the $1,499 on the card
    /// → May be eligible: Extended warranty, with a $1,000.00 payout cap. An amount over the price shows the hint and
    /// keeps [Check] off.
    @MainActor
    func testPartialPaymentCapsThePayout() throws {
        let checked = savePurchase()

        let app = Launch.app(["-dateOverride", Launch.claimDay(after: checked), "-tab", "purchases"])
        let row = app.buttons.matching(identifier: "purchase.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["purchase.somethingHappened"].waitForExistence(timeout: 5))
        app.buttons["purchase.somethingHappened"].tap()
        XCTAssertTrue(app.staticTexts["claim.paid.question"].waitForExistence(timeout: 5))
        app.buttons["claim.paid.yes"].tap()

        app.buttons["claim.paidWith.card_partial"].tap()
        let amount = app.textFields["claim.paidWith.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 2), "[Part of it] shows the amount field")
        amount.tap()
        amount.typeText("2000")
        let hint = app.descendants(matching: .any)["claim.paidWith.amountHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 2), "an amount over the price shows the hint")
        XCTAssertFalse(app.buttons["claim.check"].isEnabled)
        attach(app, "partial-over-price")
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "1000")
        XCTAssertFalse(hint.waitForExistence(timeout: 1), "$1,000 is accepted")
        app.dismissKeyboard()

        app.buttons["claim.warranty.oneYear"].tap()
        let description = app.claimDescription
        description.tap()
        description.typeText(Expected.case1Text)
        app.dismissKeyboard()
        let failure = app.buttons["claim.cause.failure"]
        if !failure.waitForSelected(timeout: 12) { failure.tap() }
        XCTAssertTrue(failure.waitForSelected(timeout: 2))
        attach(app, "partial-input")
        app.buttons["claim.check"].tap()

        XCTAssertTrue(app.verdictWeb.waitForExistence(timeout: 25), "the verdict web view opens")
        XCTAssertTrue(app.verdictText(containing: "May be eligible", timeout: 15), "case 12 verdict: \(app.verdictDump)")
        XCTAssertTrue(app.verdictText(containing: "Payout cap", timeout: 2), "case 12 payout: \(app.verdictDump)")
        XCTAssertTrue(app.verdictText(containing: "$1,000.00", timeout: 2), "capped at the part on the card: \(app.verdictDump)")
        print("PAYWISE_UI testPartialPaymentCapsThePayout: \(app.verdictDump.prefix(600))")
        attach(app, "partial-verdict")
    }

    /// The S1 purchase: a live check and [Paying with Freedom], with "Pretend today is…" off, as the demo checks it
    /// (docs/overnight-report.md, morning checklist). Returns the moment of the pick: the check is dated that day.
    @MainActor
    private func savePurchase() -> Date {
        let setup = Launch.app(["-resetState", "-skipOnboarding", "-tab", "check"])
        let checked = setup.pickNewestPhoto()
        XCTAssertTrue(setup.buttons["result.save"].waitForExistence(timeout: 10))
        setup.buttons["result.save"].tap()
        XCTAssertTrue(setup.descendants(matching: .any)["result.saved"].waitForExistence(timeout: 5))
        setup.terminate()
        return checked
    }

    /// Yes → whole price → 1 year → the text → the cause chip. With `acceptSuggestion`, waits for the server's classification to
    /// pre-select `cause` and taps it only if it doesn't.
    @MainActor
    private func fillClaim(_ app: XCUIApplication, text: String, cause: String, acceptSuggestion: Bool) {
        app.buttons["claim.paid.yes"].tap()
        app.buttons["claim.paidWith.card_full"].tap()
        app.buttons["claim.warranty.oneYear"].tap()
        let description = app.claimDescription
        description.tap()
        description.typeText(text)
        app.dismissKeyboard()
        let chip = app.buttons["claim.cause.\(cause)"]
        if acceptSuggestion, chip.waitForSelected(timeout: 12) {
            print("PAYWISE_UI claim: the server pre-selected \(cause)")
        } else {
            chip.tap()
            print("PAYWISE_UI claim: picked \(cause)")
        }
        XCTAssertTrue(chip.waitForSelected(timeout: 2), "\(cause) is selected")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
