import Foundation
import os

/// The "Can I claim?" input (SPEC §5.5, §15.7 step 12d): confirm the card and date, the maker's warranty, what
/// happened with a cause chip. After the user types, the server's LLM classifies the cause (`cause: null`) and its
/// chip is pre-selected; [Check] then sends the cause the user has picked as `user_confirmed`.
@MainActor
@Observable
final class ClaimModel {
    enum PaidAnswer: Equatable, Sendable {
        case yes
        case otherCard(String)
    }

    private(set) var purchase: PurchaseSnapshot
    let deps: AppDependencies
    let wallet: Wallet
    /// Today for this claim: "Pretend today is…" when it is on (§12.1 "14 months later"), else the phone's date; never
    /// before the purchase date. A purchase saved while the override was later than today would otherwise leave no
    /// incident date the backend accepts (it needs purchaseDate ≤ incident.date ≤ asOf), and every check would fail.
    let today: String

    private(set) var paid: PaidAnswer?
    var choosingOtherCard = false
    var warranty: WarrantyAnswer?
    /// What happened, as the user typed it. The view calls `descriptionChanged()` on every edit.
    var description = ""
    private(set) var cause: ClaimCause?
    /// The chip the server's classification pre-selected, while the user hasn't picked one.
    private(set) var suggestedCause: ClaimCause?
    private(set) var classifying = false
    private(set) var userPickedCause = false
    var incidentDate: Date
    /// The body failed the on-device privacy check (a run of 12+ digits, e.g. a serial number, in the text).
    private(set) var hasLongNumber = false

    /// Debounce before asking the server to classify what the user typed.
    var classifyDelay: Duration = .seconds(1)
    private var classifyTask: Task<Void, Never>?

    private static let log = Logger(subsystem: "com.azealoo.paywise", category: "claim")

    init(purchase: PurchaseSnapshot, deps: AppDependencies, wallet: Wallet) {
        self.purchase = purchase
        self.deps = deps
        self.wallet = wallet
        let phoneToday = Day.today(settings: deps.settings, now: deps.now(), timeZone: deps.timeZone)
        // yyyy-MM-dd strings compare as dates.
        let today = PaywiseSettings.isDay(purchase.purchaseDate) ? max(phoneToday, purchase.purchaseDate) : phoneToday
        self.today = today
        incidentDate = Day.date(today, timeZone: deps.timeZone) ?? deps.now()
        warranty = WarrantyAnswer(storedMonths: purchase.manufacturerWarrantyMonths)
        if purchase.status == .confirmed { paid = .yes }
    }

    // MARK: Questions

    /// §5.5: "Did you pay with Freedom ••1234 on Oct 17?"
    var paidQuestion: String {
        let card = PurchaseText.card(purchase.cardId, wallet: wallet, catalog: deps.catalog)
        let day = Day.monthDay(purchase.purchaseDate).map { " on \($0)" } ?? ""
        return "Did you pay with \(card)\(day)?"
    }

    /// The wallet's other cards for [No, another card].
    var otherCards: [String] {
        wallet.cards.map(\.cardId).filter { $0 != purchase.cardId }
    }

    var paidCardId: String {
        if case .otherCard(let id) = paid { return id }
        return purchase.cardId
    }

    var incidentDay: String { Day.string(incidentDate, timeZone: deps.timeZone) }

    /// The incident can't be after today, or before the purchase (today is never earlier than the purchase).
    var incidentRange: ClosedRange<Date> {
        let upper = Day.date(today, timeZone: deps.timeZone) ?? deps.now()
        let bought = Day.date(purchase.purchaseDate, timeZone: deps.timeZone) ?? upper
        return min(bought, upper)...upper
    }

    var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canCheck: Bool {
        paid != nil && warranty != nil && !trimmedDescription.isEmpty && cause != nil
    }

    // MARK: Answers

    /// [Yes] sets `status = confirmed` (§5.5).
    func answerYes(_ purchases: PurchasesModel) async {
        paid = .yes
        choosingOtherCard = false
        await purchases.confirm(id: purchase.id)
        if let updated = purchases.purchase(id: purchase.id) { purchase = updated }
    }

    /// [No, another card] → a wallet card. Saved on [Check] (`prepareVerdict`), so changing the answer before then
    /// never rewrites the purchase's card.
    func answerOtherCard(_ cardId: String) {
        paid = .otherCard(cardId)
    }

    func pick(_ cause: ClaimCause) {
        self.cause = cause
        userPickedCause = true
        classifyTask?.cancel()
        classifying = false
    }

