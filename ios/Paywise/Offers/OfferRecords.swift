import Foundation
import Synchronization

/// The user's answers about catalog offers (offers design D1): device only, in the App Group, never sent. `/v1/check`
/// carries none of this (its request schema rejects unknown fields); `OfferResolver` reads it after the response.
struct OfferRecords: Codable, Sendable, Equatable {
    /// By card id: one wallet card is one account.
    var cards: [String: CardFacts] = [:]

    func facts(_ cardId: String) -> CardFacts { cards[cardId] ?? CardFacts() }

    func state(cardId: String, offerId: String) -> OfferState? { cards[cardId]?.offers[offerId] }
}

/// Yes / No / Not sure. "Not sure" counts as No: an offer never applies on a guess.
enum OfferAnswer: String, Codable, Sendable, CaseIterable {
    case yes, no
    case notSure = "not_sure"
}

/// One catalog offer on one card: the one-tap answer to its `confirmQuestion`, and what the cap has used.
struct OfferState: Codable, Sendable, Equatable {
    var answer: OfferAnswer
    /// yyyy-MM-dd the user answered.
    var answeredOn: String
    /// yyyy-MM-dd; set on a Yes to an activation question (the day of the answer unless the user says otherwise).
    var activatedOn: String?
    /// Spend already counted toward the offer's cap this period, as the user entered it. nil: unknown, so the
    /// resolver uses the whole cap at medium confidence and states no dollar figure.
    var spentTowardCapUsd: Decimal?
    /// The variant the user holds in an `exclusiveGroup` (targeted gas OR grocery).
    var chosenVariant: String?
}

/// What only the cardholder knows about one account.
struct CardFacts: Codable, Sendable, Equatable {
    /// yyyy-MM: the month the account opened (the month is enough; windows then count from the 1st, so they end
    /// early, never late).
    var openedOn: String?
    /// Catalog offer answers, by offer id. A Yes to an `acquisition_offer` question means the account was opened
    /// under that offer.
    var offers: [String: OfferState] = [:]
    /// Catalog event answers, by event id ("Is your Discover card in the Capital One app?").
    var events: [String: OfferState] = [:]

    var openedUnderOfferIds: [String] { offers.filter { $0.value.answer == .yes }.map(\.key).sorted() }
}

/// `<AppGroup>/offers/state.json`. Thread-safe within a process; written atomically with complete-until-first-unlock
/// protection, so a Back Tap check on an unlocked phone can read it.
final class OfferStore: Sendable {
    let fileURL: URL
    private let lock = Mutex(())

    init(containerURL: URL) {
        fileURL = containerURL.appending(path: "offers", directoryHint: .isDirectory)
            .appending(path: "state.json", directoryHint: .notDirectory)
    }

    static let appGroup = OfferStore(containerURL: AppGroup.containerURL)

    /// The stored answers; empty when there are none or the file can't be read.
    func load() -> OfferRecords {
        lock.withLock { _ in Self.read(fileURL) }
    }

    /// Atomically loads, changes and saves the answers.
    @discardableResult
    func update(_ body: (inout OfferRecords) -> Void) throws -> OfferRecords {
        try lock.withLock { _ in
            var records = Self.read(fileURL)
            body(&records)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONCoding.encoder.encode(records).write(
                to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            return records
        }
    }

    /// Settings > "Delete all offer answers".
    func removeAll() {
        lock.withLock { _ in try? FileManager.default.removeItem(at: fileURL) }
    }

    private static func read(_ url: URL) -> OfferRecords {
        guard let data = try? Data(contentsOf: url) else { return OfferRecords() }
        return (try? JSONDecoder().decode(OfferRecords.self, from: data)) ?? OfferRecords()
    }
}
