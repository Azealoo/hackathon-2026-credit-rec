import Foundation

/// On-device redaction (SPEC §10, §15.7 step 8). Text in, text out: no images and no Vision, so it is testable on
/// plain strings. The patterns are ICU/PCRE-style and avoid Swift-only syntax so the backend can mirror them.
///
/// The input is OCR text in reading order: `ReadingOrder` joins the fragments of one row with two spaces, so every
/// rule allows for that ("4111  1111  1111  1111", "Name on card  Alex Doe").
///
/// What it removes, line by line:
/// - card numbers: any run of 12+ digits with up to 5 spaces, hyphens, dashes or periods between digits → `[CARD]`,
///   also when OCR split the number over two rows;
/// - last 4: "ending in 1234", "••5678", ". .1234", "**** 4321", "x1234", and any 4-digit group on a line that names
///   a card network → `[CARD]` (the network word stays: "Mastercard ••5678" → "Mastercard [CARD]");
/// - emails (also OCR-spaced, "alex doe @ example . com") → `[EMAIL]`; US phone numbers → `[PHONE]`;
/// - the lines after "Ship to", "Deliver to", "Shipping address", "Billing address", "Name", "Name on card", … →
///   `[NAME]` for a person's name, `[ADDRESS]` for the rest; the same labels with the value on the same row;
/// - under softer labels ("Contact", "Shipping", "Account", "Payment", …) only lines that look like a person's name
///   or an address;
/// - any line anywhere that looks like a street address or "City, ST 12345" / "City, State 12345" → `[ADDRESS]`;
/// - a name after a greeting ("Thank you, Alex.") or "Signed in as" → `[NAME]`.
enum Redactor {
    enum Kind: String, CaseIterable, Sendable {
        case cardNumber = "card_number"
        case address
        case email
        case phone
        case name
    }

    struct Result: Sendable, Equatable {
        var lines: [String]
        /// Kinds that fired, in `Kind.allCases` order.
        var kinds: [String]
        var text: String { lines.joined(separator: "\n") }
    }

    static let cardToken = "[CARD]"
    static let addressToken = "[ADDRESS]"
    static let emailToken = "[EMAIL]"
    static let phoneToken = "[PHONE]"
    static let nameToken = "[NAME]"

    static func redact(_ text: String) -> Result {
        redact(lines: text.components(separatedBy: "\n"))
    }

    /// The lines after a header. A hard block ("Ship to") always takes its first line; a soft block ("Contact") only
    /// takes lines that look like a name or an address.
    private struct Block {
        var isSoft: Bool
        var isName: Bool
        var linesLeft = 4
        var isFirstLine = true
    }

