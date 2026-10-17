import Foundation
import Synchronization
import Testing
@testable import Paywise

struct RecommendationTests {
    @Test func exactUsdInputAndInvalidAmounts() {
        #expect(RecommendationMoney.minor("1499.99") == 149999)
        #expect(RecommendationMoney.minor("0") == 0)
        #expect(RecommendationMoney.minor("10.5") == 1050)
        for value in ["", "-1", "NaN", "Infinity", "1e3", "1.005", "10,000", "10000000.01"] {
            #expect(RecommendationMoney.minor(value) == nil)
        }
    }

    @Test func preferencesPersistWithoutAutomaticallyAllowingProtectionLoss() {
        let suite = "recommendation-test-" + UUID().uuidString
        let settings = PaywiseSettings(suiteName: suite)
        defer { settings.defaults.removePersistentDomain(forName: suite) }
        #expect(settings.recommendationPreferences.mode == "cash_first")
        #expect(!settings.recommendationPreferences.allowLossOfExistingProtection)
        var prefs = RecommendationPreferences()
        prefs.mode = "protection_target"
        prefs.cashSacrificeBudgetMinor = 1000
        settings.recommendationPreferences = prefs
        let saved = PaywiseSettings(suiteName: suite).recommendationPreferences
        #expect(saved == prefs)
        #expect(saved.wire.protectionTargets.first?.minExtensionMonths == 12)
        #expect(saved.wire.protectionTargets.first?.minNominalLimitMinor == 1)
        #expect(!saved.wire.allowLossOfExistingProtection)
    }

    @Test func corruptSavedPreferencesFallBackToSafeDefaults() {
        let suite = "recommendation-corrupt-" + UUID().uuidString
        let settings = PaywiseSettings(suiteName: suite)
        defer { settings.defaults.removePersistentDomain(forName: suite) }
        settings.defaults.set(Data("invalid".utf8), forKey: PaywiseSettings.Key.recommendationPreferences)
        #expect(settings.recommendationPreferences == RecommendationPreferences())
    }

    private func draft() -> RecommendationCardDraft {
        .init(id: "test-card", productId: "wells-fargo-active-cash", network: "visa")
    }

