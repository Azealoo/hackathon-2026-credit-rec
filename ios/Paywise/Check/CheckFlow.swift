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
        /// No check ran: a repeat press (`PressGate`) or a screen showing Paywise's own result (`showsPaywiseResult`).
        /// Once the earlier press has returned, the intent shows its answer again as a static snippet (`reshowing`, the
        /// same record, so still one save); while that press is still checking or still shows its island or prompt,
        /// nothing. Either way the island and the save offer (`lastPressCheckId`) stay the earlier press's.
        case ignored(reshowing: String?)

        /// The check whose `CheckRecord` was written; nil when nothing was stored.
        var recordCheckId: String? {
            switch self {
            case .notSetUp, .ignored: nil
            case .snippet(let checkId), .confirm(let checkId, _): checkId
            case .island(let alert): alert.hasRecord ? alert.checkId : nil
            }
        }
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

    /// `trace` times each link (os_signpost + one `.info` line each, `CheckTrace`). The intent begins
    /// `intent-to-checking` before calling this; the in-app check never does, so that link is a no-op there.
    ///
    /// A press (`trace.source == .intent`) goes through `deps.pressGate` first: while another press runs, or within
    /// `deps.repeatWindow` of its answer, it reuses that answer instead of starting a check (one Back Tap can fire the
    /// Shortcut twice, docs/spikes.md › Results). The in-app check always runs: a second pick is a new screenshot.
    func run(imageData: Data?, trace: CheckTrace = CheckTrace(source: .inApp)) async -> Outcome {
        guard trace.source == .intent else { return await check(imageData: imageData, trace: trace) }
        let gate = deps.pressGate
        if case .repeatOf(let reshowing) = await gate.admit(now: deps.now(), window: deps.repeatWindow) {
            // Before step 1: ending activities here would take the island from the press being repeated.
            trace.abandon(.intentToChecking)
            Self.log.notice("Repeat press: reusing the last answer instead of a new check")
            return .ignored(reshowing: reshowing)
        }
        let outcome = await check(imageData: imageData, trace: trace)
        await gate.finish(outcome, now: deps.now())
        return outcome
    }

    private func check(imageData: Data?, trace: CheckTrace) async -> Outcome {
        let checkId = RequestID.make()

        // 1. End any Paywise activity.
        await deps.island.endAll()
        guard let imageData else {
            trace.abandon(.intentToChecking)
            return .notSetUp
        }

        // 2. Start *Checking*; if ActivityKit refuses, carry on without it (§6.6).
        _ = await deps.island.startChecking(checkId: checkId)
        trace.end(.intentToChecking)

        // 3–4. Crop, OCR, gate and redaction, all on the phone; then the body and its privacy check.
        trace.begin(.read)
        let preparation = await prepare(imageData: imageData, checkId: checkId)
        trace.end(.read)
        let prepared: Prepared
        switch preparation {
        case .ready(let ready):
            prepared = ready
        case .noCheckout:
            return .island(onDeviceAlert(checkId: checkId, state: Self.noCheckoutOnDevice))
        case .ownResult:
            await deps.island.end(checkId: checkId)
            return .ignored(reshowing: nil)
        }
        let wallet = prepared.wallet

        // 5. POST /v1/check (6.0 s); on failure, replay or *Couldn't check*.
        trace.begin(.post)
        let (responseJSON, replayed) = await fetch(prepared: prepared, checkId: checkId)
        trace.end(.post)

        // 6. Apply the user's offers on the phone (D1: nothing about them was sent), then write the CheckRecord.
        trace.begin(.record)
        let response = (try? responseJSON.decode(CheckResponse.self)) ?? CheckResponse()
        let adjustment = OfferResolver.resolve(
            response: response, catalog: deps.catalog, records: deps.offers.load(), wallet: wallet,
            today: prepared.request.clientDate
        )
        let decision = adjustment?.decision ?? response.decision
        let filled = CopyFill.fill(
            decision?.copy,
            wallet: wallet,
            ppCap: CopyFill.ppCap(decision: decision, catalog: deps.catalog)
        )
        let record = CheckRecord(
            checkId: checkId,
            createdAt: CheckRecord.timestamp(deps.now(), timeZone: deps.timeZone),
            sentPayload: (try? JSONValue(data: prepared.body)) ?? .null,
            response: responseJSON,
            filledCopy: filled,
            replayed: replayed,
            offerAdjustment: adjustment
        )
        var stored = true
        do {
            try deps.checkStore.write(record, now: deps.now())
        } catch {
            stored = false
            Self.log.error("Couldn't write the check record: \(String(describing: error), privacy: .public)")
        }
        trace.end(.record)

        // 7 (decided here, shown by the intent).
        return present(record: record, decision: decision, wallet: wallet, stored: stored)
    }

    /// A checkout read on the phone, turned into a body that passed the privacy check.
    private struct Prepared {
        var request: CheckRequest
        var body: Data
        var wallet: Wallet
    }

    private enum Preparation {
        case ready(Prepared)
        /// §6.3 *No checkout, on device*: reading failed, the screen isn't a checkout, or the body would break the
        /// privacy rule.
        case noCheckout
        /// The screen shows Paywise's own result (`showsPaywiseResult`).
        case ownResult
    }

    /// Steps 3–4 and the request body. Nothing has been sent unless the result is `.ready`.
    private func prepare(imageData: Data, checkId: String) async -> Preparation {
        let reader = deps.screenReader
        let reading: ScreenReading
        do {
            reading = try await withDeadline(deps.readTimeout) { try await reader.read(imageData) }
        } catch {
            // No total was read and nothing was sent: §6.3 *No checkout, on device*.
            Self.log.error("Screen reading failed: \(String(describing: error), privacy: .public)")
            return .noCheckout
        }
        guard !Self.showsPaywiseResult(reading.redactedText, catalog: deps.catalog) else {
            // The backend would answer about Paywise's words, not the checkout behind them (*Keep, items unreadable*).
            Self.log.notice("The screen shows Paywise's own result; nothing was sent.")
            return .ownResult
        }
        guard reading.isCheckout else {
            // Nothing is uploaded from a screen that isn't a checkout (§10).
            return .noCheckout
        }

        let wallet = deps.walletStore.load()
        let request = makeRequest(checkId: checkId, reading: reading, wallet: wallet)
        guard let body = try? JSONCoding.encoder.encode(request), PrivacyGuard.isSendable(body) else {
            // The body would break the backend's privacy rule (or didn't encode): it is never sent, so the answer
            // is §6.3 *No checkout, on device*, not the backend's privacy_rejected.
            Self.log.error("The check body failed the on-device privacy check; nothing was sent.")
            return .noCheckout
        }
        return .ready(Prepared(request: request, body: body, wallet: wallet))
    }

    /// Whether OCR text shows one of Paywise's own result views (§6.3): a cell that is exactly a [Paying with …] title,
    /// [What we sent] or the Sent view's title. A press over Paywise's snippet reads it with the checkout behind.
    /// A cell is a whole line or one item of a row, which reading order joins with two spaces (`ReadingOrder`): the
    /// in-app Saved card reads "What we sent  Done".
    static func showsPaywiseResult(_ text: String, catalog: CardCatalog) -> Bool {
        let titles = ["what we sent", "what left your iphone"]
            + catalog.cards.compactMap(\.shortName).map { "paying with \($0)".lowercased() }
        return text.components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: ReadingOrder.columnSeparator) }
            .contains { titles.contains($0.trimmingCharacters(in: .whitespaces).lowercased()) }
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
            // The phone's date, never "Pretend today is…": that override is for claim dates (§12.1 "14 months later"),
            // and as clientDate it dated every purchase checked while it was on to the pretend day.
            clientDate: Self.clientDate(deps.now(), timeZone: deps.timeZone),
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
    private func fetch(prepared: Prepared, checkId: String) async -> (JSONValue, Bool) {
        let failure: PaywiseAPI.Failure
        do {
            let reply = try await deps.api.postCheck(prepared.body)
            let json = try? JSONValue(data: reply.body)
            let parsed = json.flatMap { try? $0.decode(CheckResponse.self) }
            let kind = parsed?.decision?.kind
            if (400..<500).contains(reply.status) || ((200..<300).contains(reply.status) && kind == .error) {
                // R16: the server refused the request (bad_request, privacy_rejected, 429), or answered 2xx with its
                // error shape. The phone shows its own §6.3 *Couldn't check* copy, never the server's, and doesn't
                // replay: the server did answer, so this isn't a connection failure. A 5xx (even in the error shape,
                // §15.5) falls through to `.server`: §6.3's "No connection · press again" and the replay lookup.
                Self.log.error("The server refused the check: HTTP \(reply.status, privacy: .public)")
                return (Self.rejectedResponse(checkId: checkId, code: parsed?.error?.code, status: reply.status), false)
            }
            if let json, let kind, kind != .unrecognized, (200..<300).contains(reply.status) {
                return (json, false)
            }
            failure = .server(status: reply.status)
        } catch {
            failure = error
        }

        if deps.settings.replayEnabled,
           let key = ReplayStore.key(for: prepared.request.screen.ocrText, catalog: deps.catalog),
           let bundled = deps.replay.response(for: key),
           let data = ReplayStore.fitted(
               bundled, clientDate: prepared.request.clientDate, walletCardIds: Set(prepared.wallet.cards.map(\.cardId))
           ),
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

    /// R16: a 4xx (or the server's error shape on a 2xx) shows *Couldn't check* with "Something went wrong · press again",
    /// except a 429 (the backend's 60-a-minute limit), where pressing again fails too: "Too many checks · wait a minute".
    /// The stored error code is the server's when it is one the contract knows, else bad_request.
    static func rejectedResponse(checkId: String, code: APIErrorCode?, status: Int = 400) -> JSONValue {
        let known: APIErrorCode = switch code {
        case .some(.unrecognized), .none: .badRequest
        case .some(let code): code
        }
        return errorResponse(
            checkId: checkId, line2: status == 429 ? Self.tooManyChecks : Self.somethingWentWrong, code: known,
            message: status == 429 ? "Too many checks in a minute." : "The server refused the request."
        )
    }

    static let couldntCheck = "Couldn't check this time"
    static let noConnection = "No connection · press again"
    static let tookTooLong = "Took too long · press again"
    /// R16, new copy (not in §6.3): the server refused the request.
    static let somethingWentWrong = "Something went wrong · press again"
    /// The backend's 429 line2 (backend/app/middleware.py RateLimit), in the phone's own words.
    static let tooManyChecks = "Too many checks · wait a minute"

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
                    // the purchase is saved later in the app (`InAppCheck.offerLastPress`).
                    return .snippet(checkId: record.checkId)
                }
                return .confirm(checkId: record.checkId, actionName: actionName)
            case .island:
                // §6.6 G2 fallback: lines 1–3 as Switch, `.default` sound, held 8 s; saved later in the app's Check
                // tab, which offers the last press's result (`InAppCheck.offerLastPress`).
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

