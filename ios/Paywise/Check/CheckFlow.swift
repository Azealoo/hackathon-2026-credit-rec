import Foundation
import os

/// Steps 1–6 of `CheckCheckoutIntent` (SPEC §9.1, §15.5) and the choice of what step 7 shows.
/// The intent itself only turns the `Outcome` into a snippet, a confirmation or an island alert.
struct CheckFlow: Sendable {
    typealias State = PaywiseActivityAttributes.ContentState

    var deps: AppDependencies

    /// What the intent shows at the end.
    enum Outcome: Sendable, Equatable {
        /// The intent ran with no image (§6.3 *Not set up*).
        case notSetUp
        /// Pattern A: end the activity, return `CheckResultSnippetIntent(checkId:)`.
        case snippet(checkId: String)
        /// Pattern B: end the activity, `requestConfirmation` with a custom verb.
        case confirm(checkId: String, actionName: String)
        /// An alerting island update, held, then ended `.immediate`.
        case island(IslandAlert)
    }

    struct IslandAlert: Sendable, Equatable {
        var checkId: String
        var state: State
        var sound: AlertSoundChoice
        var hold: Duration
        /// A `CheckRecord` exists, so the no-island fallback can show it as a snippet.
        var hasRecord: Bool
    }

    private static let log = Logger(subsystem: "com.azealoo.paywise", category: "check")

    // MARK: Steps 1–6

    func run(imageData: Data?) async -> Outcome {
        let checkId = RequestID.make()

        // 1. End any Paywise activity.
        await deps.island.endAll()
        guard let imageData else { return .notSetUp }

        // 2. Start *Checking*; if ActivityKit refuses, carry on without it (§6.6).
        _ = await deps.island.startChecking(checkId: checkId)

        // 3–4. Crop, OCR, gate and redaction, all on the phone.
        let reader = deps.screenReader
        let reading: ScreenReading
        do {
            reading = try await withDeadline(deps.readTimeout) { try await reader.read(imageData) }
        } catch {
            // No total was read and nothing was sent: §6.3 *No checkout, on device*.
            Self.log.error("Screen reading failed: \(String(describing: error), privacy: .public)")
            return .island(onDeviceAlert(checkId: checkId, state: Self.noCheckoutOnDevice))
        }
        guard reading.isCheckout else {
            // Nothing is uploaded from a screen that isn't a checkout (§10).
            return .island(onDeviceAlert(checkId: checkId, state: Self.noCheckoutOnDevice))
        }

        // 5. POST /v1/check (6.0 s); on failure, replay or *Couldn't check*.
        let wallet = deps.walletStore.load()
        let request = makeRequest(checkId: checkId, reading: reading, wallet: wallet)
        guard let body = try? JSONCoding.encoder.encode(request), PrivacyGuard.isSendable(body) else {
            // The body would break the backend's privacy rule (or didn't encode): it is never sent, so the answer
            // is §6.3 *No checkout, on device*, not the backend's privacy_rejected.
            Self.log.error("The check body failed the on-device privacy check; nothing was sent.")
            return .island(onDeviceAlert(checkId: checkId, state: Self.noCheckoutOnDevice))
        }
        let (responseJSON, replayed) = await fetch(body: body, checkId: checkId, ocrText: request.screen.ocrText)

        // 6. Write the CheckRecord.
        let response = (try? responseJSON.decode(CheckResponse.self)) ?? CheckResponse()
        let filled = CopyFill.fill(
            response.decision?.copy,
            wallet: wallet,
            ppCap: CopyFill.ppCap(decision: response.decision, catalog: deps.catalog)
        )
        let record = CheckRecord(
            checkId: checkId,
            createdAt: CheckRecord.timestamp(deps.now(), timeZone: deps.timeZone),
            sentPayload: (try? JSONValue(data: body)) ?? .null,
            response: responseJSON,
            filledCopy: filled,
            replayed: replayed
        )
        var stored = true
        do {
            try deps.checkStore.write(record, now: deps.now())
        } catch {
            stored = false
            Self.log.error("Couldn't write the check record: \(String(describing: error), privacy: .public)")
        }

        // 7 (decided here, shown by the intent).
        return present(record: record, decision: response.decision, wallet: wallet, stored: stored)
    }

    // MARK: Request