    static func redact(lines raw: [String]) -> Result {
        var fired = Set<Kind>()
        var output: [String] = []
        output.reserveCapacity(raw.count)
        var block: Block?

        // 0. A card number OCR split over rows ("Card number 4111 1111" / "1111 1111"), before the last-4 rule below
        //    takes the groups one by one.
        var input = raw.map { $0.trimmingCharacters(in: .whitespaces) }
        if redactRunsAcrossRows(&input) { fired.insert(.cardNumber) }

        for (index, line) in input.enumerated() {
            // 1. A hard header such as "Ship to" or "Name on card" starts a block; a value on the same row goes at once.
            if let header = Patterns.blockHeader.firstMatch(in: line) {
                let label = header.group(1, in: line) ?? ""
                let hasColon = header.group(2, in: line) != nil
                let rest = (header.group(3, in: line) ?? "").trimmingCharacters(in: .whitespaces)
                let isNameLabel = Patterns.nameLabel.matches(label)
                if rest.isEmpty {
                    output.append(line)
                    block = Block(isSoft: false, isName: isNameLabel)
                    continue
                }
                // "Name brand headphones" is not a header: a bare "Name" needs a colon or a person's name after it.
                // Every other label ("Name on card  Alex Doe", "Cardholder  Alex Doe", "Ship to  …") takes the rest.
                if !Patterns.genericNameLabel.matches(label) || hasColon || looksLikePersonName(rest) {
                    let kind: Kind = isNameLabel || (looksLikePersonName(rest) && !looksLikeAddress(rest)) ? .name : .address
                    output.append(label + " " + token(for: kind))
                    fired.insert(kind)
                    block = nil
                    continue
                }
            }

            // 2. A soft header ("Contact", "Shipping", "Account", …) alone on its row opens a soft block; with a person's
            //    name on the same row ("Contact  Alex Doe", "Account: Alex Doe") the name goes. "Shipping  Free" stays.
            if let header = Patterns.softHeader.firstMatch(in: line) {
                let label = header.group(1, in: line) ?? ""
                let rest = (header.group(3, in: line) ?? "").trimmingCharacters(in: .whitespaces)
                if rest.isEmpty {
                    output.append(line)
                    block = Block(isSoft: true, isName: false)
                    continue
                }
                if looksLikePersonName(rest) {
                    output.append(label + " " + nameToken)
                    fired.insert(.name)
                    block = nil
                    continue
                }
            }

            // 3. Lines inside a block. A section label or a price ends it.
            if var current = block {
                let first = current.isFirstLine
                current.isFirstLine = false
                current.linesLeft -= 1
                block = current.linesLeft > 0 ? current : nil

                if Patterns.sectionLabel.matches(line) || Patterns.money.matches(line) {
                    block = nil
                } else if !current.isSoft && first {
                    // The first line under a hard header always goes: as a name if it looks like one, or after "Name".
                    let kind: Kind = current.isName || (Patterns.personName.matches(line) && !looksLikeAddress(line)) ? .name : .address
                    output.append(token(for: kind))
                    fired.insert(kind)
                    if current.isName { block = nil }
                    continue
                } else if looksLikeAddress(line) || Patterns.zipAtEnd.matches(line) {
                    output.append(addressToken)
                    fired.insert(.address)
                    continue
                } else if current.isSoft && looksLikePersonName(line) {
                    output.append(nameToken)
                    fired.insert(.name)
                    continue
                } else if !current.isSoft {
                    block = nil
                }
                // A soft block stays open over lines it leaves to the in-line rules (the email line under "Contact").
            }

            // 4. An address anywhere replaces the whole line, and a person's name on the row right above it goes too
            //    ("Alex Doe" / "123 Example St" with no header).
            if looksLikeAddress(line) {
                if index > 0, output.last == input[index - 1], looksLikePersonName(input[index - 1]) {
                    output[output.count - 1] = nameToken
                    fired.insert(.name)
                }
                output.append(addressToken)
                fired.insert(.address)
                continue
            }

            // 5. In-line replacements, most specific first.
            var text = line
            if Patterns.email.replace(in: &text, with: emailToken) { fired.insert(.email) }
            if Patterns.longDigitRun.replace(in: &text, with: cardToken) { fired.insert(.cardNumber) }
            if Patterns.phone.replace(in: &text, with: phoneToken) { fired.insert(.phone) }
            if Patterns.endingIn.replace(in: &text, with: "$1 " + cardToken) { fired.insert(.cardNumber) }
            if Patterns.maskedLast4.replace(in: &text, with: cardToken) { fired.insert(.cardNumber) }
            if Patterns.cardWord.matches(text),
               Patterns.lineLast4.replace(in: &text, with: cardToken) {
                fired.insert(.cardNumber)
            }
            if Patterns.greetingName.replace(in: &text, with: "$1$2" + nameToken) { fired.insert(.name) }
            if Patterns.signedInAs.replace(in: &text, with: "$1 " + nameToken) { fired.insert(.name) }
            // Tidy "Mastercard ••[CARD]" or "Visa . . [CARD]" (mask characters before a replaced group) to "Visa [CARD]".
            Patterns.maskBeforeToken.replace(in: &text, with: " " + cardToken)
            Patterns.letterBeforeToken.replace(in: &text, with: "$1 " + cardToken)
            output.append(text)
        }

        // 6. Once more over the output, so no run of 12+ digits across rows is left whatever the rules above did.
        if redactRunsAcrossRows(&output) { fired.insert(.cardNumber) }

        let kinds = Kind.allCases.filter { fired.contains($0) }.map(\.rawValue)
        return Result(lines: output, kinds: kinds)
    }

