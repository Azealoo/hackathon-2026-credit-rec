import Foundation

struct RecommendationService: Sendable {
    enum Failure: Error {
        case unavailable, offline, invalid, privacy
    }
    let api: PaywiseAPI

    func catalog() async throws -> RecommendationCatalog {
        try await send(path: "v2/catalog", body: nil)
    }

    func compare(_ request: RecommendationRequest) async throws -> RecommendationResult {
        let body = try JSONEncoder().encode(request)
        guard PrivacyGuard.isSendable(body) else { throw Failure.privacy }
        return try await send(path: "v2/recommend", body: body)
    }

    private func send<T: Decodable & Sendable>(path: String, body: Data?) async throws -> T {
        var request = URLRequest(url: api.baseURL.appending(path: path), cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: api.timeout.seconds)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data: Data
        let response: URLResponse
        do {
            let session = api.session
            let outgoing = request
            (data, response) = try await withDeadline(api.timeout) { try await session.data(for: outgoing) }
        } catch {
            throw Failure.offline
        }
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200:
            guard let result = try? JSONDecoder().decode(T.self, from: data) else { throw Failure.invalid }
            return result
        case 404, 503: throw Failure.unavailable
        default: throw Failure.invalid
        }
    }
}