    func makeRequest(checkId: String, reading: ScreenReading, wallet: Wallet) -> CheckRequest {
        let screen = PrivacyGuard.scrub(
            reading,
            walletLast4: wallet.cards.compactMap { wallet.last4(for: $0.cardId) },
            cardNames: deps.catalog.cards.flatMap { [$0.shortName, $0.displayName].compactMap { $0 } }
        )
        return CheckRequest(
            requestId: checkId,
            client: .init(app: "paywise-ios", version: Self.appVersion),
            // "Pretend today is…" (Settings) moves the purchase date, and so the coverage dates, with it.
            clientDate: deps.settings.dateOverrideDay ?? Self.clientDate(deps.now(), timeZone: deps.timeZone),
            screen: .init(
                ocrText: screen.text, redactions: screen.redactions,
                ocrConfidence: Self.wireConfidence(reading.ocrConfidence)
            ),
            wallet: .init(cards: wallet.requestCards),
            prefs: .init(paysInFull: nil)
        )
    }

    /// The OCR confidence as sent: clamped to 0...1 and rounded to 2 places. A Vision confidence is a `Float`, and
    /// widened to `Double` it encodes as e.g. 0.9300000071525574, a 16-digit run the backend rejects (§9.2).
    /// n / 100 for a whole n always encodes with at most 2 decimals.
    static func wireConfidence(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (min(max(value, 0), 1) * 100).rounded() / 100
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    /// yyyy-MM-dd in the phone's time zone.
    static func clientDate(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: Fetch

    /// The response JSON and whether it was replayed.
    private func fetch(body: Data, checkId: String, ocrText: String) async -> (JSONValue, Bool) {
        let failure: PaywiseAPI.Failure
        do {
            let reply = try await deps.api.postCheck(body)
            let json = try? JSONValue(data: reply.body)
            let parsed = json.flatMap { try? $0.decode(CheckResponse.self) }
            let kind = parsed?.decision?.kind
            if (400..<500).contains(reply.status) || kind == .error {
                // R16: the server refused the request (bad_request, privacy_rejected, 429) or answered with its error
                // shape. The phone shows its own §6.3 *Couldn't check* copy, never the server's, and doesn't replay:
                // the server did answer, so this isn't a connection failure.
                Self.log.error("The server refused the check: HTTP \(reply.status, privacy: .public)")
                return (Self.rejectedResponse(checkId: checkId, code: parsed?.error?.code), false)
            }
            if let json, let kind, kind != .unrecognized, (200..<300).contains(reply.status) {
                return (json, false)
            }
            failure = .server(status: reply.status)
        } catch {
            failure = error
        }

        if deps.settings.replayEnabled,
           let key = ReplayStore.key(for: ocrText, catalog: deps.catalog),
           let data = deps.replay.response(for: key),
           let json = try? JSONValue(data: data) {
            Self.log.notice("Replayed \(key.fileName, privacy: .public) after \(String(describing: failure), privacy: .public)")
            return (json, true)
        }
        return (Self.couldntCheckResponse(checkId: checkId, failure: failure), false)
    }

    /// The phone's own error-shape response for *Couldn't check* (§6.3), so the record stays schema-valid.
    static func couldntCheckResponse(checkId: String, failure: PaywiseAPI.Failure) -> JSONValue {
        let timedOut = failure == .timeout
        return errorResponse(
            checkId: checkId,
            line2: timedOut ? Self.tookTooLong : Self.noConnection,
            code: timedOut ? .timeout : .serverError,
            message: timedOut ? "No answer within 6 seconds." : "The request didn't reach the server or failed there."
        )
    }

    /// R16: a 4xx (or the server's error shape) shows *Couldn't check* with "Something went wrong · press again".
    /// The stored error code is the server's when it is one the contract knows, else bad_request.
    static func rejectedResponse(checkId: String, code: APIErrorCode?) -> JSONValue {
        let known: APIErrorCode = switch code {
        case .some(.unrecognized), .none: .badRequest
        case .some(let code): code
        }
        return errorResponse(
            checkId: checkId, line2: Self.somethingWentWrong, code: known,
            message: "The server refused the request."
        )
    }

    static let couldntCheck = "Couldn't check this time"
    static let noConnection = "No connection · press again"
    static let tookTooLong = "Took too long · press again"
    /// R16, new copy (not in §6.3): the server refused the request.
    static let somethingWentWrong = "Something went wrong · press again"

    private static func errorResponse(checkId: String, line2: String, code: APIErrorCode, message: String) -> JSONValue {
        let response = CheckResponse(
            requestId: checkId,
            decision: .init(
                kind: .error, reason: .error, presentation: .island,
                copy: .init(line1: couldntCheck, line2: line2)
            ),
            error: .init(code: code, message: message)
        )
        return (try? JSONValue(data: JSONCoding.encoder.encode(response))) ?? .null
    }

    // MARK: Step 7 choice

    private func present(record: CheckRecord, decision: CheckResponse.Decision?, wallet: Wallet, stored: Bool) -> Outcome {
        let kind = decision?.kind ?? .unrecognized
        let presentation: Presentation = switch decision?.presentation {
        case .snippet: .snippet
        case .island: .island
        default: (kind == .switch || (kind == .keep && decision?.reason == .alreadyProtected)) ? .snippet : .island
        }

        if presentation == .snippet, kind == .switch || kind == .keep, stored {
            switch deps.settings.snippetMode {
            case .snippet:
                return .snippet(checkId: record.checkId)
            case .confirm:
                guard let actionName = ResultText.primaryButtonTitle(decision: decision, catalog: deps.catalog) else {
                    // No card name for the verb: §6.6's static snippet (Pattern B hides the view's own button);
                    // the purchase is saved later with "I bought this".
                    return .snippet(checkId: record.checkId)
                }
                return .confirm(checkId: record.checkId, actionName: actionName)
            case .island:
                // §6.6 G2 fallback: lines 1–3 as Switch, `.default` sound, held 8 s; save later with "I bought this".
                var state = islandState(decision: decision, copy: record.filledCopy, wallet: wallet)
                state.phase = .switchFallback
                state.glyph = .card
                return .island(IslandAlert(
                    checkId: record.checkId, state: state, sound: .standard, hold: deps.fallbackHold, hasRecord: stored
                ))
            }
        }

        return .island(IslandAlert(
            checkId: record.checkId,
            state: islandState(decision: decision, copy: record.filledCopy, wallet: wallet),
            sound: deps.settings.silentAlerts ? .silent : .standard,
            hold: deps.islandHold,
            hasRecord: stored
        ))
    }

    func islandState(decision: CheckResponse.Decision?, copy: CheckRecord.FilledCopy, wallet: Wallet) -> State {
        let cardId = decision?.recommendedCardId ?? decision?.defaultCardId
        let phase: State.Phase
        let glyph: State.Glyph
        var showsCard = false
        switch decision?.kind {
        case .keep: (phase, glyph, showsCard) = (.keep, .check, true)
        case .noCheckout: (phase, glyph) = (.noCheckout, .warning)
        case .switch: (phase, glyph, showsCard) = (.switchFallback, .card, true)
        default: (phase, glyph) = (.error, .warning)
        }
        return State(
            phase: phase,
            glyph: glyph,
            cardId: showsCard ? cardId : nil,
            cardShortName: showsCard ? deps.catalog.shortName(cardId) : nil,
            last4: showsCard ? wallet.last4(for: cardId) : nil,
            line1: copy.line1.isEmpty ? "Couldn't check this time" : copy.line1,
            line2: copy.line2,
            line3: copy.line3,
            lockScreenText: State.checkedLockScreenText
        )
    }

    private func onDeviceAlert(checkId: String, state: State) -> IslandAlert {
        IslandAlert(
            checkId: checkId, state: state, sound: deps.settings.silentAlerts ? .silent : .standard,
            hold: deps.islandHold, hasRecord: false
        )
    }

    /// §6.3 *No checkout, on device*: no total was read on the phone (the gate failed, reading failed, or the body
    /// failed the privacy check) and nothing was sent.
    static let noCheckoutOnDevice = State(
        phase: .noCheckout,
        glyph: .warning,
        line1: "No checkout total found",
        line2: "Nothing left your phone",
        line3: "Scroll to the total and press again",
        lockScreenText: State.checkedLockScreenText
    )
}

/// Request IDs (also the check ID). A v4 UUID's last group is 12 hex characters, all digits about 1 time in 285, and
/// the backend rejects any body with a run of 12+ digits (§9.2), so such IDs are drawn again. So is an ID whose
/// hyphenated digit groups read as a card number, so the whole-body check (`PrivacyGuard.isSendable`) needs no
/// exemption for it.
enum RequestID {
    static func make() -> String {
        var id: String
        repeat {
            id = UUID().uuidString.lowercased()
        } while PrivacyGuard.longestDigitRun(id) > PrivacyGuard.maxDigitRun || PrivacyGuard.containsCardNumber(id)
        return id
    }
}
