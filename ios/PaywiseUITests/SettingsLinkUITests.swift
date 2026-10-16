import XCTest

/// Which Settings link reaches Accessibility › Touch › Back Tap on this iPhone? There is no public API for it
/// (only UIApplication.openSettingsURLString, which opens Paywise's own page). Seen on iOS 27 (Oct 16):
/// `settings-navigation://` and `prefs:` are refused to third-party callers (LSApplicationWorkspace error 115);
/// `App-prefs:` opens Settings. Each test opens one candidate and records where Settings lands. Device only.
final class SettingsLinkUITests: XCTestCase {
    @MainActor func testLink1() throws { try probe("App-prefs:com.apple.Settings.Accessibility/TOUCH_REACHABILITY_TITLE/BACK_TAP") }
    @MainActor func testLink2() throws { try probe("App-prefs:root=ACCESSIBILITY&path=TOUCH_REACHABILITY_TITLE/BACK_TAP") }
    @MainActor func testLink3() throws { try probe("App-prefs:ACCESSIBILITY") }
    @MainActor func testLink4() throws { try probe("App-prefs:root=ACCESSIBILITY") }

    @MainActor
    private func probe(_ link: String) throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Back Tap exists only on a device.")
        #else
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.terminate()
        XCUIDevice.shared.system.open(URL(string: link)!)
        let opened = settings.wait(for: .runningForeground, timeout: 6)
        Thread.sleep(forTimeInterval: 2)
        let title = opened ? settings.navigationBars.firstMatch.identifier : "(Settings didn't open)"
        let backTapPage = settings.staticTexts["Double Tap"].exists && settings.staticTexts["Triple Tap"].exists
        print("PAYWISE_LINK \(link) → title=\(title.isEmpty ? "(none)" : title) backTapPage=\(backTapPage)")
        #endif
    }
}
