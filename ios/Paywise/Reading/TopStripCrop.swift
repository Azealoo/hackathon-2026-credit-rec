import CoreGraphics
import Foundation

/// Cuts the status-bar strip off the top of a screenshot before anything reads it (SPEC §10, §15.7 step 8),
/// so the time, carrier, signal and battery never reach OCR.
enum TopStripCrop {
    /// TOP_CROP_PT. On a 393-pt iPhone with a Dynamic Island the status bar ends at about 54 pt; 62 pt leaves a margin
    /// and still sits above the demo store's header, which starts below 80 pt (§15.7 step 5).
    static let topCropPoints = 62

    /// Screen scale guessed from the screenshot's short side: 1080 px and wider (1125, 1170, 1179, 1206, 1290, …) is @3x,
    /// 640–1079 px (750, 828) is @2x. Guessing too high only crops a little more.
    static func scale(pixelWidth: Int, pixelHeight: Int) -> Int {
        let shortSide = min(pixelWidth, pixelHeight)
        if shortSide >= 1080 { return 3 }
        if shortSide >= 640 { return 2 }
        return 1
    }

    /// Pixel rows removed from the top.
    static func cropPixels(pixelWidth: Int, pixelHeight: Int) -> Int {
        topCropPoints * scale(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    /// The rectangle that is kept, in the image's pixel space (origin at the top-left, as `CGImage.cropping(to:)` uses).
    static func keptRect(pixelWidth: Int, pixelHeight: Int) -> CGRect? {
        let cut = cropPixels(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        guard pixelWidth > 0, pixelHeight > cut else { return nil }
        return CGRect(x: 0, y: cut, width: pixelWidth, height: pixelHeight - cut)
    }

    /// The screenshot without its top strip, or nil if the image is too small to hold anything below the strip.
    static func crop(_ image: CGImage) -> CGImage? {
        guard let rect = keptRect(pixelWidth: image.width, pixelHeight: image.height) else { return nil }
        return image.cropping(to: rect)
    }
}