    private func request(confirmed: Bool = false) throws -> RecommendationRequest {
        var card = draft()
        card.availableCredit = confirmed ? "2000" : ""
        card.termsConfirmed = confirmed
        card.foreignFeeApplies = confirmed ? "no" : "unknown"
        return try #require(RecommendationRequest.build(requestId: "synthetic-comparison", amount: "1000",
            chargeDate: "2026-10-16", cards: [card], defaultId: card.id, path: "direct_card",
            usableConfirmed: confirmed, interestFreeConfirmed: confirmed, noCheckoutFeesConfirmed: confirmed,
            preferences: RecommendationPreferences()))
    }

    @Test func unknownAccountFactsStayUnknownOnTheWire() throws {
        let payload = try request()
        #expect(payload.options.first?.availableCreditMinor == nil)
        #expect(payload.options.first?.expectedFullRepayment == "unknown")
        #expect(payload.options.first?.purchaseGracePeriodActive == "unknown")
        #expect(payload.options.first?.checkoutFeeMinor == nil)
        #expect(payload.options.first?.policyConfirmedThrough == nil)
        #expect(payload.purchase.acceptedNetworks == nil)
        #expect(PrivacyGuard.isSendable(try JSONEncoder().encode(payload)))
    }

    @Test func confirmedFactsProduceAnExactCentsRequest() throws {
        let payload = try request(confirmed: true)
        #expect(payload.purchase.totalMinor == 100000)
        #expect(payload.options.first?.availableCreditMinor == 200000)
        #expect(payload.options.first?.policyConfirmedThrough == "2026-10-16")
        #expect(payload.options.first?.checkoutFeeMinor == 0)
        #expect(payload.options.first?.expectedFullRepayment == "yes")
        #expect(payload.purchase.acceptedNetworks == ["visa"])
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        #expect(json["preferences"] != nil)
        #expect(json["purchase"] != nil)
        #expect(RecommendationCardDraft.productId(forLegacyId: "wf-active-cash") == "wells-fargo-active-cash")
    }

    @Test func comparisonNeedsAnExplicitBaselineAndValidCredit() {
        var card = draft()
        card.availableCredit = "not an amount"
        #expect(RecommendationRequest.build(requestId: "synthetic", amount: "100", chargeDate: "2026-10-16",
            cards: [card], defaultId: card.id, path: "direct_card", usableConfirmed: false,
            interestFreeConfirmed: false, noCheckoutFeesConfirmed: false, preferences: .init()) == nil)
        card.availableCredit = ""
        #expect(RecommendationRequest.build(requestId: "synthetic", amount: "100", chargeDate: "2026-10-16",
            cards: [card], defaultId: "unsupported-default", path: "direct_card", usableConfirmed: false,
            interestFreeConfirmed: false, noCheckoutFeesConfirmed: false, preferences: .init()) == nil)
    }

    @Test func v2ClientSendsSavedPreferencesAndDecodesUnverifiedTarget() async throws {
        let host = "comparison-" + UUID().uuidString.lowercased() + ".test"
        let response = Data(#"{"decision":"choice_required","reason":"protection_target_unverified","options":[]}"#.utf8)
        ComparisonURLProtocol.register(host, status: 200, body: response)
        let api = client(host)
        var payload = try request(confirmed: true)
        var prefs = RecommendationPreferences()
        prefs.mode = "protection_target"
        prefs.cashSacrificeBudgetMinor = 500
        payload.preferences = prefs.wire
        let result = try await api.compare(payload)
        #expect(result.decision == "choice_required")
        #expect(result.selected == nil)
        #expect(result.explanation.contains("cannot yet confirm"))
        let sent = try #require(ComparisonURLProtocol.body(host))
        let decoded = try JSONDecoder().decode(RecommendationRequest.self, from: sent)
        #expect(decoded.preferences.mode == "protection_target")
        #expect(decoded.preferences.cashSacrificeBudgetMinor == 500)
        #expect(!decoded.preferences.allowLossOfExistingProtection)
    }

    @Test func unavailableAndMalformedResponsesDoNotReplayLegacyAnswers() async throws {
        for status in [404, 503, 200] {
            let host = "comparison-error-" + UUID().uuidString.lowercased() + ".test"
            ComparisonURLProtocol.register(host, status: status, body: Data("{}".utf8))
            do {
                _ = try await client(host).compare(request())
                Issue.record("Expected an unavailable or invalid response")
            } catch let error as RecommendationService.Failure {
                if status == 200 { if case .invalid = error {} else { Issue.record("Expected invalid") } }
                else { if case .unavailable = error {} else { Issue.record("Expected unavailable") } }
            }
        }
    }

    @Test func clientPrivacyGuardRejectsLongDigitRunsBeforeSending() async throws {
        let host = "comparison-private-" + UUID().uuidString.lowercased() + ".test"
        ComparisonURLProtocol.register(host, status: 200, body: Data("{}".utf8))
        var payload = try request()
        payload.requestId = "4" + String(repeating: "1", count: 15)
        do {
            _ = try await client(host).compare(payload)
            Issue.record("Expected privacy rejection")
        } catch let error as RecommendationService.Failure {
            if case .privacy = error {} else { Issue.record("Expected privacy rejection") }
        }
        #expect(ComparisonURLProtocol.body(host) == nil)
    }

    private func client(_ host: String) -> RecommendationService {
        .init(api: .init(baseURL: URL(string: "https://\(host)")!,
                         session: PaywiseAPI.makeSession(timeout: .seconds(2), protocolClasses: [ComparisonURLProtocol.self])))
    }
}

private final class ComparisonURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Reply { var status: Int; var data: Data; var body: Data? }
    private static let replies = Mutex<[String: Reply]>([:])
    static func register(_ host: String, status: Int, body: Data) {
        replies.withLock { $0[host] = Reply(status: status, data: body) }
    }
    static func body(_ host: String) -> Data? { replies.withLock { $0[host]?.body } }
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host.map { host in replies.withLock { $0[host] != nil } } ?? false
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let host = url.host else { return }
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            var data = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                guard count > 0 else { break }
                data.append(contentsOf: bytes.prefix(count))
            }
            body = data
        }
        let reply = Self.replies.withLock { state in
            state[host]?.body = body
            return state[host]
        }
        guard let reply, let response = HTTPURLResponse(url: url, statusCode: reply.status,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
