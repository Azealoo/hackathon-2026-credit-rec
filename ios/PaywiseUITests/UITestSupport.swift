import XCTest

/// Shared pieces for the live UI tests and the screenshot tour.
///
/// Before a run, put the demo laptop checkout in the simulator's Photos (the picker shows the newest photo first):
///
///     xcrun simctl addmedia <udid> fixtures/screenshots/laptop-checkout.png
///
/// `ios/tools/run_ui_tour.sh` does that, warms the Render backend, and runs everything.
enum Expected {
    /// SPEC §6.3 *Switch, protection* on `demo-3card`: lines 1–3 and the instruction, exactly.
    static let switchLine1 = "Use Freedom ••1234"
    static let switchLine2 = "Adds a warranty year + $500 theft cover"
    static let switchLine3 = "$7.49 less cash back than Active Cash"
    static let switchInstruction = "Change card to Visa ••1234, then place order"
    static let saveButton = "Paying with Freedom"
    /// §6.3 *Saved* line 1.
    static let savedLine1 = "✓ Saved: Aero 14 · $1,499"
    /// §15.7 step 12a, word for word, for a purchase checked on Oct 17, 2026.
    static let purchaseLine =
        "Aero 14 · Freedom ••1234 · Planned · theft & damage up to $500 to Feb 14, 2027 · warranty year to Oct 17, 2028"
    /// §5.5 claim input, question 1.
    static let paidQuestion = "Did you pay with Freedom ••1234 on Oct 17?"
    static let case1Text = "Lines across the screen. Never dropped."
    static let case2Text = "Cracked it when I dropped it"
}

enum Launch {
    /// The day the S1 purchase is checked and saved (SPEC §5.5's "laptop bought Oct 17, 2026").
    static let purchaseDay = "2026-10-17"
    /// "14 months later" (SPEC §12.1): the claim demo's day.
    static let claimDay = "2027-12-18"

    @MainActor
    static func app(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }
}

extension XCUIApplication {
    /// "Check a screenshot" → the newest photo in the PhotosPicker. Returns the moment of the pick.
    ///
    /// The out-of-process picker's grid is reachable from the app's own element tree (iOS 17+). Its cells are images
    /// identified `PXGGridLayout-Info`, labelled "Photo, <date>", newest date first (seen on iOS 27: "Photo, October 15,
    /// 14:17" ahead of the simulator's 2009–2018 samples). `simctl addmedia` dates a PNG by its file's modification
    /// time, so the laptop checkout is the newest unless the library has a later photo; run_ui_tour.sh adds a copy
    /// dated now.
    @MainActor
    @discardableResult
    func pickNewestPhoto(file: StaticString = #filePath, line: UInt = #line) -> Date {
        let pick = buttons["check.pickScreenshot"]
        XCTAssertTrue(pick.waitForExistence(timeout: 10), "Check tab shows Check a screenshot", file: file, line: line)
        pick.tap()
        let photo = newestPhoto
        XCTAssertTrue(
            photo.waitForExistence(timeout: 15),
            "the picker shows the laptop screenshot (run xcrun simctl addmedia first)", file: file, line: line
        )
        print("PAYWISE_UI picked the newest photo: \(photo.label)")
        photo.tap()
        return Date()
    }

    /// The picker's first grid cell: the newest photo.
    var newestPhoto: XCUIElement {
        images.matching(identifier: "PXGGridLayout-Info").firstMatch
    }

    /// The claim's free-text field (a vertical-axis TextField: a text view on some iOS versions).
    var claimDescription: XCUIElement {
        let field = textFields["claim.description"]
        return field.exists ? field : textViews["claim.description"]
    }

    /// The web view showing the HTML verdict.
    var verdictWeb: XCUIElement { webViews["verdict.web"] }

    /// Waits for text in the verdict web view (`app.webViews.staticTexts`).
    @MainActor
    func verdictText(containing text: String, timeout: TimeInterval) -> Bool {
        verdictWeb.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
            .waitForExistence(timeout: timeout)
    }

    /// Every static text in the verdict web view, joined, for failure messages.
    @MainActor
    var verdictDump: String {
        verdictWeb.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
    }

    /// Swipes until `element` is on screen, down the page first, then back up (lists build their rows lazily, so an
    /// off-screen row doesn't exist yet).
    @MainActor
    @discardableResult
    func scrollTo(_ element: XCUIElement, maxSwipes: Int = 6) -> Bool {
        for down in [true, false] {
            for _ in 0..<maxSwipes {
                if element.exists && element.isHittable { return true }
                if down { swipeUp() } else { swipeDown() }
                // Let the scroll come to rest: a tap on a list that is still moving only stops it.
                Thread.sleep(forTimeInterval: 1)
            }
        }
        return element.exists && element.isHittable
    }

    /// Taps `element` until `destination` appears (a second tap if the first only stopped a scroll), then waits.
    @MainActor
    @discardableResult
    func tap(_ element: XCUIElement, until destination: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        element.tap()
        if destination.waitForExistence(timeout: 2) { return true }
        if element.exists && element.isHittable { element.tap() }
        return destination.waitForExistence(timeout: timeout)
    }

    /// The navigation bar's back button (the first button in the bar).
    @MainActor
    func goBack() {
        navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// Dismisses the keyboard with the keyboard toolbar's Done, if the keyboard is up.
    @MainActor
    func dismissKeyboard() {
        guard keyboards.firstMatch.exists else { return }
        let done = buttons["Done"].firstMatch
        if done.exists { done.tap() }
    }
}

extension XCUIElement {
    /// Waits until the element exists and is selected (a chip the server pre-selected).
    func waitForSelected(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if exists && isSelected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }

    /// Waits until the element is gone.
    func waitForAbsence(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return !exists
    }
}

/// The repo root, from this file's path (ios/PaywiseUITests/UITestSupport.swift). The simulator's test runner runs on
/// the Mac, so it can write into the checkout.
enum Repo {
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // PaywiseUITests
        .deletingLastPathComponent()  // ios
        .deletingLastPathComponent()  // repo root
}
