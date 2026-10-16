import CoreGraphics
import Foundation

/// One piece of recognised text and where it sits on the (cropped) screen.
struct OCRFragment: Sendable, Equatable {
    var text: String
    /// Normalised 0...1 box with the origin at the top-left.
    var box: CGRect
    var confidence: Double
}

/// Puts OCR fragments into reading order: rows top to bottom, fragments in a row left to right, joined with two
/// spaces ("Total  $1,499.00"), the same shape as `screen.ocrText` in contracts/check.request.example.json.
enum ReadingOrder {
    static let columnSeparator = "  "

    static func lines(_ fragments: [OCRFragment]) -> [String] {
        let sorted = fragments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.box.midY < $1.box.midY }

        var rows: [[OCRFragment]] = []
        for fragment in sorted {
            // Same row when the vertical centres are closer than half the shorter fragment's height.
            if let lastRow = rows.last, let anchor = lastRow.first,
               abs(fragment.box.midY - anchor.box.midY) < 0.5 * min(fragment.box.height, anchor.box.height) {
                rows[rows.count - 1].append(fragment)
            } else {
                rows.append([fragment])
            }
        }

        return rows.flatMap { row -> [String] in
            let joined = row
                .sorted { $0.box.minX < $1.box.minX }
                .map { $0.text.trimmingCharacters(in: .whitespaces) }
                .joined(separator: columnSeparator)
            // A fragment that already holds several lines keeps them as separate lines.
            return joined.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }

    /// Mean confidence of the fragments, 0 when there are none.
    static func meanConfidence(_ fragments: [OCRFragment]) -> Double {
        guard !fragments.isEmpty else { return 0 }
        return fragments.map(\.confidence).reduce(0, +) / Double(fragments.count)
    }
}
