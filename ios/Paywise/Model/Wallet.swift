import Foundation

/// The user's cards, in wallet order; the first card is the default (SPEC §15.4). The engine compares against the card
/// selected on screen when its network names one wallet card, else against the default (SPEC §7.2, baseline).
/// `last4` is optional and stays on the phone: it fills `{last4:<cardId>}` and is never sent.
struct Wallet: Codable, Sendable, Equatable {
    struct Card: Codable, Sendable, Equatable {
        var cardId: String
        var isDefault: Bool
        var last4: String?
    }

    var cards: [Card]

    /// §15.4 `demo-3card`: Apple Card ••5678 (default), Active Cash ••4321, Freedom ••1234. Obviously fake last 4.
    static let demo3Card = Wallet(cards: [
        Card(cardId: "apple-card", isDefault: true, last4: "5678"),
        Card(cardId: "wf-active-cash", isDefault: false, last4: "4321"),
        Card(cardId: "chase-freedom-unlimited", isDefault: false, last4: "1234"),
    ])

    func last4(for cardId: String?) -> String? {
        guard let cardId, let last4 = cards.first(where: { $0.cardId == cardId })?.last4,
              last4.count == 4, last4.allSatisfy(\.isASCII), last4.allSatisfy(\.isNumber)
        else { return nil }
        return last4
    }

    var defaultCardId: String? { cards.first(where: \.isDefault)?.cardId ?? cards.first?.cardId }

    /// The wallet as `/v1/check` sends it: card IDs and the default flag only.
    var requestCards: [CheckRequest.WalletCard] {
        let defaultId = defaultCardId
        return cards.map { CheckRequest.WalletCard(cardId: $0.cardId, isDefault: $0.cardId == defaultId) }
    }
}

/// The wallet in App Group `UserDefaults` (key "wallet"); seeded with the demo wallet on first read.
struct WalletStore: Sendable {
    var settings: PaywiseSettings

    func load() -> Wallet {
        let defaults = settings.defaults
        if let data = defaults.data(forKey: PaywiseSettings.Key.wallet),
           let wallet = try? JSONDecoder().decode(Wallet.self, from: data),
           !wallet.cards.isEmpty {
            return wallet
        }
        save(.demo3Card)
        return .demo3Card
    }

    func save(_ wallet: Wallet) {
        if let data = try? JSONEncoder().encode(wallet) {
            settings.defaults.set(data, forKey: PaywiseSettings.Key.wallet)
        }
    }
}