    /// Replaces each row's part of a 12+ digit run that crosses rows with `[CARD]` ("4111 1111" / "1111 1111" →
    /// "[CARD]" / "[CARD]"). Runs inside one row are left to `longDigitRun`. Address, phone and email rows are left out
    /// of the search, so a ZIP code above a phone number is not taken for a card; their own rules handle them.
    /// Returns whether anything changed.
    private static func redactRunsAcrossRows(_ lines: inout [String]) -> Bool {
        guard lines.count > 1 else { return false }
        let skipped = lines.map { looksLikeAddress($0) || Patterns.phone.matches($0) || $0.contains("@") }
        // U+0001 never comes out of OCR; it stands in for a skipped row and breaks any run.
        var joined = zip(lines, skipped).map { line, skip in skip ? "\u{1}" : line }.joined(separator: "\n")
        let before = joined
        _ = Patterns.crossLineDigitRun.replaceEach(in: &joined) { match in
            guard match.contains("\n") else { return match }
            return match.components(separatedBy: "\n")
                .map { $0.contains(where: { $0.isASCII && $0.isNumber }) ? cardToken : $0 }
                .joined(separator: "\n")
        }
        guard joined != before else { return false }
        let replaced = joined.components(separatedBy: "\n")
        lines = lines.indices.map { skipped[$0] ? lines[$0] : replaced[$0] }
        return true
    }

    private static func token(for kind: Kind) -> String {
        switch kind {
        case .cardNumber: cardToken
        case .address: addressToken
        case .email: emailToken
        case .phone: phoneToken
        case .name: nameToken
        }
    }

    /// A street line ("123 Example St"), a city line ("Seattle, WA 98000", "Seattle, Washington 98000") or a
    /// unit/PO box line.
    static func looksLikeAddress(_ line: String) -> Bool {
        Patterns.street.matches(line) || Patterns.cityStateZip.matches(line) || Patterns.cityStateNameZip.matches(line)
            || Patterns.unitOrBox.matches(line)
    }

    /// Two to four capitalised words that are not shop words ("Alex Doe" yes; "Standard Shipping", "Visa Card",
    /// "Northbay Electronics", "Best Buy" no).
    static func looksLikePersonName(_ text: String) -> Bool {
        Patterns.personName.matches(text) && !Patterns.nonNameWord.matches(text)
    }

