import Foundation

/// On-device redaction (SPEC §10, §15.7 step 8). Text in, text out: no images and no Vision, so it is testable on
/// plain strings. The patterns are ICU/PCRE-style and avoid Swift-only syntax so the backend can mirror them.
///
/// The input is OCR text in reading order: `ReadingOrder` joins the fragments of one row with two spaces, so every
/// rule allows for that ("4111  1111  1111  1111", "Name on card  Alex Doe").
///
/// What it removes, line by line:
/// - card numbers: any run of 12+ digits with up to 5 spaces, hyphens, dashes or periods between digits → `[CARD]`,
///   also when OCR split the number over two rows, and also when OCR read a few digits, or a whole group, as
///   look-alike letters ("4111 1111 l111 1111", "5105 105| 0510 5100", "4111 1111 llll 1111": O/o → 0,
///   l/I/|/! → 1, S → 5, B → 8, Z → 2);
/// - card-entry fields: the expiry ("Exp  12/28", "Expiration date" / "12 / 28", any MM/YY on a card form) and the
///   security code ("CVV  123", "Security code" / "123") → `[CARD]`. A card form is a screen with a card-form label
///   ("Card number", "Card information", "CVC", …), a full card number, or an expiry and a code side by side. On one,
///   a filled form whose placeholders are gone ("4242 4242 4242 4242" / "12 / 28  123") loses its unlabelled code
///   too, and a one-row card element's ZIP ("… 12 / 28  123  98000") → `[ADDRESS]`;
/// - last 4: "ending in 1234", "••5678", ". .1234", "**** 4321", "#### 4321", "x1234", any 4-digit group on a line
///   that names a card network, and a bare 4-digit row under a card name or inside a "Pay with" block → `[CARD]`
///   (the network word stays: "Mastercard ••5678" → "Mastercard [CARD]");
/// - emails (also OCR-spaced, "alex doe @ example . com") → `[EMAIL]`; US phone numbers → `[PHONE]`;
/// - the lines after "Ship to", "Deliver to", "Shipping address", "Billing address", "Name", "Name on card",
///   "Pickup person", "Order for", … → `[NAME]` for a person's name, `[ADDRESS]` for the rest; the same labels with
///   the value on the same row. An address block stays open past lines it leaves (a delivery promise), so its house
///   number, city and country lines go wherever they sit in the block;
/// - under softer labels ("Contact", "Shipping", "Account", "Payment", …) only lines that look like a person's name
///   or an address. Card product names ("Chase Freedom Unlimited", "Active Cash") are not a person's name: the backend
///   needs them to see the payment options, so they stay;
/// - any line anywhere that looks like a street address or "City, ST 12345" / "City, State 12345" → `[ADDRESS]`, and
///   a person's name up to two rows above it (one other row may sit between) or right above an email or phone;
/// - a name after a greeting ("Thank you, Alex.") or "Signed in as" → `[NAME]`.
///
/// `redactFreeText` applies the in-line rules to text a person typed (the claim's "What happened?"), replacing only
/// the matched part, so the words around it survive for the cause classifier.
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

    /// The card names in the bundled cards.json (`shortName` and `displayName`), so a "Pay with" block keeps
    /// "Chase Freedom Unlimited" rather than taking it for a person. The names come from the one card-data file.
    static let catalogCardNames: [String] = CardCatalog.bundled().cards.flatMap {
        [$0.shortName, $0.displayName].compactMap { $0 }
    }

    /// The lines after a header. A hard block ("Ship to") always takes its first line; a soft block ("Contact") only
    /// takes lines that look like a name or an address.
    private struct Block {
        var isSoft: Bool
        var isName: Bool
        /// "Ship to", "Billing address", "Shipping", …: house-number, city, country and "c/o" lines go too, and the
        /// block stays open over a line it leaves ("Free delivery in 2–4 days") until a section label, a price, a
        /// blank row or its line budget ends it.
        var isAddress = false
        /// "Pay with", "Payment", …: a bare last 4 goes; card product names stay.
        var isPayment = false
        var linesLeft = 4
        var isFirstLine = true
    }

    /// - Parameter cardNames: card product names that are never a person's name; the bundled catalog's by default.
    static func redact(lines raw: [String], cardNames: [String]? = nil) -> Result {
        let names = CardNames(cardNames ?? catalogCardNames)
        var fired = Set<Kind>()
        var output: [String] = []
        output.reserveCapacity(raw.count)
        var block: Block?

        var input = raw.map { $0.trimmingCharacters(in: .whitespaces) }
        // 0. Before the line rules: letters OCR read for digits inside a card number become digits, so the number
        //    rules see all of it; the labelled fields and expiry of a card form go; then a card number OCR split over
        //    rows ("Card number 4111 1111" / "1111 1111"), before the last-4 rule below takes the groups one by one.
        //    The expiry goes first, so the split-number rule cannot take its month ("[CARD] / 28"); the security code
        //    and ZIP next to it go last, so the split-number rule still sees a number's groups whole.
        normalizeLookalikeDigits(&input)
        let cardForm = isCardForm(input)
        if redactCardFields(&input, isCardForm: cardForm) { fired.insert(.cardNumber) }
        if redactRunsAcrossRows(&input) { fired.insert(.cardNumber) }
        if cardForm { fired.formUnion(redactCardEntryRows(&input)) }

        for (index, line) in input.enumerated() {
            let inPaymentBlock = block?.isPayment ?? false
            let belowACard = index > 0 && namesACard(input[index - 1], names)

            // 1. A hard header such as "Ship to" or "Name on card" starts a block; a value on the same row goes at once.
            if let header = Patterns.blockHeader.firstMatch(in: line) {
                let label = header.group(1, in: line) ?? ""
                let hasColon = header.group(2, in: line) != nil
                let rest = (header.group(3, in: line) ?? "").trimmingCharacters(in: .whitespaces)
                let isNameLabel = Patterns.nameLabel.matches(label)
                let isAddressLabel = Patterns.addressLabel.matches(label)
                if rest.isEmpty {
                    output.append(line)
                    block = Block(isSoft: false, isName: isNameLabel, isAddress: isAddressLabel,
                                  linesLeft: isAddressLabel ? 5 : 4)
                    continue
                }
                // "Name brand headphones" is not a header: a bare "Name" (or "Order for", "Buyer", …) needs a colon or
                // a person's name after it. Every other label ("Name on card  Alex Doe", "Ship to  …") takes the rest.
                if !Patterns.ambiguousLabel.matches(label) || hasColon || looksLikePersonName(rest, names) {
                    let kind: Kind = isNameLabel || (looksLikePersonName(rest, names) && !looksLikeAddress(rest)) ? .name : .address
                    output.append(label + " " + token(for: kind))
                    fired.insert(kind)
                    // "Ship to  Alex Doe" / "2 Park Plaza" / "Boston, MA 02116": the address lines below still go.
                    block = isAddressLabel ? Block(isSoft: false, isName: false, isAddress: true, isFirstLine: false) : nil
                    continue
                }
            }

            // 2. A soft header ("Contact", "Shipping", "Account", …) alone on its row opens a soft block; with a person's
            //    name on the same row ("Contact  Alex Doe", "Account: Alex Doe") the name goes. "Shipping  Free" and
            //    "Pay with  Chase Freedom Unlimited" stay.
            if let header = Patterns.softHeader.firstMatch(in: line) {
                let label = header.group(1, in: line) ?? ""
                let rest = (header.group(3, in: line) ?? "").trimmingCharacters(in: .whitespaces)
                let isAddressLabel = Patterns.softAddressLabel.matches(label)
                let isPaymentLabel = Patterns.paymentLabel.matches(label)
                if rest.isEmpty {
                    output.append(line)
                    block = Block(isSoft: true, isName: false, isAddress: isAddressLabel, isPayment: isPaymentLabel,
                                  linesLeft: isAddressLabel ? 5 : 4)
                    continue
                }
                if looksLikePersonName(rest, names) {
                    output.append(label + " " + nameToken)
                    fired.insert(.name)
                    // "Shipping  Alex Doe" / "1 Infinite Loop": the address lines below still go.
                    block = isAddressLabel ? Block(isSoft: true, isName: false, isAddress: true, isFirstLine: false) : nil
                    continue
                }
            }

            // 3. Lines inside a block. A section label or a price ends it, and so does a blank row after the first line.
            if var current = block {
                if line.isEmpty {
                    if !current.isFirstLine { block = nil }
                    output.append(line)
                    continue
                }
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
                } else if looksLikeAddress(line) || Patterns.zipAtEnd.matches(line)
                            || (current.isAddress && looksLikeAddressPart(line)) {
                    output.append(addressToken)
                    fired.insert(.address)
                    continue
                } else if current.isAddress && Patterns.careOf.matches(line) {
                    output.append(nameToken)
                    fired.insert(.name)
                    continue
                } else if current.isSoft && looksLikePersonName(line, names) {
                    output.append(nameToken)
                    fired.insert(.name)
                    continue
                } else if !current.isSoft && !current.isAddress {
                    block = nil
                }
                // A soft block stays open over lines it leaves to the in-line rules (the email line under "Contact"),
                // and an address block over a delivery promise between its lines.
            }

            // 4. An address anywhere replaces the whole line, and a person's name just above it goes too ("Alex Doe" /
            //    "123 Example St" with no header; a blank row or one other row may sit between them).
            if looksLikeAddress(line) {
                redactNameAbove(index, input: input, output: &output, fired: &fired, names: names, allowOtherRow: true)
                output.append(addressToken)
                fired.insert(.address)
                continue
            }

            // 5. In-line replacements, most specific first. A person's name right above an email or phone goes too.
            var text = line
            if Patterns.email.matches(line) || Patterns.phone.matches(line) {
                redactNameAbove(index, input: input, output: &output, fired: &fired, names: names, allowOtherRow: false)
            }
            if Patterns.email.replace(in: &text, with: emailToken) { fired.insert(.email) }
            if Patterns.longDigitRun.replace(in: &text, with: cardToken) { fired.insert(.cardNumber) }
            if Patterns.phone.replace(in: &text, with: phoneToken) { fired.insert(.phone) }
            if Patterns.endingIn.replace(in: &text, with: "$1 " + cardToken) { fired.insert(.cardNumber) }
            if Patterns.maskedLast4.replace(in: &text, with: cardToken) { fired.insert(.cardNumber) }
            if Patterns.cardWord.matches(text),
               Patterns.lineLast4.replace(in: &text, with: cardToken) {
                fired.insert(.cardNumber)
            }
            // A last 4 on a row of its own, under a card name ("Chase Freedom Unlimited" / "1234") or in "Pay with".
            if inPaymentBlock || belowACard, Patterns.bareLast4Row.matches(text),
               Patterns.lineLast4.replace(in: &text, with: cardToken) {
                fired.insert(.cardNumber)
            }
            if Patterns.greetingName.replace(in: &text, with: "$1$2" + nameToken) { fired.insert(.name) }
            if Patterns.signedInAs.replace(in: &text, with: "$1 " + nameToken) { fired.insert(.name) }
            tidyTokens(&text)
            output.append(text)
        }

        // 6. Once more over the output, so no run of 12+ digits across rows is left whatever the rules above did.
        if redactRunsAcrossRows(&output) { fired.insert(.cardNumber) }

        let kinds = Kind.allCases.filter { fired.contains($0) }.map(\.rawValue)
        return Result(lines: output, kinds: kinds)
    }

    /// The in-line rules over text a person typed (the claim's "What happened?", SPEC §5.5): card numbers (look-alike
    /// letters too), a labelled expiry or security code, last 4, emails, phones, street addresses and "City, ST 12345",
    /// a greeting's name. Only the matched part is replaced ("Stolen at [ADDRESS], call [PHONE]"), so the words that
    /// say what happened stay for the cause classifier. No block rules: typed text has no "Ship to" layout.
    static func redactFreeText(_ text: String) -> Result {
        var fired = Set<Kind>()
        var lines = text.components(separatedBy: "\n")
        normalizeLookalikeDigits(&lines)
        for index in lines.indices {
            var line = lines[index]
            if Patterns.labeledExpiry.replace(in: &line, with: "$1 " + cardToken) { fired.insert(.cardNumber) }
            if Patterns.labeledCode.replace(in: &line, with: "$1 " + cardToken) { fired.insert(.cardNumber) }
            if Patterns.email.replace(in: &line, with: emailToken) { fired.insert(.email) }
            if Patterns.longDigitRun.replace(in: &line, with: cardToken) { fired.insert(.cardNumber) }
            if Patterns.phone.replace(in: &line, with: phoneToken) { fired.insert(.phone) }
            if Patterns.endingIn.replace(in: &line, with: "$1 " + cardToken) { fired.insert(.cardNumber) }
            if Patterns.maskedLast4.replace(in: &line, with: cardToken) { fired.insert(.cardNumber) }
            if Patterns.cardWord.matches(line),
               Patterns.lineLast4.replace(in: &line, with: cardToken) {
                fired.insert(.cardNumber)
            }
            for address in [Patterns.typedStreet, Patterns.typedCityStateZip, Patterns.typedCityStateNameZip, Patterns.poBox] {
                if address.replace(in: &line, with: addressToken) { fired.insert(.address) }
            }
            if Patterns.greetingName.replace(in: &line, with: "$1$2" + nameToken) { fired.insert(.name) }
            if Patterns.signedInAs.replace(in: &line, with: "$1 " + nameToken) { fired.insert(.name) }
            tidyTokens(&line)
            lines[index] = line
        }
        if redactRunsAcrossRows(&lines) { fired.insert(.cardNumber) }
        let kinds = Kind.allCases.filter { fired.contains($0) }.map(\.rawValue)
        return Result(lines: lines, kinds: kinds)
    }

    /// Tidy "Mastercard ••[CARD]" or "Visa . . [CARD]" (mask characters before a replaced group) to "Visa [CARD]".
    private static func tidyTokens(_ text: inout String) {
        Patterns.maskBeforeToken.replace(in: &text, with: " " + cardToken)
        Patterns.letterBeforeToken.replace(in: &text, with: "$1 " + cardToken)
    }

    /// Replaces a person's name on a row above `index` with `[NAME]`: the nearest non-blank row, or with
    /// `allowOtherRow` the one above that when the nearest isn't a name ("Alex Doe" / "Home" / "1 Infinite Loop").
    /// Rows already redacted, card product names and store names ("Best Buy") are left alone.
    private static func redactNameAbove(
        _ index: Int, input: [String], output: inout [String], fired: inout Set<Kind>, names: CardNames, allowOtherRow: Bool
    ) {
        var row = index - 1
        var passedOther = false
        while row >= 0, row >= index - 4 {
            let previous = input[row]
            if previous.isEmpty {
                row -= 1
                continue
            }
            if output[row] == previous, looksLikePersonName(previous, names) {
                output[row] = nameToken
                fired.insert(.name)
                return
            }
            guard allowOtherRow, !passedOther else { return }
            passedOther = true
            row -= 1
        }
    }

    /// Whether a row names a card: a network or card word ("Visa", "Apple Card", "Pay with") or a card product name.
    private static func namesACard(_ line: String, _ names: CardNames) -> Bool {
        Patterns.cardWord.matches(line) || looksLikeCardProduct(line, names)
    }

    // MARK: Look-alike digits

    /// What OCR reads for a digit in some fonts ("4111 1111 l111 1111" in Gill Sans, "5105 105|"): mapped back only
    /// inside a run that is a card number once mapped.
    private static let lookalikeDigits: [Character: Character] = [
        "O": "0", "o": "0", "l": "1", "I": "1", "|": "1", "!": "1", "S": "5", "B": "8", "Z": "2",
    ]

    /// Rewrites look-alike letters as digits inside each run of digit groups that, mapped, holds 12+ digits of which
    /// at least 9 are real digits and at most a third are letters. The card-number rules then redact the run as
    /// usual. Rows are searched joined, so a number split over two rows is caught too. The change is character for
    /// character. A group of letters only joins a run between two groups with a digit ("4111 1111 llll 1111"), or, 3–6
    /// letters long, at the end of a run that maps to 12+ digits on its own ("4111 1111 1111 llll"), so words ("So",
    /// "BOSS") next to a shorter number are left alone.
    private static func normalizeLookalikeDigits(_ lines: inout [String]) {
        var joined = lines.joined(separator: "\n")
        let changed = Patterns.lookalikeRun.replaceEach(in: &joined) { match in
            var segments: [(text: String, isGroup: Bool)] = []
            for character in match {
                let isGroupCharacter = (character.isASCII && character.isNumber) || lookalikeDigits[character] != nil
                if let last = segments.last, last.isGroup == isGroupCharacter {
                    segments[segments.count - 1].text.append(character)
                } else {
                    segments.append((String(character), isGroupCharacter))
                }
            }
            let groups = segments.indices.filter { segments[$0].isGroup }
            // Whether a row ends between group k and group k + 1.
            let rowBreaks = zip(groups, groups.dropFirst()).map { segments[$0 + 1..<$1].contains { $0.text.contains("\n") } }
            let runs = lookalikeRuns(groups.map { segments[$0].text }, rowBreaks: rowBreaks).map { run in run.map { groups[$0] } }
            for run in runs {
                let characters = run.flatMap { Array(segments[$0].text) }
                let real = characters.filter { $0.isASCII && $0.isNumber }.count
                let letters = characters.count - real
                guard letters > 0, characters.count >= 12, real >= 9, letters * 3 <= characters.count else { continue }
                for position in run {
                    segments[position].text = String(segments[position].text.map { lookalikeDigits[$0] ?? $0 })
                }
            }
            return segments.map(\.text).joined()
        }
        guard changed else { return }
        let rewritten = joined.components(separatedBy: "\n")
        if rewritten.count == lines.count { lines = rewritten }
    }

    /// The runs among consecutive digit groups (`groups`, in order, separators between them; `rowBreaks[k]` when a row
    /// ends between group k and k + 1), as indices into `groups`. A group with a real digit always joins. A group of
    /// look-alike letters only joins on the same row: between two groups with a digit, or, 3–6 letters long, at either
    /// end of a run whose groups hold 12+ characters without it.
    private static func lookalikeRuns(_ groups: [String], rowBreaks: [Bool]) -> [[Int]] {
        func hasDigit(_ index: Int) -> Bool { groups[index].contains { $0.isASCII && $0.isNumber } }
        /// Whether groups k and k + 1 sit on the same row.
        func sameRow(_ k: Int) -> Bool { rowBreaks.indices.contains(k) && !rowBreaks[k] }
        var runs: [[Int]] = []
        var current: [Int] = []
        for index in groups.indices {
            let isInnerWord = !current.isEmpty && index + 1 < groups.count && hasDigit(index + 1)
                && sameRow(index - 1) && sameRow(index)
            if hasDigit(index) || isInnerWord {
                current.append(index)
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs.map { run in
            guard let first = run.first, let last = run.last, run.reduce(0, { $0 + groups[$1].count }) >= 12 else { return run }
            func isEdgeWord(_ index: Int) -> Bool {
                groups.indices.contains(index) && !hasDigit(index) && (3...6).contains(groups[index].count)
            }
            let before = isEdgeWord(first - 1) && sameRow(first - 1) ? [first - 1] : []
            let after = isEdgeWord(last + 1) && sameRow(last) ? [last + 1] : []
            return before + run + after
        }
    }

    // MARK: Card-entry fields

    /// Whether the screen is a card-entry form:
    /// - a label only a card form has ("Card number", "Card information", "Name on card", "CVC", "Expiry", "MM / YY");
    /// - a full card number (`looksLikeCardNumber`), also split over two rows: a filled form whose placeholders are
    ///   gone may show no label at all;
    /// - a row with an expiry and a security code side by side and nothing else ("12 / 28  123").
    private static func isCardForm(_ lines: [String]) -> Bool {
        let onOneRow = lines.contains { line in
            if Patterns.cardFormLabel.matches(line) { return true }
            if Patterns.longDigitRun.allMatches(in: line).contains(where: looksLikeCardNumber) { return true }
            guard Patterns.digitsOnlyRow.matches(line) else { return false }
            var rest = line
            return Patterns.expiryValue.replace(in: &rest, with: cardToken) && Patterns.codeValue.matches(rest)
        }
        return onOneRow
            || Patterns.crossLineDigitRun.allMatches(in: joinedForRuns(lines).text).contains(where: looksLikeCardNumber)
    }

    /// A run of digit groups that is a card number: a Luhn-valid number of 13–19 digits, an aligned window of 13–19
    /// digits grouped as a card is typed (4-4-4-1…4, 4-6-5, 4-6-4; Luhn-valid or not, as a typo is still a card), or
    /// one unbroken group of 15–16 digits.
    static func looksLikeCardNumber(_ run: String) -> Bool {
        let groups = run.split(whereSeparator: { !($0.isASCII && $0.isNumber) }).map(\.count)
        let digits = run.filter { $0.isASCII && $0.isNumber }
        if (13...19).contains(digits.count), isLuhnValid(digits) { return true }
        if groups.count == 1, (15...16).contains(digits.count) { return true }
        for start in groups.indices {
            var count = 0
            for end in start..<groups.count {
                count += groups[end]
                if count > 19 { break }
                if count >= 13, isCardShaped(Array(groups[start...end])) { return true }
            }
        }
        return false
    }

    private static func isCardShaped(_ shape: [Int]) -> Bool {
        if shape == [4, 6, 5] || shape == [4, 6, 4] { return true }
        guard shape.count >= 4, let last = shape.last else { return false }
        return shape.dropLast().allSatisfy { $0 == 4 } && (1...4).contains(last)
    }

    /// The labelled fields and the expiry of a card form → `[CARD]`:
    /// - with the label on the same row: "Exp  12/28", "Expiration date: 12/2028", "CVV  123", "Security code 1234";
    /// - on the rows under a label row ("Expiration date" / "12 / 28", "Expiry  CVC" / "12/28  123");
    /// - on a card form (`isCardForm`): any MM/YY.
    /// The unlabelled security code is left to `redactCardEntryRows`. Returns whether anything changed.
    private static func redactCardFields(_ lines: inout [String], isCardForm: Bool) -> Bool {
        var changed = false
        // The label row's fields, for the next two rows.
        var pendingExpiry = false
        var pendingCode = false
        var pendingRows = 0
        for index in lines.indices {
            var line = lines[index]
            guard !line.isEmpty else { continue }
            let before = line
            let hasExpiryLabel = Patterns.expiryLabel.matches(line)
            let hasCodeLabel = Patterns.codeLabel.matches(line)
            Patterns.labeledExpiry.replace(in: &line, with: "$1 " + cardToken)
            Patterns.labeledCode.replace(in: &line, with: "$1 " + cardToken)

            if hasExpiryLabel || hasCodeLabel {
                if !line.contains(where: { $0.isASCII && $0.isNumber }) && line == before {
                    // A label row: its values are on the rows below.
                    pendingExpiry = pendingExpiry || hasExpiryLabel
                    pendingCode = pendingCode || hasCodeLabel
                    pendingRows = 2
                }
            } else if pendingRows > 0 {
                if pendingExpiry || isCardForm { Patterns.expiryValueUnderLabel.replace(in: &line, with: cardToken) }
                if pendingCode, Patterns.digitsOnlyRow.matches(line) {
                    // A card number under a "Card number  CVC" row goes whole, not group by group.
                    Patterns.longDigitRun.replace(in: &line, with: cardToken)
                    Patterns.codeValue.replace(in: &line, with: cardToken)
                }
                pendingRows -= 1
                if pendingRows == 0 { pendingExpiry = false; pendingCode = false }
            }
            if isCardForm {
                Patterns.expiryValue.replace(in: &line, with: cardToken)
            }
            if line != before {
                lines[index] = line
                changed = true
            }
        }
        return changed
    }

    /// On a card form, after its card number and expiry are tokens, the fields with no label next to them (a filled
    /// form's placeholders are gone):
    /// - a row that holds a card number or a `[CARD]` token ("[CARD]  123", "Card number  [CARD]  [CARD]  123"): the
    ///   card number → `[CARD]`, then every 3–4 digit group that is not part of a price (the security code) →
    ///   `[CARD]`;
    /// - a row of digits only, card-field labels and placeholders aside ("123", "123  98000", "MM / YY  123",
    ///   "[CARD]  [CARD]  123  98000"): the same, and a 5-digit or ZIP+4 group (a one-row card element's ZIP) →
    ///   `[ADDRESS]`.
    /// Phone rows are left to the phone rule. Returns the kinds that fired.
    private static func redactCardEntryRows(_ lines: inout [String]) -> Set<Kind> {
        var fired = Set<Kind>()
        for index in lines.indices {
            var line = lines[index]
            let holdsCard = line.contains(cardToken) || Patterns.longDigitRun.matches(line)
            var values = line
            Patterns.cardFieldWord.replace(in: &values, with: " ")
            let digitsOnly = !line.isEmpty && Patterns.digitsOnlyRow.matches(values)
            guard holdsCard || digitsOnly, holdsCard || !Patterns.phone.matches(line) else { continue }
            if Patterns.longDigitRun.replace(in: &line, with: cardToken) { fired.insert(.cardNumber) }
            if digitsOnly, Patterns.zipValue.replace(in: &line, with: addressToken) { fired.insert(.address) }
            if Patterns.codeValue.replace(in: &line, with: cardToken) { fired.insert(.cardNumber) }
            lines[index] = line
        }
        return fired
    }

    /// Replaces each row's part of a 12+ digit run that crosses rows with `[CARD]` ("4111 1111" / "1111 1111" →
    /// "[CARD]" / "[CARD]"). Runs inside one row are left to `longDigitRun`. Address, phone and email rows are left out
    /// of the search, so a ZIP code above a phone number is not taken for a card; their own rules handle them.
    /// Returns whether anything changed.
    private static func redactRunsAcrossRows(_ lines: inout [String]) -> Bool {
        guard lines.count > 1 else { return false }
        var (joined, skipped) = joinedForRuns(lines)
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

    /// The rows joined with newlines for a search across rows, with address, phone and email rows left out (`skipped`)
    /// so a ZIP code above a phone number is not taken for a card. U+0001 never comes out of OCR; it stands in for a
    /// skipped row and breaks any run.
    private static func joinedForRuns(_ lines: [String]) -> (text: String, skipped: [Bool]) {
        let skipped = lines.map { looksLikeAddress($0) || Patterns.phone.matches($0) || $0.contains("@") }
        return (zip(lines, skipped).map { line, skip in skip ? "\u{1}" : line }.joined(separator: "\n"), skipped)
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

    /// A street line ("123 Example St", "1 Infinite Loop"; not an item line with a price), a city line
    /// ("Seattle, WA 98000", "Cupertino, CA, 95014", "Seattle, Washington 98000") or a unit/PO box line.
    static func looksLikeAddress(_ line: String) -> Bool {
        (Patterns.street.matches(line) && !Patterns.money.matches(line))
            || Patterns.cityStateZip.matches(line) || Patterns.cityStateNameZip.matches(line)
            || Patterns.unitOrBox.matches(line) || Patterns.poBox.matches(line)
    }

    /// Inside an address block only: a street with no known suffix ("1600 Broadway Ave" is caught anywhere, "10 Hudson
    /// Yards" or "221 Elm" only here), "Cupertino, CA", or a country line ("United States").
    static func looksLikeAddressPart(_ line: String) -> Bool {
        (Patterns.houseNumberLine.matches(line) && !Patterns.nonAddressWord.matches(line) && !Patterns.money.matches(line))
            || Patterns.cityState.matches(line) || Patterns.country.matches(line)
    }

    /// Two to four capitalised words that are not shop words or a card product ("Alex Doe" yes; "Standard Shipping",
    /// "Visa Card", "Northbay Electronics", "Best Buy", "Chase Freedom Unlimited", "Active Cash" no).
    static func looksLikePersonName(_ text: String, cardNames: [String]? = nil) -> Bool {
        looksLikePersonName(text, CardNames(cardNames ?? catalogCardNames))
    }

    /// Whether `text` names a card product: a card name of two or more words from cards.json ("Active Cash",
    /// "Chase Freedom Rise"), or two or more issuer and product words ("Chase Sapphire", "Capital One Venture").
    static func looksLikeCardProduct(_ text: String, cardNames: [String]? = nil) -> Bool {
        looksLikeCardProduct(text, CardNames(cardNames ?? catalogCardNames))
    }

    private static func looksLikePersonName(_ text: String, _ names: CardNames) -> Bool {
        Patterns.personName.matches(text) && !Patterns.nonNameWord.matches(text) && !looksLikeCardProduct(text, names)
    }

    private static func looksLikeCardProduct(_ text: String, _ names: CardNames) -> Bool {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        guard !words.isEmpty else { return false }
        if words.filter({ names.words.contains($0) }).count >= 2 { return true }
        let padded = " " + words.joined(separator: " ") + " "
        return names.phrases.contains { padded.contains(" " + $0 + " ") }
    }

    /// Card names split for matching: multi-word names and their leading parts of two or more words ("discover it" of
    /// "Discover it Student Cash Back") as lowercase phrases, and every word of 3+ letters of those names plus the
    /// issuer and product-line words cards are sold under.
    private struct CardNames {
        var phrases: [String]
        var words: Set<String>

        /// Issuers and product lines, so a card outside the catalog ("Capital One Venture") is not taken for a person.
        /// Names only, no card terms.
        private static let issuerWords: Set<String> = [
            "chase", "citi", "capital", "wells", "fargo", "amex", "american", "express", "discover", "apple", "bank",
            "barclays", "synchrony", "bilt", "sapphire", "freedom", "venture", "quicksilver", "savor", "platinum",
            "gold", "rewards", "cash", "back", "unlimited", "preferred", "reserve", "active", "rise", "flex",
            "custom", "double", "prime", "student", "secured", "autograph", "card", "visa", "mastercard", "credit",
            "debit",
        ]

        init(_ names: [String]) {
            let split = names.map { $0.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init) }
            phrases = Array(Set(split.flatMap { words in
                words.count < 2 ? [] : (2...words.count).map { words.prefix($0).joined(separator: " ") }
            }))
            words = Self.issuerWords.union(split.joined().filter { $0.count >= 3 })
        }
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
    /// Mask characters, then the last 4: "••5678", "• •5678", "**** 4321", "...1234", ". .1234", "x1234", "XXXX-1234",
    /// and the masks OCR misreads: "#### 4321", "°°°° 5678", "---- 4321", "oooo 5678".
    static let maskedLast4 = Pattern(#"(?:(?:[.•·∙●◦*#°] ?){2,}|[\-–—_]{2,} ?|[•·∙●◦*] ?|\b[xX]{1,4}[ \-]?|\b[oO]{2,4} ?)[0-9]{4}(?![0-9])"#)
    /// A line that names a card or a network.
    static let cardWord = Pattern(#"(?i)\b(visa|master ?card|mastercard|amex|american express|discover|debit|credit|card|pay with|paid with)\b"#)
    /// Any standalone 4-digit group that is not part of a price ("$1499", "1499.00", "1,499").
    static let lineLast4 = Pattern(#"(?<![0-9$,.])[0-9]{4}(?![0-9]|[.,][0-9])"#)
    /// A row that is a last 4 and nothing else ("1234", "(1234)", "• 1234").
    static let bareLast4Row = Pattern(#"^[^A-Za-z0-9]{0,8}[0-9]{4}[^A-Za-z0-9]{0,4}$"#)

    /// A run of digit groups in which OCR may have read some digits as letters (see `Redactor.lookalikeDigits`),
    /// over rows joined with newlines.
    static let lookalikeRun = Pattern(#"(?<![A-Za-z0-9])[0-9OolISBZ|!]+(?:(?:[ \t\n\-–—]|\.(?![0-9]{2}(?![0-9]))){1,5}[0-9OolISBZ|!]+)*(?![A-Za-z0-9])"#)

    // Card-entry fields.
    private static let expiryLabelText = #"(?<![A-Za-z])(?:exp(?:iry|iration|ires)?\.?(?:\s+date)?|valid\s+(?:thru|through|until)|good\s+thru|mm\s?/\s?yy(?:yy)?)(?![A-Za-z])"#
    private static let codeLabelText = #"(?<![A-Za-z])(?:cvc2?|cvv2?|cvn|cid|csc|security\s+code|card\s+(?:verification|security)\s+(?:code|number|value)|verification\s+(?:code|number)|card\s+code)(?![A-Za-z])"#
    /// MM/YY or MM/YYYY ("12/28", "12 / 28", "1/2028"), not part of a full date ("10/17/2026").
    private static let expiryValueText = #"(?<![0-9/.])(?:0?[1-9]|1[0-2])\s{0,2}/\s{0,2}(?:20[0-9]{2}|[0-9]{2})(?![0-9/])"#
    static let expiryLabel = Pattern("(?i)" + expiryLabelText)
    static let codeLabel = Pattern("(?i)" + codeLabelText)
    /// "Exp  12/28", "Expiration date: 12-2028", "Valid thru 12/28", "MM/YY  12/28". Group 1: the label.
    static let labeledExpiry = Pattern(#"(?i)("# + expiryLabelText + #")\s*[:\-]?\s*(?:0?[1-9]|1[0-2])\s{0,2}[/\-]\s{0,2}(?:20[0-9]{2}|[0-9]{2})(?![0-9])"#)
    /// "CVV  123", "Security code: 1234", "CVC2 123". Group 1: the label.
    static let labeledCode = Pattern(#"(?i)("# + codeLabelText + #")\s*[:\-#]?\s*[0-9]{3,4}(?![0-9])"#)
    static let expiryValue = Pattern(expiryValueText)
    /// Under an expiry label the value may also be written with a hyphen ("12-28").
    static let expiryValueUnderLabel = Pattern(#"(?<![0-9/.\-])(?:0?[1-9]|1[0-2])\s{0,2}[/\-]\s{0,2}(?:20[0-9]{2}|[0-9]{2})(?![0-9/\-])"#)
    /// A security code: a standalone 3–4 digit group that is not part of a price or a date ("2026-10-17").
    static let codeValue = Pattern(#"(?<![0-9$.,/])[0-9]{3,4}(?![0-9]|[.,\-][0-9])"#)
    /// A ZIP code on a card row: 5 digits or ZIP+4, not part of a price or a longer number.
    static let zipValue = Pattern(#"(?<![0-9$.,/\-])[0-9]{5}(?:-[0-9]{4})?(?![0-9\-]|[.,][0-9])"#)
    /// A row with no letters (tokens aside) and no price: "123", "[CARD]  123".
    static let digitsOnlyRow = Pattern(#"^(?:\[CARD\]|[^A-Za-z$])*$"#)
    /// A label only a card-entry form has: "Card number", "Card no.", "Card information" (Stripe's one card field),
    /// "Card details", "Cardholder name", "Name on card", the security-code and expiry labels.
    private static let cardFormLabelText = #"(?<![A-Za-z])(?:card\s*(?:number|no\.?|#|information|info|details)|card\s*holder|name\s+on\s+card)(?![A-Za-z])"#
    static let cardFormLabel = Pattern("(?i)" + cardFormLabelText + "|" + codeLabelText + "|" + expiryLabelText)
    /// The labels and placeholders a card field may still show next to its values: the card-form labels and
    /// "ZIP" / "ZIP code" / "Postal code".
    static let cardFieldWord = Pattern("(?i)" + cardFormLabelText + "|" + codeLabelText + "|" + expiryLabelText
                                       + #"|(?<![A-Za-z])(?:zip(?:\s*code)?|postal\s*code|postcode)(?![A-Za-z])"#)
    /// Leftover mask characters right before a token ("••[CARD]", ". . [CARD]").
    static let maskBeforeToken = Pattern(#"(?:\s*[•·∙●◦*.])+\s*\[CARD\]"#)
    /// A token glued to the word before it ("card no[CARD]").
    static let letterBeforeToken = Pattern(#"([A-Za-z])\[CARD\]"#)

    /// "Thank you, Alex." / "Hi Alex" / "Welcome back, Alex".
    static let greetingName = Pattern(#"(?i)\b(thank you|thanks|hi|hello|hey|welcome back|welcome)(,\s*|\s+)(?-i:[A-Z][a-z'\-]+)(?:\s+(?-i:[A-Z][a-z'\-]+))?"#)
    /// "Signed in as Alex Doe": everything after the phrase goes, unless it is already a token ("[EMAIL]").
    static let signedInAs = Pattern(#"(?i)\b(signed in as|logged in as)\s+(?!\[)\S.*$"#)

    /// Labels whose value is a person's name.
    private static let nameLabels = "full name|first name|last name|your name|name on card|cardholder name|cardholder|card holder name|card holder|account holder|customer name|contact name|billing name|recipient name|pickup person|pick up person|pickup name|picked up by|pick up by|order for|gift for|gift recipient|attention|attn|buyer|purchaser|member name|guest name|passenger name|traveler name|traveller name|name"
    /// Labels whose value is an address (a name first, as a rule).
    private static let addressLabels = "ship to|shipping to|deliver to|delivering to|delivery address|shipping address|billing address|bill to|sold to|recipient"
    /// Headers that start a hard block. Group 1: the label; group 2: a colon; group 3: anything after it. Name labels
    /// come first, so "Recipient name" wins over "Recipient".
    static let blockHeader = Pattern(#"(?i)^("# + nameLabels + "|" + addressLabels + #")\b\s*(:)?\s*(.*)$"#)
    /// Hard labels whose value is a person's name.
    static let nameLabel = Pattern("(?i)^(" + nameLabels + ")$")
    /// Hard labels whose value is an address.
    static let addressLabel = Pattern("(?i)^(" + addressLabels + ")$")
    /// Labels that are also ordinary words ("Name brand headphones", "Order for pickup", "Buyer protection"): the
    /// value on the same row goes only after a colon or when it looks like a person's name.
    static let ambiguousLabel = Pattern(#"(?i)^(name|order for|gift for|attention|buyer|purchaser)$"#)
    /// Headers that start a soft block. Same groups as `blockHeader`.
    static let softHeader = Pattern(#"(?i)^(contact(?: info(?:rmation)?| details)?|shipping(?: info(?:rmation)?| details)?|delivery(?: info(?:rmation)?| details)?|billing(?: info(?:rmation)?| details)?|customer(?: info(?:rmation)?| details)?|your account|account|payment(?: method| details| info(?:rmation)?)?|pay with|paid with)\b\s*(:)?\s*(.*)$"#)
    static let softAddressLabel = Pattern(#"(?i)^(shipping|delivery|billing)\b"#)
    static let paymentLabel = Pattern(#"(?i)^(payment|pay with|paid with)\b"#)
    /// "c/o Jamie Doe", "Attn: Alex Doe" inside an address block.
    static let careOf = Pattern(#"(?i)^(?:c/o|attn\.?|attention)\s*:?\s+\S"#)

    /// Labels that end a block rather than belong to it.
    static let sectionLabel = Pattern(#"(?i)^(contact|pay with|paid with|payment|shipping|delivery|billing|customer|account|total|subtotal|order|items?|change|edit|qty)\b"#)
    static let money = Pattern(#"\$\s?[0-9]"#)

    /// Two to four capitalised words, letters only: "Alex Doe", "Mary-Jo O'Neil".
    static let personName = Pattern(#"^[A-Z][a-zA-Z'\-]+(?:\s+[A-Z][a-zA-Z'\-.]*){1,3}$"#)
    /// Words in shop text that are not in a person's name; they keep "Standard Shipping" or "Visa Card" from being
    /// taken for a name inside a soft block.
    static let nonNameWord = Pattern(#"(?i)\b(ship|shipping|shipped|delivery|deliver|delivered|pickup|standard|express|free|ground|overnight|priority|order|orders|total|subtotal|summary|payment|pay|card|visa|master|mastercard|amex|american|discover|debit|credit|apple|google|paypal|change|edit|add|new|save|saved|continue|return|returns|policy|warranty|day|days|store|shop|electronics|inc|llc|support|help|account|sign|signed|log|details|information|info|method|address|email|phone|checkout|cart|item|items|qty|place|placed|renewed|refurbished|buy|athletics|outlet|market|pharmacy|supply|goods|company|co|coffee|pickup|pick|arrive|arrives|arriving|service|services|team)\b"#)

    /// Street suffixes, long and short.
    private static let streetSuffixes = [
        "st", "street", "ave", "avenue", "rd", "road", "blvd", "boulevard", "dr", "drive", "ln", "lane", "way", "ct",
        "court", "pl", "place", "pkwy", "parkway", "hwy", "highway", "ter", "terrace", "cir", "circle", "sq", "square",
        "loop", "trail", "trl", "plaza", "plz", "row", "pike", "alley", "aly", "crescent", "cres", "expressway", "expy",
        "freeway", "fwy", "turnpike", "tpke", "broadway", "yards", "crossing", "xing", "commons", "heights", "hts",
        "landing", "ridge", "grove", "mews",
    ]
    /// "123 Example St", "4 Main Street", "1600 Pennsylvania Ave NW", "1 Infinite Loop", "2 Park Plaza".
    static let street = Pattern(#"(?i)(?<![0-9A-Za-z$.,])[0-9]{1,6}[A-Za-z]?\s+(?:[A-Za-z0-9.'\-]+\s+){0,4}(?:"#
                                + streetSuffixes.joined(separator: "|") + #")\b"#)
    /// "Seattle, WA 98000", "WA 98000-1234", "CUPERTINO, CA, 95014-2083".
    static let cityStateZip = Pattern(#"(?:\b[A-Za-z][A-Za-z .'\-]*,\s*)?\b[A-Z]{2},?\s+[0-9]{5}(?:-[0-9]{4})?\b"#)
    /// "Seattle, Washington 98000", "Concord, New Hampshire 03301".
    static let cityStateNameZip = Pattern(#"\b[A-Z][A-Za-z .'\-]*,\s*[A-Z][A-Za-z]+(?:\s[A-Z][A-Za-z]+){0,2}\s+[0-9]{5}(?:-[0-9]{4})?(?![0-9])"#)
    /// Inside a block only: a line that ends in a ZIP code ("Seattle Washington 98000").
    static let zipAtEnd = Pattern(#"[A-Za-z][A-Za-z .,'\-]*\s[0-9]{5}(?:-[0-9]{4})?$"#)
    /// "Apt 4", "Suite 200", "Unit 5B", "Apt B" (not "Unit price").
    static let unitOrBox = Pattern(#"(?i)^(?:apt|apartment|suite|ste|unit|bldg|building)\.?\s*#?\s*(?:[0-9][0-9A-Za-z\-]*|[A-Za-z](?![A-Za-z]))"#)
    /// "PO Box 123", "P.O. Box 123", "Post Office Box 123", anywhere on the line.
    static let poBox = Pattern(#"(?i)\b(?:p\.?\s?o\.?\s?box|post\s+office\s+box)\s*#?\s*[0-9]+"#)

    // Inside an address block only.
    /// A house number and a street name with no known suffix: "1600 Broadway", "10 Hudson Yards", "221B Baker".
    static let houseNumberLine = Pattern(#"^[0-9]{1,6}[A-Za-z]?(?:-[0-9]{1,4})?\s+[A-Za-z][A-Za-z.'\-]*(?:\s+[A-Za-z0-9.'\-#,]+){0,5}$"#)
    /// Words that make a "2 day shipping", "8 AM - 12 PM" or "1 item" line, not a street.
    static let nonAddressWord = Pattern(#"(?i)\b(am|pm|noon|day|days|week|weeks|month|months|year|years|yr|yrs|hour|hours|hr|hrs|min|mins|minute|minutes|business|delivery|deliveries|shipping|ship|ships|shipped|arrive|arrives|arriving|item|items|qty|x|pack|pk|count|pcs|piece|pieces|oz|lb|lbs|inch|inches|in|ft|gb|tb|mb|left|stock|review|reviews|rating|ratings|star|stars|off|free|warranty|plan|protection|of|more|less)\b"#)
    /// "Cupertino, CA", "Seattle, WA".
    static let cityState = Pattern(#"^[A-Za-z][A-Za-z .'\-]*,\s*[A-Z]{2}$"#)
    static let country = Pattern(#"(?i)^(?:united states(?: of america)?|usa|u\.s\.a?\.?|us|canada|united kingdom|uk|mexico)$"#)

    // Typed text (`redactFreeText`): only capitalised street and city words count, so "2 days ago on the way home" or
    // "walking home in Seattle, WA 98000" keep their other words.
    /// "1 Infinite Loop", "123 Example St".
    static let typedStreet = Pattern(#"(?<![0-9A-Za-z$.,])[0-9]{1,6}[A-Za-z]?\s+(?:[A-Z0-9][A-Za-z0-9.'\-]*\s+){0,4}(?:"#
                                     + streetSuffixes.map { suffix in
                                         suffix.prefix(1).uppercased() + "(?i:" + suffix.dropFirst() + ")"
                                     }.joined(separator: "|") + #")\b"#)
    /// "Seattle, WA 98000", "Cupertino CA, 95014".
    static let typedCityStateZip = Pattern(#"(?:\b[A-Z][A-Za-z.'\-]*(?:\s[A-Z][A-Za-z.'\-]*){0,2},?\s*)?\b[A-Z]{2},?\s+[0-9]{5}(?:-[0-9]{4})?\b"#)
    /// "Seattle, Washington 98000".
    static let typedCityStateNameZip = Pattern(#"\b[A-Z][A-Za-z.'\-]*(?:\s[A-Z][A-Za-z.'\-]*){0,2},\s*[A-Z][A-Za-z]+(?:\s[A-Z][A-Za-z]+){0,2}\s+[0-9]{5}(?:-[0-9]{4})?(?![0-9])"#)
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

    /// The text of every match, in order.
    func allMatches(in text: String) -> [String] {
        expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
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
