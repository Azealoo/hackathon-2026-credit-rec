import Foundation

/// `POST /v1/coverage?format=json|html` (SPEC §5.5, §15.5, `contracts/coverage.request.schema.json`). Sent only when
/// the user works on a claim for one purchase. The cause and the verdict wording come from the server; dates and
/// windows are worked out there in code.
struct CoverageAPI: Sendable {
    enum Format: String, Sendable {
        case json, html
    }

    /// The server classifies the cause with the LLM and drafts `why`; give it longer than a check's 6 s.
    static let defaultTimeout: Duration = .seconds(20)

    var baseURL: URL
    var session: URLSession
    var timeout: Duration = CoverageAPI.defaultTimeout

    static func live(bundle: Bundle = .main) -> CoverageAPI {
        let api = PaywiseAPI.live(bundle: bundle)
        return CoverageAPI(baseURL: api.baseURL, session: PaywiseAPI.makeSession(timeout: defaultTimeout))
    }

    func url(_ format: Format) -> URL {
        baseURL.appending(path: "v1/coverage").appending(queryItems: [URLQueryItem(name: "format", value: format.rawValue)])
    }

    /// Sends one coverage body. Returns the reply for 2xx and 4xx; throws `PaywiseAPI.Failure` otherwise.
    func post(_ body: Data, format: Format) async throws(PaywiseAPI.Failure) -> PaywiseAPI.Reply {
        var request = URLRequest(url: url(format), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout.seconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(format == .html ? "text/html" : "application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body

        let session = session
        let urlRequest = request
        let result: (Data, URLResponse)
        do {
            result = try await withDeadline(timeout) { try await session.data(for: urlRequest) }
        } catch is DeadlineExceeded {
            throw .timeout
        } catch let error as URLError where error.code == .timedOut {
            throw .timeout
        } catch {
            throw .offline
        }
        let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300, 400..<500:
            return PaywiseAPI.Reply(status: status, body: result.0)
        default:
            throw .server(status: status)
        }
    }
}

/// The `/v1/coverage` request body. Every key the contract requires is written, `null` included.
struct CoverageRequest: Encodable, Sendable, Hashable {
    struct Purchase: Encodable, Sendable, Hashable {
        var cardId: String
        var merchant: String
        var item: String
        var category: String
        var condition: String
        var priceUsd: Double
        var purchaseDate: String
        var status: String
        var manufacturerWarrantyMonths: Int?
        /// "user", or "assumed" for "Don't know" (12 months).
        var manufacturerWarrantySource: String
        var paidWith: String

        private enum CodingKeys: String, CodingKey {
            case cardId, merchant, item, category, condition, priceUsd, purchaseDate, status
            case manufacturerWarrantyMonths, manufacturerWarrantySource, paidWith
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(cardId, forKey: .cardId)
            try c.encode(merchant, forKey: .merchant)
            try c.encode(item, forKey: .item)
            try c.encode(category, forKey: .category)
            try c.encode(condition, forKey: .condition)
            try c.encode(priceUsd, forKey: .priceUsd)
            try c.encode(purchaseDate, forKey: .purchaseDate)
            try c.encode(status, forKey: .status)
            try c.encode(manufacturerWarrantyMonths, forKey: .manufacturerWarrantyMonths)
            try c.encode(manufacturerWarrantySource, forKey: .manufacturerWarrantySource)
            try c.encode(paidWith, forKey: .paidWith)
        }
    }

    struct Incident: Encodable, Sendable, Hashable {
        var date: String
        var description: String
        /// nil: the server classifies it.
        var cause: ClaimCause?
        /// "user_confirmed" once the user has a chip picked; nil while the server classifies.
        var causeSource: String?

        private enum CodingKeys: String, CodingKey { case date, description, cause, causeSource }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(date, forKey: .date)
            try c.encode(description, forKey: .description)
            try c.encode(cause?.rawValue, forKey: .cause)
            try c.encode(causeSource, forKey: .causeSource)
        }
    }

    var purchase: Purchase
    var incident: Incident
    var asOf: String

    func body() throws -> Data {
        try JSONCoding.encoder.encode(self)
    }
}

/// The four cause chips (§5.5) and their wire values.
enum ClaimCause: String, CaseIterable, Sendable, Identifiable {
    case failure
    case accidentalDamage = "accidental_damage"
    case theft
    case loss

    var id: String { rawValue }

    var label: String {
        switch self {
        case .failure: "Stopped working"
        case .accidentalDamage: "Dropped or damaged"
        case .theft: "Stolen"
        case .loss: "Lost"
        }
    }
}

/// The maker's-warranty answers (§5.5): "Don't know" sends 12 months, labelled assumed.
enum WarrantyAnswer: String, CaseIterable, Sendable, Identifiable {
    case oneYear, twoYears, unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneYear: "1 year"
        case .twoYears: "2 years"
        case .unknown: "Don't know"
        }
    }

    var months: Int {
        switch self {
        case .oneYear, .unknown: 12
        case .twoYears: 24
        }
    }

    var source: String { self == .unknown ? "assumed" : "user" }

    /// What the purchase stores: the user's own answer, nil for "Don't know".
    var storedMonths: Int? { self == .unknown ? nil : months }

    init?(storedMonths: Int?) {
        switch storedMonths {
        case 12: self = .oneYear
        case 24: self = .twoYears
        default: return nil
        }
    }
}

/// The server's cause classification in a `?format=json` reply, read tolerantly: `incident.cause` may be missing
/// (older servers) or a value without a chip (cosmetic, unknown), and then no chip is pre-selected.
enum CoverageClassification {
    static func cause(in body: Data) -> ClaimCause? {
        guard let json = try? JSONValue(data: body) else { return nil }
        let raw = json["incident"]?["cause"]?.stringValue
        return raw.flatMap(ClaimCause.init(rawValue:))
    }
}
