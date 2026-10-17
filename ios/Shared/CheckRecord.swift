import Foundation

/// One check, stored at `<AppGroup>/checks/<checkId>.json` (SPEC §15.5, `contracts/check-record.schema.json`).
/// Written by `CheckCheckoutIntent`; the snippet intents read it, `SavePurchaseIntent` / `ShowSentIntent` update it.
struct CheckRecord: Codable, Sendable, Equatable, Identifiable {
    /// Which of the three snippet views shows (§6.3).
    enum Screen: String, Codable, Sendable {
        case result, saved, sent
    }

    /// The response copy with `{last4:…}` and `{ppCap}` filled on the phone.
    struct FilledCopy: Codable, Sendable, Equatable {
        var line1: String
        var line2: String?
        var line3: String?
        var instruction: String?
    }

    var checkId: String
    /// ISO 8601 with the local offset, e.g. "2026-10-17T14:02:11-07:00".
    var createdAt: String
    /// The exact `/v1/check` request JSON.
    var sentPayload: JSONValue
    /// The `/v1/check` response JSON as received (or replayed, or the phone's own error shape).
    var response: JSONValue
    var filledCopy: FilledCopy
    var replayed: Bool
    var savedPurchaseId: String?
    var view: Screen
    /// What `OfferResolver` changed using the user's offer answers (offers design D1). Device only, never sent;
    /// nil when no offer applied. `response` stays exactly as received.
    var offerAdjustment: OfferAdjustment?

    var id: String { checkId }

    private enum CodingKeys: String, CodingKey {
        case checkId, createdAt, sentPayload, response, filledCopy, replayed, savedPurchaseId, view, offerAdjustment
    }

    init(
        checkId: String, createdAt: String, sentPayload: JSONValue, response: JSONValue,
        filledCopy: FilledCopy, replayed: Bool, savedPurchaseId: String? = nil, view: Screen = .result,
        offerAdjustment: OfferAdjustment? = nil
    ) {
        self.checkId = checkId
        self.createdAt = createdAt
        self.sentPayload = sentPayload
        self.response = response
        self.filledCopy = filledCopy
        self.replayed = replayed
        self.savedPurchaseId = savedPurchaseId
        self.view = view
        self.offerAdjustment = offerAdjustment
    }

    // `savedPurchaseId` is a required key that may be null.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(checkId, forKey: .checkId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(sentPayload, forKey: .sentPayload)
        try container.encode(response, forKey: .response)
        try container.encode(filledCopy, forKey: .filledCopy)
        try container.encode(replayed, forKey: .replayed)
        try container.encode(savedPurchaseId, forKey: .savedPurchaseId)
        try container.encode(view, forKey: .view)
        try container.encodeIfPresent(offerAdjustment, forKey: .offerAdjustment)
    }
}

/// `check-record.schema.json#/$defs/offerAdjustment`: the decision and purchase the phone shows after applying the
/// user's offers, and what each offer added.
struct OfferAdjustment: Codable, Sendable, Equatable {
    struct Applied: Codable, Sendable, Equatable {
        var offerId: String
        var cardId: String
        /// Cash the offer added on that card, over the card's public rate (cents).
        var extraUsd: Double
    }

    var decision: CheckResponse.Decision
    var purchaseDraft: CheckResponse.PurchaseDraft?
    var appliedOffers: [Applied]
    var changedDecision: Bool

    private enum CodingKeys: String, CodingKey { case decision, purchaseDraft, appliedOffers, changedDecision }

    init(decision: CheckResponse.Decision, purchaseDraft: CheckResponse.PurchaseDraft?, appliedOffers: [Applied],
         changedDecision: Bool) {
        self.decision = decision
        self.purchaseDraft = purchaseDraft
        self.appliedOffers = appliedOffers
        self.changedDecision = changedDecision
    }

    // `purchaseDraft` is a required key that may be null.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(decision, forKey: .decision)
        try container.encode(purchaseDraft, forKey: .purchaseDraft)
        try container.encode(appliedOffers, forKey: .appliedOffers)
        try container.encode(changedDecision, forKey: .changedDecision)
    }
}

extension CheckRecord {
    /// The request as a typed model (nil only if the stored JSON was edited by hand).
    var request: CheckRequest? { try? sentPayload.decode(CheckRequest.self) }

    /// The response as a typed, tolerant model, with the phone's offer adjustment (if any) in place of the server's
    /// decision and purchase draft: what the snippet shows and [Paying with …] saves.
    var parsedResponse: CheckResponse {
        var parsed = serverResponse
        if let offerAdjustment {
            parsed.decision = offerAdjustment.decision
            parsed.purchaseDraft = offerAdjustment.purchaseDraft
        }
        return parsed
    }

    /// The response exactly as received (or replayed).
    var serverResponse: CheckResponse { (try? response.decode(CheckResponse.self)) ?? CheckResponse() }

    /// The exact redacted text that was sent (§6.3 *Sent*).
    var sentText: String { sentPayload["screen"]?["ocrText"]?.stringValue ?? "" }

    /// Every other field of `sentPayload`, one `path: value` line each with the value as it was sent (its JSON),
    /// in the body's own key order (sorted): the card IDs and `isDefault`, `clientDate`, the redaction kinds, and
    /// the rest. "What we sent" shows these under `sentText`, so it shows the exact payload (§10), not a summary.
    var sentFields: [String] { Self.fieldLines(sentPayload, path: "").filter { !$0.hasPrefix("screen.ocrText: ") } }

    private static func fieldLines(_ value: JSONValue, path: String) -> [String] {
        switch value {
        case .object(let object):
            if object.isEmpty { return path.isEmpty ? [] : ["\(path): {}"] }
            return object.keys.sorted().flatMap { key in
                fieldLines(object[key] ?? .null, path: path.isEmpty ? key : "\(path).\(key)")
            }
        case .array(let items) where items.contains(where: \.isContainer):
            return items.enumerated().flatMap { index, item in fieldLines(item, path: "\(path)[\(index)]") }
        default:
            return ["\(path): \(json(value))"]
        }
    }

    /// One value as the request body has it (the same encoder).
    private static func json(_ value: JSONValue) -> String {
        (try? value.data()).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }

    var createdDate: Date? { CheckRecord.timestamp(from: createdAt) }

    static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func timestamp(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}
