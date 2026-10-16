import Foundation

/// The last check before anything leaves the phone (SPEC §9.2, §10, §15.7 step 8).
///
/// On-device redaction in the screen reader does the real work. This backstop holds, whatever the reader returned:
/// - the OCR text sent carries no card number and no last 4 (`scrub`), and
/// - the whole request body passes the backend's privacy rule (`isSendable`; backend/app/middleware.py
///   `body_is_private`: no run of 12+ digits anywhere, no card-shaped number), so a press never ends on the
///   backend's 400 privacy_rejected.
enum PrivacyGuard {
    /// The longest digit run the backend accepts (§9.2 rejects 12 or more).
    static let maxDigitRun = 11
    static let cardToken = "[CARD]"
    static let cardRedaction = "card_number"

    // MARK: Whole body

    /// Whether the encoded `/v1/check` body may be sent: valid UTF-8, no run of 12+ digits anywhere (the requestId
    /// included, as the backend reads every byte) and no card-shaped or Luhn-valid separated number.
    static func isSendable(_ body: Data) -> Bool {
        guard !body.isEmpty, let text = String(data: body, encoding: .utf8) else { return false }
        return longestDigitRun(text) <= maxDigitRun && !containsCardNumber(asciiDigits(text))
    }

    /// The longest run of decimal digits. Counts every Unicode decimal digit, as the backend's Python `\d` does.
    static func longestDigitRun(_ text: String) -> Int {
        var longest = 0
        var run = 0
        for scalar in text.unicodeScalars {
            if scalar.properties.numericType == .decimal {
                run += 1
                longest = max(longest, run)
            } else {
                run = 0
            }
        }
        return longest
    }

    /// Whether `text` holds a separated number the backend (or this guard) treats as a card number.
    static func containsCardNumber(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return separatedRun.matches(in: text, range: range).contains { match in
            Range(match.range, in: text).map { isCardNumber(String(text[$0])) } ?? false
        }
    }

    // MARK: OCR text

    /// The OCR text as it may leave the phone, and the redaction kinds (adds "card_number" when this removed any).
    ///
    /// Each of these becomes `[CARD]` (§10's example sends "Mastercard [CARD]"):
    /// 1. any run of 12+ digits (§9.2);
    /// 2. a separated 13–19 digit number that is card-shaped (4-4-4-4, 4-6-5) or Luhn-valid (§15.7 step 8), also when
    ///    OCR read a few of its digits as look-alike letters ("4111 1111 l111 1111", "5105 105| 0510 5100");
    /// 3. "ending in dddd" (§15.7 step 8);
    /// 4. a masked last 4: "••5678", "•••• 1234", "**1234", "..1234", "…1234", "XXXX-1234", and misread masks
    ///    "#### 4321", "°°°° 5678", "---- 4321", "oooo 5678";
    /// 5. 4 digits right after a network or card word: "Visa 4321", "Mastercard: 5678";
    /// 6. one of the wallet's own last 4 within a few characters of a card word or a card name from cards.json.
    /// Invisible format characters are dropped and other control characters become spaces first, since the JSON
    /// encoder writes controls as `\u00XX` escapes whose digits could join a run in the body.
    static func scrub(
        _ reading: ScreenReading, walletLast4: [String] = [], cardNames: [String] = []
    ) -> (text: String, redactions: [String]) {
        let start = plain(reading.redactedText)
        var text = start
        text = replaceAll(longRun, in: text)
        // Before the digits-only rule, so a misread last group ("… 1111 111I") goes whole, letter included.
        text = replaceLookalikeCardNumbers(in: text)
        text = replaceMatches(separatedRun, in: text) { isCardNumber($0) }
        text = replaceAll(endingIn, in: text)
        text = replaceAll(maskedLast4, in: text)

        let words = (networkWords + cardNames.map(NSRegularExpression.escapedPattern(for:)))
            .filter { !$0.isEmpty }
            .joined(separator: "|")
        if let afterWord = try? NSRegularExpression(
            pattern: #"(?i)\b(?:"# + words + #")\b[ \u00A0\t:#()\-\u2013]*([0-9]{4})(?![0-9])(?![.,][0-9])"#
        ) {
            text = replaceGroup(afterWord, in: text)
        }
        let last4 = walletLast4.filter { $0.count == 4 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }
        if !last4.isEmpty, let nearWord = try? NSRegularExpression(
            pattern: #"(?i)\b(?:"# + words + #")\b[^0-9$]{0,16}?("# + last4.joined(separator: "|")
                + #")(?![0-9])(?![.,][0-9])"#
        ) {
            text = replaceGroup(nearWord, in: text)
        }

        var redactions = reading.redactions
        if text != start, !redactions.contains(cardRedaction) {
            redactions.append(cardRedaction)
        }
        return (text, redactions)
    }

