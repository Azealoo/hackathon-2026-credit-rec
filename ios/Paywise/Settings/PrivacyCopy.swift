import Foundation

/// SPEC §10 copy, verbatim. Change it only when SPEC.md changes.
enum PrivacyCopy {
    /// §10 "Onboarding privacy copy" (three lines).
    static let onboardingLines = [
        "We only look when you press. Never in the background.",
        "Card numbers, names and addresses are removed on your iPhone first.",
        "Only that redacted order summary is sent for analysis; our AI provider (Anthropic) deletes it within 30 days and doesn't train on it.",
    ]

    /// §10 "Consent screen" copy: names the AI provider and its retention.
    static let consent = """
    Paywise sends only a redacted order summary, such as "Northbay Electronics, Aero 14 Laptop (New), $1,499.00, \
    Mastercard", to Anthropic's Claude API so it can read the items and prices. Card numbers, names and addresses are \
    removed on your iPhone first, and your screenshot never leaves your phone. Anthropic doesn't use this text to train \
    its models. It deletes API inputs and outputs within 30 days, and can keep them longer, up to 2 years, if its safety \
    systems flag them. Tap "What we sent" any time to see exactly what was sent.
    """

    /// §10 "Retention copy".
    static let retention = """
    Screenshots are processed in memory and never saved. Purchases you save stay until you delete them. Our AI \
    provider, Anthropic, may keep the redacted order text for up to 30 days, and longer if its safety systems flag it. \
    It isn't used for model training.
    """

    /// §10 "Disclaimer", with "[date]" filled from the bundled cards.json `catalogVersion` (the day its card terms were
    /// last checked), e.g. "Oct 15, 2026".
    static func disclaimer(catalog: CardCatalog) -> String {
        guard let checked = catalog.catalogVersion.flatMap(Day.medium) else {
            // No date to show: the parenthesis goes rather than a visible "[date]".
            return disclaimerTemplate.replacingOccurrences(of: " (last checked [date])", with: "")
        }
        return disclaimerTemplate.replacingOccurrences(of: "[date]", with: checked)
    }

    static let disclaimerTemplate = """
    Estimates only, not financial, legal or insurance advice. Values use public card terms (last checked [date]) and \
    the assumptions shown. Paywise can't see your caps, activations or balances. Warranty and purchase protection are \
    insurance benefits with limits and exclusions; only your card's benefit administrator decides claims. If you carry \
    a balance, interest will likely cost more than any reward. Not affiliated with or paid by any issuer.
    """
}
