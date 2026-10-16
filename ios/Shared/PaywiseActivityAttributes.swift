import ActivityKit
import Foundation

/// The Paywise Live Activity (SPEC §6, §15.5). Compiled into both the app and the widget extension.
/// Mirrors `contracts/live-activity-content-state.schema.json`; the static part is just the check ID.
struct PaywiseActivityAttributes: ActivityAttributes {
    let checkId: String

    /// Dynamic state, well under ActivityKit's 4 KB limit.
    struct ContentState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Hashable, Sendable {
            case checking
            case keep
            case noCheckout = "no_checkout"
            case error
            case switchFallback = "switch_fallback"
        }

        /// Wire values come from the contract; `paywise` is the Paywise glyph (the island mark, `PaywiseGlyphMark`).
        enum Glyph: String, Codable, Hashable, Sendable {
            case paywise
            case check
            case warning
            case card
        }

        var phase: Phase
        var glyph: Glyph
        /// The card whose art the island shows (§9.1: send a `cardId`, not an image). Keep and the switch fallback.
        var cardId: String?
        var cardShortName: String?
        var last4: String?
        var line1: String
        var line2: String?
        /// Optional third line: the switch fallback and the on-device no-checkout state (§6.3).
        var line3: String?
        /// No card, amount or store (§6.4).
        var lockScreenText: String

        init(
            phase: Phase,
            glyph: Glyph,
            cardId: String? = nil,
            cardShortName: String? = nil,
            last4: String? = nil,
            line1: String,
            line2: String? = nil,
            line3: String? = nil,
            lockScreenText: String
        ) {
            self.phase = phase
            self.glyph = glyph
            self.cardId = cardId
            self.cardShortName = cardShortName
            self.last4 = last4
            self.line1 = line1
            self.line2 = line2
            self.line3 = line3
            self.lockScreenText = lockScreenText
        }

        private enum CodingKeys: String, CodingKey {
            case phase, glyph, cardId, cardShortName, last4, line1, line2, line3, lockScreenText
        }

        // The contract requires cardShortName, last4 and line2 as keys (null allowed); cardId and line3 are optional.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(phase, forKey: .phase)
            try container.encode(glyph, forKey: .glyph)
            try container.encodeIfPresent(cardId, forKey: .cardId)
            try container.encode(cardShortName, forKey: .cardShortName)
            try container.encode(last4, forKey: .last4)
            try container.encode(line1, forKey: .line1)
            try container.encode(line2, forKey: .line2)
            try container.encodeIfPresent(line3, forKey: .line3)
            try container.encode(lockScreenText, forKey: .lockScreenText)
        }
    }
}

extension PaywiseActivityAttributes.ContentState {
    static let checkingLockScreenText = "Paywise is checking"
    static let checkedLockScreenText = "Paywise checked this screen"

    /// The *Checking* state from SPEC §6.3.
    static let checking = Self(
        phase: .checking,
        glyph: .paywise,
        line1: "Reading this screen…",
        line2: "Only the order summary leaves your phone",
        lockScreenText: checkingLockScreenText
    )
}
