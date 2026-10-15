import Foundation

/// The bundled `data/cards.json` (SPEC §15.3), the app's single source for card names, art and protection limits.
/// Only the fields the phone uses are decoded, each one optional, so catalog edits on the data side don't break it.
struct CardCatalog: Sendable {
    struct Card: Decodable, Sendable, Identifiable, Equatable {
        struct Art: Decodable, Sendable, Equatable {
            var assetName: String?
            var color: String?
        }

        struct Limits: Decodable, Sendable, Equatable {
            var perItemUsd: Double?
            var perClaimUsd: Double?
            var perAccountUsd: Double?
            var appliesTo: LimitAppliesTo?
        }

        struct Verification: Decodable, Sendable, Equatable {
            var status: VerificationStatus?
        }

        struct Protection: Decodable, Sendable, Equatable {
            var type: ProtectionType?
            var windowDays: Int?
            var extendsByMonths: Int?
            var limits: Limits?
            var verification: Verification?
        }

        var id: String
        var displayName: String?
        var shortName: String?
        var network: CardNetwork?
        var art: Art?
        var protections: [Protection]?
    }

    struct Merchant: Decodable, Sendable, Equatable {
        var id: String
        var names: [String]?
    }

    var catalogVersion: String?
    var cards: [Card]
    var merchants: [Merchant]

    /// Loads `cards.json` from the app bundle. A missing or unreadable file gives an empty catalog
    /// (names fall back to card IDs) rather than a crash inside a background intent.
    static func bundled(_ bundle: Bundle = .main) -> CardCatalog {
        guard let url = bundle.url(forResource: "cards", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(CardCatalog.self, from: data)
        else { return CardCatalog(catalogVersion: nil, cards: [], merchants: []) }
        return catalog
    }

    func card(_ id: String?) -> Card? {
        guard let id else { return nil }
        return cards.first { $0.id == id }
    }

    /// `shortName` from cards.json, e.g. "Freedom".
    func shortName(_ id: String?) -> String? {
        card(id)?.shortName ?? card(id)?.displayName
    }

    /// The verified purchase-protection cap for `{ppCap}`: per item or per claim, as the protection says it applies.
    func verifiedPurchaseProtectionCap(cardId: String?) -> Double? {
        guard let protection = card(cardId)?.protections?.first(where: { $0.type == .purchaseProtection }),
              protection.verification?.status == .verified,
              let limits = protection.limits
        else { return nil }
        switch limits.appliesTo {
        case .claim: return limits.perClaimUsd ?? limits.perItemUsd
        default: return limits.perItemUsd ?? limits.perClaimUsd
        }
    }

    /// The merchant whose name appears in `text` (case-insensitive, whole words). The earliest match wins, then the
    /// longest name, so "Northbay Electronics … Apple Pay" is Northbay, not Apple.
    func merchantId(in text: String) -> String? {
        var best: (id: String, offset: Int, length: Int)?
        for merchant in merchants {
            for name in merchant.names ?? [] where !name.isEmpty {
                guard let range = Self.wordRange(of: name, in: text) else { continue }
                let offset = text.distance(from: text.startIndex, to: range.lowerBound)
                if best == nil || offset < best!.offset || (offset == best!.offset && name.count > best!.length) {
                    best = (merchant.id, offset, name.count)
                }
            }
        }
        return best?.id
    }

    private static func wordRange(of name: String, in text: String) -> Range<String.Index>? {
        let pattern = "(?<![A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: name) + "(?![A-Za-z0-9])"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive])
    }
}

extension CardCatalog: Decodable {
    private enum CodingKeys: String, CodingKey { case catalogVersion, cards, merchants }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        catalogVersion = container.tolerant(String.self, .catalogVersion)
        cards = (container.tolerant([Lossy<Card>].self, .cards) ?? []).compactMap(\.value)
        merchants = (container.tolerant([Lossy<Merchant>].self, .merchants) ?? []).compactMap(\.value)
    }
}

/// Decodes one array element, or nil if that element is malformed, so one bad entry doesn't drop the rest.
struct Lossy<Value: Decodable & Sendable>: Decodable, Sendable {
    var value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
