import XCTest

/// Gates G1/G2 on a real iPhone (SPEC §14.2, §15.7 steps 6–7, 12a): the Action Button runs the "Paywise"
/// Shortcut over the demo store's laptop checkout in Safari, and we count what happens.
///
/// Needs: the iPhone unlocked with UI Automation on (Settings › Developer), the Paywise Shortcut bound to the
/// Action Button, and one practice press done (it clears Shortcuts' first-run prompts). Device only; skipped on the
/// simulator, which has no Action Button. Run with:
///
///     xcodebuild -project Paywise.xcodeproj -scheme Paywise -destination 'id=<UDID>' \
///       -allowProvisioningUpdates -only-testing:PaywiseUITests/DevicePressUITests test
///
/// Prints one `PAYWISE_PRESS` line per press and a `PAYWISE_PRESS_SUMMARY` line; screenshots are attached to the
/// xcresult. It doesn't fail on a missed press (the gate counts misses); it fails only if no press worked at all.
final class DevicePressUITests: XCTestCase {
    private static let storeURL = URL(string: "https://paywise-store.onrender.com/checkout.html?item=laptop")!
    private static let presses = 10

    @MainActor private var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }
    @MainActor private var safari: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.mobilesafari") }

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testActionButtonPressesOverTheDemoStore() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("The Action Button exists only on a device.")
        #else
        // The demo wallet (Apple Card ••5678 default, Active Cash ••4321, Freedom ••1234) gives the §6.3 Switch copy.
        let app = Launch.app(["-skipOnboarding"])
        let before = purchaseCount(app)
        print("PAYWISE_PRESS purchases before: \(before)")

        var snippets = 0, saves = 0, islandClear = 0
        var times: [Double] = []
        for press in 1...Self.presses {
            openStore()
            let start = Date()
            XCUIDevice.shared.press(.action)
            let line1 = waitForText(Expected.switchLine1, timeout: 15)
            let elapsed = Date().timeIntervalSince(start)
            snap("press-\(press)-after")
            guard let line1 else {
                print("PAYWISE_PRESS \(press): no Switch snippet within 15 s")
                dismissAnything()
                continue
            }
            snippets += 1
            times.append(elapsed)
            let host = line1.host
            let rest = [Expected.switchLine2, Expected.switchLine3].allSatisfy { host.staticTexts[$0].exists }
            print(String(format: "PAYWISE_PRESS %d: snippet in %.2f s (lines 2–3 exact: %@, in %@)",
                         press, elapsed, rest ? "yes" : "no", line1.name))

            let save = host.buttons[Expected.saveButton]
            if save.waitForExistence(timeout: 3) {
                if press == 1 { save.doubleTap() } else { save.tap() }
                if host.staticTexts[Expected.savedLine1].waitForExistence(timeout: 8) {
                    saves += 1
                    print("PAYWISE_PRESS \(press): \(press == 1 ? "double tap → " : "")Saved")
                } else {
                    print("PAYWISE_PRESS \(press): tapped [\(Expected.saveButton)], no Saved view within 8 s")
                }
                snap("press-\(press)-saved")
            } else {
                print("PAYWISE_PRESS \(press): no [\(Expected.saveButton)] button in the snippet")
            }
            dismissAnything()
            // §6.2: the intent ends its Live Activity before returning, so the island should be empty after Done.
            Thread.sleep(forTimeInterval: 3)
            if !springboard.staticTexts["Reading this screen…"].exists { islandClear += 1 }
        }

        app.activate()
        let after = purchaseCount(app)
        let sorted = times.sorted()
        let p50 = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        print(String(
            format: "PAYWISE_PRESS_SUMMARY presses=%d snippets=%d saves=%d purchasesAdded=%d (expected %d) islandClearAfterDone=%d p50=%.2fs max=%.2fs",
            Self.presses, snippets, saves, after - before, saves, islandClear, p50, sorted.last ?? 0))
        XCTAssertGreaterThan(snippets, 0, "at least one press showed the Switch snippet")
        #endif
    }

    /// Assisted run: XCUITest can only tap the Action Button (no press-and-hold), so a person presses and holds it
    /// each time the laptop checkout is on screen; the test watches for the result, saves, dismisses and reloads.
    /// Presses 1–8 are on the laptop checkout (expect the §6.3 Switch snippet; press 1 double-taps the save);
    /// presses 9–10 are on the store's social-feed page (expect the island's "No checkout total found").
    @MainActor
    func testAssistedPresses() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("The Action Button exists only on a device.")
        #else
        let app = Launch.app(["-skipOnboarding"])
        let before = purchaseCount(app)
        print("PAYWISE_PRESS purchases before: \(before)")
        var snippets = 0, saves = 0, feedAlerts = 0, islandClear = 0
        for press in 1...10 {
            let feed = press > 8
            openStore(feed ? URL(string: "https://paywise-store.onrender.com/feed.html")! : Self.storeURL)
            print("PAYWISE_PRESS \(press): READY — trigger Paywise: double-tap the back or hold the Action Button (\(feed ? "feed" : "checkout"))")
            if feed {
                if waitForText("No checkout total found", timeout: 45) != nil {
                    feedAlerts += 1
                    print("PAYWISE_PRESS \(press): island shows No checkout total found")
                } else {
                    print("PAYWISE_PRESS \(press): no No-checkout alert within 45 s")
                }
                snap("assisted-\(press)-feed")
                Thread.sleep(forTimeInterval: 6)
                continue
            }
            guard let line1 = waitForText(Expected.switchLine1, timeout: 45) else {
                print("PAYWISE_PRESS \(press): no Switch snippet within 45 s")
                snap("assisted-\(press)-none")
                dismissAnything()
                continue
            }
            snippets += 1
            let host = line1.host
            let rest = [Expected.switchLine2, Expected.switchLine3].allSatisfy { host.staticTexts[$0].exists }
            print("PAYWISE_PRESS \(press): Switch snippet (lines 2–3 exact: \(rest ? "yes" : "no"), in \(line1.name))")
            snap("assisted-\(press)-snippet")
            let save = host.buttons[Expected.saveButton]
            if save.waitForExistence(timeout: 3) {
                if press == 1 { save.doubleTap() } else { save.tap() }
                if host.staticTexts[Expected.savedLine1].waitForExistence(timeout: 8) {
                    saves += 1
                    print("PAYWISE_PRESS \(press): \(press == 1 ? "double tap → " : "")Saved")
                } else {
                    print("PAYWISE_PRESS \(press): tapped [\(Expected.saveButton)], no Saved view within 8 s")
                }
                snap("assisted-\(press)-saved")
            } else {
                print("PAYWISE_PRESS \(press): no [\(Expected.saveButton)] button found in the snippet")
            }
            dismissAnything()
            Thread.sleep(forTimeInterval: 3)
            if !springboard.staticTexts["Reading this screen…"].exists { islandClear += 1 }
        }
        let after = purchaseCount(app)
        print("PAYWISE_PRESS_SUMMARY assisted checkoutPresses=8 snippets=\(snippets) saves=\(saves) purchasesAdded=\(after - before) (expected \(saves)) feedAlerts=\(feedAlerts)/2 islandClearAfterDone=\(islandClear)")
        #endif
    }

    // MARK: - Helpers

    @MainActor
    private func openStore(_ url: URL = DevicePressUITests.storeURL) {
        safari.open(url)
        _ = safari.wait(for: .runningForeground, timeout: 10)
        let marker = safari.webViews.descendants(matching: .any)[url.path.hasSuffix("feed.html") ? "Northbay Electronics" : "Place order"]
        if !marker.waitForExistence(timeout: 20) { print("PAYWISE_PRESS store page didn't finish loading") }
        Thread.sleep(forTimeInterval: 1)
    }

    /// The snippet is drawn by the system, so look in SpringBoard first, then Safari and Paywise.
    @MainActor
    private func waitForText(_ text: String, timeout: TimeInterval) -> (element: XCUIElement, host: XCUIApplication, name: String)? {
        let hosts = [("SpringBoard", springboard), ("Safari", safari), ("Paywise", XCUIApplication())]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for (name, host) in hosts {
                let element = host.staticTexts[text]
                if element.exists { return (element, host, name) }
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return nil
    }

    @MainActor
    private func dismissAnything() {
        for host in [springboard, safari] where host.buttons["Done"].exists {
            host.buttons["Done"].tap()
            return
        }
    }

    @MainActor
    private func purchaseCount(_ app: XCUIApplication) -> Int {
        app.activate()
        let tab = app.buttons["tab.purchases"]
        if tab.waitForExistence(timeout: 10) { tab.tap() }
        Thread.sleep(forTimeInterval: 1)
        return app.buttons.matching(identifier: "purchase.row").count
    }

    @MainActor
    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
