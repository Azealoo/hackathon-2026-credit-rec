import ActivityKit
import Foundation

/// The Paywise Live Activity (SPEC §6, §15.5). Compiled into both the app and the widget extension.
/// Mirrors `contracts/live-activity-content-state.schema.json`; the static part is just the check ID.
struct PaywiseActivityAttributes: ActivityAttributes {
    let checkId: String

    /// Dynamic state, well under ActivityKit's 4 KB limit.
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case checking
            case keep
            case noCheckout = "no_checkout"
            case error
            case switchFallback = "switch_fallback"
        }

        /// Wire values come from the contract; `app` is the Paywise glyph (`"fp"` on the wire).
        enum Glyph: String, Codable, Hashable {
            case app = "fp"
            case check
            case warning
            case card
        }

        var phase: Phase
        var glyph: Glyph
        var cardShortName: String?
        var last4: String?
        var line1: String
        var line2: String?
        /// No card, amount or store (§6.4).
        var lockScreenText: String
    }
}

extension PaywiseActivityAttributes.ContentState {
    /// The *Checking* state from SPEC §6.3.
    static let checking = Self(
        phase: .checking,
        glyph: .app,
        cardShortName: nil,
        last4: nil,
        line1: "Reading this screen…",
        line2: "Only the order summary leaves your phone",
        lockScreenText: "Paywise is checking"
    )
}

extension PaywiseActivityAttributes.ContentState.Glyph {
    /// SF Symbol stand-ins until the team-made art lands (§6.4).
    var systemImage: String {
        switch self {
        case .app: "creditcard.fill"
        case .check: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .card: "creditcard"
        }
    }
}