    // MARK: Patterns

    private static let longRun = regex("[0-9]{12,}")
    /// Digits split by single spaces or hyphens, 13 or more digits in all (the backend's `_SEPARATED_RUN`, plus the
    /// no-break and thin spaces and the en dash a screen may use).
    private static let separatedRun = regex(#"[0-9](?:[ \u00A0\u2009\u202F\-\u2013]?[0-9]){12,}"#)
    private static let endingIn = regex(#"(?i)\b(?:ending|ends)(?:\s+(?:in|with))?\s*[:#\-]?\s*[0-9]{4}(?![0-9])"#)
    private static let maskedLast4 = regex(
        #"(?:[\u2022\u25CF\u2219]+|\u00B7{2,}|\.{2,}|\u2026|\*+|#{2,}|\u00B0{2,}|[\-\u2013\u2014_]{2,}|(?<![A-Za-z])[xX]{2,}|(?<![A-Za-z])[oO]{3,4})"#
            + #"[ \u00A0\-]?[0-9]{4}(?![0-9])(?![.,][0-9])"#
    )
    /// Digit groups in which some digits may be OCR look-alike letters, single or double separators between groups.
    private static let lookalikeRun = regex(
        #"(?<![A-Za-z0-9])[0-9OolISBZ|!]+(?:[ \u00A0\u2009\u202F\-\u2013]{1,2}[0-9OolISBZ|!]+)*(?![A-Za-z0-9])"#
    )
    /// The letters OCR reads for digits in some fonts (the Redactor maps the same set).
    private static let lookalikeDigits: [Character: Character] = [
        "O": "0", "o": "0", "l": "1", "I": "1", "|": "1", "!": "1", "S": "5", "B": "8", "Z": "2",
    ]
    /// Payment networks and generic card words (not card data: names of cards come from cards.json).
    private static let networkWords = [
        "visa", "master ?card", "amex", "american express", "discover", "debit", "credit", "card",
    ]

    private static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("Bad privacy pattern \(pattern): \(error)")
        }
    }

    // MARK: Card numbers

    /// A separated run that is, as a whole, a Luhn-valid 13–19 digit number, or that holds an aligned window of
    /// 13–19 digits shaped like a typed card number (4-4-4-1…4 or 4-6-5 / 4-6-4), Luhn-valid or not (an OCR misread
    /// of one digit must not let the other 15 through). The backend rejects only windows that are both.
    private static func isCardNumber(_ run: String) -> Bool {
        let groups = run.split(whereSeparator: { !$0.isASCII || !$0.isNumber }).map(String.init)
        let all = groups.joined()
        if (13...19).contains(all.count), luhnValid(all) { return true }
        for start in groups.indices {
            var count = 0
            for end in start..<groups.count {
                count += groups[end].count
                if count > 19 { break }
                if count >= 13, isCardShaped(groups[start...end].map(\.count)) { return true }
            }
        }
        return false
    }