/// Admits one press at a time. One Back Tap can fire the Shortcut twice a few seconds apart (docs/spikes.md › Results ›
/// Back Tap): a press while another runs, or within `AppDependencies.repeatWindow` of an answer, runs no check of its
/// own. Its screenshot shows the first press's snippet, and its check would take the island from that press (§6.2).
/// After *No checkout* or *Couldn't check* ("press again"), the next press always runs.
///
/// A repeat shows the answer again once its press has returned (`returned`): by then a Keep island's hold is over and
/// a Pattern B prompt is gone, so without it a press later in the window would show nothing at all.
actor PressGate {
    enum Admission: Sendable, Equatable {
        case run
        /// A repeat: show this check's answer again, or nothing (nil) while the earlier press is still checking or
        /// still shows its island or prompt.
        case repeatOf(reshowing: String?)
    }

    /// A press counts as running for at most the intent's 30 s (§6.2), so one that never finished can't block the next.
    static let maxRun: TimeInterval = 30

    private struct Answer {
        var outcome: CheckFlow.Outcome
        var at: Date
        /// Its intent has returned (`returned`).
        var returned = false
    }

    private var runningSince: Date?
    private var answer: Answer?

    init() {}

    func admit(now: Date, window: Duration) -> Admission {
        if let runningSince, (0..<Self.maxRun).contains(now.timeIntervalSince(runningSince)) {
            return .repeatOf(reshowing: nil)
        }
        if let answer, (0..<CheckTrace.milliseconds(window) / 1000).contains(now.timeIntervalSince(answer.at)) {
            return .repeatOf(reshowing: answer.returned ? answer.outcome.recordCheckId : nil)
        }
        runningSince = now
        answer = nil
        return .run
    }

    func finish(_ outcome: CheckFlow.Outcome, now: Date) {
        runningSince = nil
        answer = Self.isAnswer(outcome) ? Answer(outcome: outcome, at: now) : nil
    }

    /// The intent that answered `checkId` has returned: its island has ended, its prompt is gone, or its snippet shows.
    func returned(checkId: String) {
        if answer?.outcome.recordCheckId == checkId { answer?.returned = true }
    }

    /// A stored Switch or Keep: the answer a repeat reuses. Errors and *No checkout* ask the user to press again.
    static func isAnswer(_ outcome: CheckFlow.Outcome) -> Bool {
        switch outcome {
        case .snippet, .confirm: true
        case .island(let alert): alert.hasRecord && (alert.state.phase == .keep || alert.state.phase == .switchFallback)
        case .notSetUp, .ignored: false
        }
    }
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