    /// Luhn checksum over the digits of `candidate` (other characters are ignored).
    static func isLuhnValid(_ candidate: String) -> Bool {
        let digits = candidate.compactMap(\.wholeNumberValue)
        guard digits.count >= 2 else { return false }
        var sum = 0
        for (index, digit) in digits.reversed().enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    /// Characters that `longestDigitRun` counts as part of a run when at most 5 of them sit between two digits.
    private static let runSeparators: Set<Character> = [" ", "\t", "\n", "-", "–", "—", "."]

    /// Longest run of digits in `text`, counting up to 5 spaces, newlines, hyphens, dashes or periods between digits
    /// as part of the run ("4111  1111  1111  1111" and "4111 1111\n1111 1111" are 16). The privacy bar (SPEC §9.2) is
    /// that this stays below 12 in anything sent. It is the tests' check, written separately from the redaction rules
    /// and a little stricter: it also counts across a decimal point, which the redaction leaves alone in prices.
    static func longestDigitRun(in text: String) -> Int {
        var best = 0
        var current = 0
        var gap = 0
        for character in text {
            if character.isASCII && character.isNumber {
                current += 1
                gap = 0
                best = max(best, current)
            } else if current > 0 && gap < 5 && runSeparators.contains(character) {
                gap += 1
            } else {
                current = 0
                gap = 0
            }
        }
        return best
    }
}

// MARK: - Rules

private enum Patterns {
    /// What may sit between two digits of a card number: spaces (ReadingOrder joins columns with two), tabs, hyphens,
    /// en and em dashes, and periods, except a decimal point before cents ("$18.00  1234 5678" keeps its price).
    static let digitSeparator = #"(?:[ \t\-–—]|\.(?![0-9]{2}(?![0-9])))"#
    /// 12+ digits with up to 5 separators between digits: "4111 1111 1111 1111", "4111  1111  1111  1111",
    /// "4111 - 1111 - 1111 - 1111", "4111.1111.1111.1111". Every card number (12–19 digits, Luhn-valid or not) is
    /// caught by this.
    static let longDigitRun = Pattern(#"(?<![0-9])[0-9](?:"# + digitSeparator + #"{0,5}[0-9]){11,}(?![0-9])"#)
    /// The same over the joined lines, newlines counting as separators: a number split over two OCR rows.
    static let crossLineDigitRun = Pattern(#"(?<![0-9])[0-9](?:(?:[ \t\n\-–—]|\.(?![0-9]{2}(?![0-9])))"#
                                           + #"{0,5}[0-9]){11,}(?![0-9])"#)

    /// US phone numbers: "(555) 010-0000", "555-010-0000", "555.010.0000", "555 . 010 . 0000", "+1 555 010 0000",
    /// "+15550100000", "5550100000". Up to 3 spaces, periods or dashes between the groups.
    static let phone = Pattern(#"(?<![0-9])(?:(?:\+ ?)?1[ .\-–—]{0,3})?\(?[0-9]{3}\)?[ .\-–—]{0,3}[0-9]{3}[ .\-–—]{0,3}[0-9]{4}(?![0-9])"#)

    /// "alex@example.com", and OCR's spaced form "alex doe @ example . com" (the words before " @" go too).
    private static let emailLocal = #"[A-Za-z0-9._%+\-]+"#
    private static let emailDomain = #"[A-Za-z0-9\-]+(?:(?:\.| \. )[A-Za-z0-9\-]+)*(?:\.| \. )[A-Za-z]{2,}(?![A-Za-z])"#
    static let email = Pattern(emailLocal + #" ?@ ?"# + emailDomain + "|(?:" + emailLocal + " ){1,2}" + emailLocal + " @ ?" + emailDomain)

    /// "ending in 1234", "ends with 1234", "Last 4: 1234".
    static let endingIn = Pattern(#"(?i)\b(ending in|ends in|ending with|ends with|ending|last 4(?: digits)?|last four(?: digits)?)\s*[:\-]?\s*[0-9]{4}\b"#)
    /// Mask characters, then the last 4: "••5678", "• •5678", "**** 4321", "...1234", ". .1234", "x1234", "XXXX-1234".
    static let maskedLast4 = Pattern(#"(?:(?:[.•·∙●◦*] ?){2,}|[•·∙●◦*] ?|\b[xX]{1,4}[ \-]?)[0-9]{4}(?![0-9])"#)
    /// A line that names a card or a network.
    static let cardWord = Pattern(#"(?i)\b(visa|master ?card|mastercard|amex|american express|discover|debit|credit|card|pay with|paid with)\b"#)
    /// Any standalone 4-digit group that is not part of a price ("$1499", "1499.00", "1,499").
    static let lineLast4 = Pattern(#"(?<![0-9$,.])[0-9]{4}(?![0-9]|[.,][0-9])"#)
    /// Leftover mask characters right before a token ("••[CARD]", ". . [CARD]").
    static let maskBeforeToken = Pattern(#"(?:\s*[•·∙●◦*.])+\s*\[CARD\]"#)
    /// A token glued to the word before it ("card no[CARD]").
    static let letterBeforeToken = Pattern(#"([A-Za-z])\[CARD\]"#)

    /// "Thank you, Alex." / "Hi Alex" / "Welcome back, Alex".
    static let greetingName = Pattern(#"(?i)\b(thank you|thanks|hi|hello|hey|welcome back|welcome)(,\s*|\s+)(?-i:[A-Z][a-z'\-]+)(?:\s+(?-i:[A-Z][a-z'\-]+))?"#)
    /// "Signed in as Alex Doe": everything after the phrase goes, unless it is already a token ("[EMAIL]").
    static let signedInAs = Pattern(#"(?i)\b(signed in as|logged in as)\s+(?!\[)\S.*$"#)

    /// Headers that start a hard block. Group 1: the label; group 2: a colon; group 3: anything after it.
    static let blockHeader = Pattern(#"(?i)^(ship to|shipping to|deliver to|delivering to|delivery address|shipping address|billing address|bill to|sold to|recipient|full name|name on card|cardholder name|cardholder|card holder name|card holder|account holder|customer name|contact name|billing name|name)\b\s*(:)?\s*(.*)$"#)
    /// Hard labels whose value is a person's name.
    static let nameLabel = Pattern(#"(?i)^(full name|name on card|cardholder name|cardholder|card holder name|card holder|account holder|customer name|contact name|billing name|name)$"#)
    /// The one label that is also an ordinary word ("Name brand headphones").
    static let genericNameLabel = Pattern(#"(?i)^name$"#)
    /// Headers that start a soft block. Same groups as `blockHeader`.
    static let softHeader = Pattern(#"(?i)^(contact(?: info(?:rmation)?| details)?|shipping(?: info(?:rmation)?| details)?|delivery(?: info(?:rmation)?| details)?|billing(?: info(?:rmation)?| details)?|customer(?: info(?:rmation)?| details)?|your account|account|payment(?: method| details| info(?:rmation)?)?|pay with|paid with)\b\s*(:)?\s*(.*)$"#)

    /// Labels that end a block rather than belong to it.
    static let sectionLabel = Pattern(#"(?i)^(contact|pay with|paid with|payment|shipping|delivery|billing|customer|account|total|subtotal|order|items?|change|edit|qty)\b"#)
    static let money = Pattern(#"\$\s?[0-9]"#)

    /// Two to four capitalised words, letters only: "Alex Doe", "Mary-Jo O'Neil".
    static let personName = Pattern(#"^[A-Z][a-zA-Z'\-]+(?:\s+[A-Z][a-zA-Z'\-.]*){1,3}$"#)
    /// Words in shop text that are not in a person's name; they keep "Standard Shipping" or "Visa Card" from being
    /// taken for a name inside a soft block.
    static let nonNameWord = Pattern(#"(?i)\b(ship|shipping|shipped|delivery|deliver|delivered|pickup|standard|express|free|ground|overnight|priority|order|orders|total|subtotal|summary|payment|pay|card|visa|master|mastercard|amex|american|discover|debit|credit|apple|google|paypal|change|edit|add|new|save|saved|continue|return|returns|policy|warranty|day|days|store|shop|electronics|inc|llc|support|help|account|sign|signed|log|details|information|info|method|address|email|phone|checkout|cart|item|items|qty|place|placed|renewed|refurbished|buy|athletics|outlet|market|pharmacy|supply|goods|company|co|coffee|pickup|pick)\b"#)

    /// "123 Example St", "4 Main Street", "1600 Pennsylvania Ave NW".
    static let street = Pattern(#"(?i)(?<![0-9A-Za-z$.,])[0-9]{1,6}[A-Za-z]?\s+(?:[A-Za-z0-9.'\-]+\s+){0,4}(?:st|street|ave|avenue|rd|road|blvd|boulevard|dr|drive|ln|lane|way|ct|court|pl|place|pkwy|parkway|hwy|highway|ter|terrace|cir|circle|sq|square)\b"#)
    /// "Seattle, WA 98000", "WA 98000-1234".
    static let cityStateZip = Pattern(#"(?:\b[A-Za-z][A-Za-z .'\-]*,\s*)?\b[A-Z]{2}\s+[0-9]{5}(?:-[0-9]{4})?\b"#)
    /// "Seattle, Washington 98000", "Concord, New Hampshire 03301".
    static let cityStateNameZip = Pattern(#"\b[A-Z][A-Za-z .'\-]*,\s*[A-Z][A-Za-z]+(?:\s[A-Z][A-Za-z]+){0,2}\s+[0-9]{5}(?:-[0-9]{4})?(?![0-9])"#)
    /// Inside a block only: a line that ends in a ZIP code ("Seattle Washington 98000").
    static let zipAtEnd = Pattern(#"[A-Za-z][A-Za-z .,'\-]*\s[0-9]{5}(?:-[0-9]{4})?$"#)
    static let unitOrBox = Pattern(#"(?i)^(?:apt|apartment|suite|ste|unit|p\.?\s?o\.?\s?box)\b\.?\s*#?\s*[0-9A-Za-z]+"#)
}

// MARK: - A small NSRegularExpression wrapper (named Pattern so it does not shadow Swift.Regex)

private struct Pattern: Sendable {
    let expression: NSRegularExpression

    init(_ pattern: String) {
        // The patterns are constants; a typo is a programming error that the unit tests catch on the first call.
        expression = try! NSRegularExpression(pattern: pattern)
    }

    func matches(_ text: String) -> Bool {
        expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    func firstMatch(in text: String) -> Match? {
        expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)).map(Match.init)
    }

    /// Replaces every match; returns whether anything was replaced.
    @discardableResult
    func replace(in text: inout String, with template: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        guard expression.firstMatch(in: text, range: range) != nil else { return false }
        text = expression.stringByReplacingMatches(in: text, range: range, withTemplate: template)
        return true
    }

    /// Replaces every match with `transform(match)`; returns whether anything matched.
    @discardableResult
    func replaceEach(in text: inout String, transform: (String) -> String) -> Bool {
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return false }
        // Back to front, so the earlier ranges stay valid.
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            text.replaceSubrange(range, with: transform(String(text[range])))
        }
        return true
    }

    struct Match {
        let result: NSTextCheckingResult

        /// Capture group `index` (1-based), or nil if it did not take part in the match.
        func group(_ index: Int, in text: String) -> String? {
            let range = result.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }
}