    /// Replaces each run of digit groups that holds a look-alike letter and, with the letters read as digits, is a
    /// card number (`isCardNumber`) with at least 9 real digits. A group without a real digit ("So", "BOSS", "llll")
    /// is part of a run only between two groups with one, or at the end of a run of 12+ characters, so words next to a
    /// shorter number stay.
    private static func replaceLookalikeCardNumbers(in text: String) -> String {
        func isASCIIDigit(_ character: Character) -> Bool { character.isASCII && character.isNumber }
        var ranges: [NSRange] = []
        for match in lookalikeRun.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let matchRange = Range(match.range, in: text) else { continue }
            // The match's groups, split at the separators.
            var groups: [Range<String.Index>] = []
            var groupStart: String.Index?
            var index = matchRange.lowerBound
            while index < matchRange.upperBound {
                let isGroupCharacter = isASCIIDigit(text[index]) || lookalikeDigits[text[index]] != nil
                if isGroupCharacter, groupStart == nil { groupStart = index }
                if !isGroupCharacter, let start = groupStart {
                    groups.append(start..<index)
                    groupStart = nil
                }
                index = text.index(after: index)
            }
            if let start = groupStart { groups.append(start..<matchRange.upperBound) }

            // Runs of consecutive groups: a group with a real digit always joins; a group of letters only joins
            // between two groups with a digit ("4111 1111 llll 1111"), or, 3–6 letters long, at either end of a run
            // whose groups hold 12+ characters without it ("4111 1111 1111 llll").
            func hasDigit(_ index: Int) -> Bool { text[groups[index]].contains(where: isASCIIDigit) }
            func isEdgeWord(_ index: Int) -> Bool {
                groups.indices.contains(index) && !hasDigit(index) && (3...6).contains(text[groups[index]].count)
            }
            var runs: [[Int]] = []
            var current: [Int] = []
            for index in groups.indices {
                if hasDigit(index) || (!current.isEmpty && index + 1 < groups.count && hasDigit(index + 1)) {
                    current.append(index)
                } else if !current.isEmpty {
                    runs.append(current)
                    current = []
                }
            }
            if !current.isEmpty { runs.append(current) }
            for var run in runs {
                guard let first = run.first, let last = run.last else { continue }
                if run.reduce(0, { $0 + text[groups[$1]].count }) >= 12 {
                    if isEdgeWord(first - 1) { run.insert(first - 1, at: 0) }
                    if isEdgeWord(last + 1) { run.append(last + 1) }
                }
                let characters = run.flatMap { Array(text[groups[$0]]) }
                let real = characters.filter(isASCIIDigit).count
                guard real < characters.count, real >= 9, let start = run.first, let end = run.last else { continue }
                let mapped = run.map { String(text[groups[$0]].map { lookalikeDigits[$0] ?? $0 }) }.joined(separator: " ")
                if isCardNumber(mapped) { ranges.append(NSRange(groups[start].lowerBound..<groups[end].upperBound, in: text)) }
            }
        }
        return replaceRanges(ranges, in: text) { _ in true }
    }

    private static func isCardShaped(_ shape: [Int]) -> Bool {
        if shape == [4, 6, 5] || shape == [4, 6, 4] { return true }
        guard shape.count >= 4, let last = shape.last else { return false }
        return shape.dropLast().allSatisfy { $0 == 4 } && (1...4).contains(last)
    }

    static func luhnValid(_ digits: String) -> Bool {
        var total = 0
        for (position, character) in digits.reversed().enumerated() {
            guard var value = character.wholeNumberValue else { return false }
            if position % 2 == 1 {
                value *= 2
                if value > 9 { value -= 9 }
            }
            total += value
        }
        return total % 10 == 0
    }

    // MARK: Text helpers

    /// Format characters (zero-width spaces, BOMs, bidi marks) removed, controls other than tab, CR and LF turned
    /// into spaces, and every Unicode decimal digit written as its ASCII digit.
    private static func plain(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .format:
                continue
            case .control where !["\n", "\r", "\t"].contains(scalar):
                scalars.append(" ")
            default:
                scalars.append(contentsOf: asciiDigit(scalar).unicodeScalars)
            }
        }
        return String(scalars)
    }

    private static func asciiDigits(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.flatMap { asciiDigit($0).unicodeScalars }))
    }

    private static func asciiDigit(_ scalar: Unicode.Scalar) -> String {
        guard !scalar.isASCII, scalar.properties.numericType == .decimal,
              let value = scalar.properties.numericValue, (0...9).contains(value)
        else { return String(scalar) }
        return String(Int(value))
    }

    private static func replaceAll(_ regex: NSRegularExpression, in text: String) -> String {
        regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: NSRegularExpression.escapedTemplate(for: cardToken)
        )
    }

    /// Replaces each whole match for which `shouldReplace` holds.
    private static func replaceMatches(
        _ regex: NSRegularExpression, in text: String, where shouldReplace: (String) -> Bool
    ) -> String {
        replaceRanges(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map(\.range), in: text) {
            shouldReplace($0)
        }
    }

    /// Replaces capture group 1 of each match.
    private static func replaceGroup(_ regex: NSRegularExpression, in text: String) -> String {
        replaceRanges(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { $0.range(at: 1) }, in: text) { _ in
            true
        }
    }

    private static func replaceRanges(
        _ ranges: [NSRange], in text: String, where shouldReplace: (String) -> Bool
    ) -> String {
        var result = text
        for nsRange in ranges.reversed() {
            guard nsRange.location != NSNotFound, let range = Range(nsRange, in: result),
                  shouldReplace(String(result[range]))
            else { continue }
            result.replaceSubrange(range, with: cardToken)
        }
        return result
    }
}
