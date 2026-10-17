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
    /// §15.7 step 12a, word for word, for a purchase checked on `day`. A check's `clientDate` is the phone's real date
    /// (never `-dateOverride`), and the backend dates the cover from it: theft & damage for 120 days, the warranty year
    /// to 24 months (the assumed 12-month maker's warranty + Freedom's 12). Checked on Oct 17, 2026 (SPEC §5.5), it reads
    /// "Aero 14 · Freedom ••1234 · Planned · theft & damage up to $500 to Feb 14, 2027 · warranty year to Oct 17, 2028".
    static func purchaseLine(checkedOn day: Date) -> String {
        let theft = TestDay.medium(TestDay.adding(days: 120, to: day))
        let warranty = TestDay.medium(TestDay.adding(months: 24, to: day))
        return "Aero 14 · Freedom ••1234 · Planned · theft & damage up to $500 to \(theft) · warranty year to \(warranty)"
    }
    /// §5.5 claim input, question 1, for a purchase checked on `day` ("… on Oct 17?" for Oct 17).
    static func paidQuestion(checkedOn day: Date) -> String {
        "Did you pay with Freedom ••1234 on \(TestDay.monthDay(day))?"
    }
    static let case1Text = "Lines across the screen. Never dropped."
    static let case2Text = "Cracked it when I dropped it"
}

enum Launch {
    /// "14 months later" (SPEC §12.1) than a purchase checked on `day`, for `-dateOverride`: the claim demo's day,
    /// after the 120-day theft & damage cover and inside the extra warranty year (months 12–24). A purchase checked
    /// on Oct 17, 2026 gives the spec's 2027-12-18.
    static func claimDay(after day: Date) -> String {
        TestDay.string(TestDay.adding(days: 1, to: TestDay.adding(months: 14, to: day)))
    }

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

/// Calendar days in the simulator's time zone (the test runner's and the app's), written as the app writes them.
enum TestDay {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// Noon on `date`'s day, `months` then `days` later. Months clamp to the month's last day, as the backend's
    /// add_months does (Jan 31 + 1 month = Feb 28 or 29); noon, so a DST change never moves the day.
    static func adding(days: Int = 0, months: Int = 0, to date: Date) -> Date {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
        let shifted = calendar.date(byAdding: .month, value: months, to: noon)!
        return calendar.date(byAdding: .day, value: days, to: shifted)!
    }

    /// yyyy-MM-dd, as `-dateOverride` takes it.
    static func string(_ date: Date) -> String { format(date, "yyyy-MM-dd") }

    /// "Feb 14, 2027" (§15.7 step 12a).
    static func medium(_ date: Date) -> String { format(date, "MMM d, yyyy") }

    /// "Oct 17" (§5.5).
    static func monthDay(_ date: Date) -> String { format(date, "MMM d") }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
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
