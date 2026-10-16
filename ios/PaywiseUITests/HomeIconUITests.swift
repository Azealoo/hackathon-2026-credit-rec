import UIKit
import XCTest

/// The app icon (logo 08 "Monoline") on the home screen, saved to docs/overnight-shots/brand/:
///
///     home-icon-light.png    appearance light, icon style Default: the standard icon
///     home-icon-dark.png     appearance dark, icon style Dark: the dark icon
///     home-icon-tinted.png   appearance dark, icon style Tinted: the tinted icon
///
/// each with a `-zoom.png` crop of the icon and its label. Set the appearance first
/// (`xcrun simctl ui <udid> appearance dark`); the test picks the icon style for it in the home screen's Customize
/// sheet (iOS 27's "Default" style keeps light icons in dark mode) and puts Default back when it ends.
/// `ios/tools/run_ui_tour.sh icon` runs it in both appearances. No network, no Photos.
final class HomeIconUITests: XCTestCase {
    @MainActor
    private var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeScreenIcon() throws {
        // Launch once so the freshly installed build is the one SpringBoard draws, then go home.
        let app = Launch.app(["-skipOnboarding"])
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCUIDevice.shared.press(.home)

        if XCUIDevice.shared.appearance == .dark {
            addTeardownBlock { @MainActor in self.setIconStyle("Default") }
            setIconStyle("Dark")
            try snapIcon("home-icon-dark")
            setIconStyle("Tinted")
            try snapIcon("home-icon-tinted")
        } else {
            setIconStyle("Default")
            try snapIcon("home-icon-light")
        }
    }

    /// Home screen → long-press an empty spot → Edit → Customize → `style` (Default, Dark, Clear or Tinted) → done.
    @MainActor
    private func setIconStyle(_ style: String) {
        let icon = paywiseIcon
        XCTAssertTrue(icon.waitForExistence(timeout: 10), "Paywise is on the home screen")
        showPage(of: icon)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).press(forDuration: 1.5)
        let edit = springboard.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "the home screen is in edit mode")
        edit.tap()
        let customize = springboard.buttons["Customize"]
        XCTAssertTrue(customize.waitForExistence(timeout: 5), "Edit shows Customize")
        customize.tap()
        let option = springboard.buttons[style]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Customize offers \(style)")
        option.tap()
        Thread.sleep(forTimeInterval: 1)
        // Close the sheet (tap above it), then leave edit mode.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        Thread.sleep(forTimeInterval: 1)
        let done = springboard.buttons["Done"]
        if done.exists && done.isHittable {
            done.tap()
        } else {
            XCUIDevice.shared.press(.home)
        }
        Thread.sleep(forTimeInterval: 1.5)
    }

    @MainActor
    private var paywiseIcon: XCUIElement { springboard.icons["Paywise"].firstMatch }

    /// Pages right until `icon` is on screen (a new app lands on a later page).
    @MainActor
    private func showPage(of icon: XCUIElement) {
        var swipes = 0
        while !icon.isHittable && swipes < 8 {
            springboard.swipeLeft()
            swipes += 1
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(icon.isHittable, "the Paywise icon is on screen after \(swipes) swipes")
    }

    /// Saves the whole screen as `<name>.png` and the icon with its label as `<name>-zoom.png`.
    @MainActor
    private func snapIcon(_ name: String) throws {
        let icon = paywiseIcon
        XCTAssertTrue(icon.waitForExistence(timeout: 10), "Paywise is on the home screen")
        showPage(of: icon)
        Thread.sleep(forTimeInterval: 1.5)

        let folder = Repo.root.appendingPathComponent("docs/overnight-shots/brand", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let screenshot = XCUIScreen.main.screenshot()
        try screenshot.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        // The icon with its label and a margin, at the screenshot's pixel scale.
        let image = screenshot.image
        let frame = icon.frame.insetBy(dx: -24, dy: -16)
        let pixels = CGRect(
            x: frame.minX * image.scale, y: frame.minY * image.scale,
            width: frame.width * image.scale, height: (frame.height + 22) * image.scale
        ).integral
        let cropped = try XCTUnwrap(image.cgImage?.cropping(to: pixels), "crop \(pixels) of the screenshot")
        let zoom = try XCTUnwrap(UIImage(cgImage: cropped).pngData())
        try zoom.write(to: folder.appendingPathComponent("\(name)-zoom.png"))
        print("PAYWISE_UI \(name): icon at \(icon.frame) → \(folder.path)")
    }
}