    // MARK: Classification

    /// After an edit: once the user pauses, ask the server to classify the text (unless they picked a chip).
    func descriptionChanged() {
        hasLongNumber = false
        classifyTask?.cancel()
        let text = trimmedDescription
        guard !userPickedCause, text.count >= 8 else {
            classifying = false
            return
        }
        let delay = classifyDelay
        classifyTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.classify(text)
        }
    }

    /// `POST /v1/coverage?format=json` with `cause: null`: the server's LLM reads the cause; its chip is pre-selected.
    /// A missing `incident.cause` (or a value with no chip) leaves the chips as they are.
    func classify(_ text: String) async {
        guard let body = try? request(description: text, cause: nil, causeSource: nil).body(),
              PrivacyGuard.isSendable(body)
        else { return }
        classifying = true
        defer { classifying = false }
        let reply: PaywiseAPI.Reply
        do {
            reply = try await deps.coverage.post(body, format: .json)
        } catch {
            Self.log.notice("Cause classification failed: \(String(describing: error), privacy: .public)")
            return
        }
        guard (200..<300).contains(reply.status), let suggested = CoverageClassification.cause(in: reply.body) else { return }
        guard !userPickedCause, trimmedDescription == text, !Task.isCancelled else { return }
        cause = suggested
        suggestedCause = suggested
    }

    // MARK: Verdict

    /// The [Check] request: the purchase as confirmed, the incident with the user's chip, `asOf` = today.
    func verdictRequest() -> CoverageRequest {
        request(description: trimmedDescription, cause: cause, causeSource: "user_confirmed")
    }

    /// Saves the warranty answer and returns the request to render, or nil (with `hasLongNumber` set) when the body
    /// would break the backend's privacy rule, so it is never sent.
    func prepareVerdict(_ purchases: PurchasesModel) async -> CoverageRequest? {
        classifyTask?.cancel()
        let request = verdictRequest()
        guard let body = try? request.body(), PrivacyGuard.isSendable(body) else {
            hasLongNumber = true
            return nil
        }
        if case .otherCard(let cardId) = paid {
            // Paid with another wallet card: the purchase is confirmed with that card.
            await purchases.confirm(id: purchase.id, paidWith: cardId)
        }
        if let warranty, purchase.manufacturerWarrantyMonths != warranty.storedMonths {
            await purchases.setManufacturerWarranty(id: purchase.id, months: warranty.storedMonths)
        }
        return request
    }

    func request(description: String, cause: ClaimCause?, causeSource: String?) -> CoverageRequest {
        let warranty = warranty ?? .unknown
        return CoverageRequest(
            purchase: .init(
                cardId: paidCardId,
                merchant: purchase.merchant,
                item: purchase.item,
                category: purchase.category,
                condition: purchase.condition,
                priceUsd: purchase.priceUsd,
                purchaseDate: purchase.purchaseDate,
                status: paid == nil ? purchase.status.rawValue : Purchase.Status.confirmed.rawValue,
                manufacturerWarrantyMonths: warranty.months,
                manufacturerWarrantySource: warranty.source,
                paidWith: "card_full"
            ),
            incident: .init(date: incidentDay, description: description, cause: cause, causeSource: causeSource),
            asOf: today
        )
    }
}

/// Loads the HTML verdict (`POST /v1/coverage?format=html`) for the in-app web view.
@MainActor
@Observable
final class VerdictModel {
    enum State: Equatable {
        case loading
        case loaded(html: String)
        /// §6.3 *Couldn't check* line 2.
        case failed(line2: String)
    }

    private(set) var state: State = .loading
    let request: CoverageRequest
    let api: CoverageAPI

    init(request: CoverageRequest, api: CoverageAPI) {
        self.request = request
        self.api = api
    }

    var baseURL: URL { api.baseURL }

    func load() async {
        state = .loading
        guard let body = try? request.body(), PrivacyGuard.isSendable(body) else {
            state = .failed(line2: CheckFlow.somethingWentWrong)
            return
        }
        do {
            let reply = try await api.post(body, format: .html)
            if (200..<300).contains(reply.status), let html = String(data: reply.body, encoding: .utf8), !html.isEmpty {
                state = .loaded(html: html)
            } else {
                // R16: a refused request shows the phone's own words, never the server's error text.
                state = .failed(line2: CheckFlow.somethingWentWrong)
            }
        } catch {
            state = .failed(line2: error == .timeout ? CheckFlow.tookTooLong : CheckFlow.noConnection)
        }
    }
}
