import Foundation

/// `POST {base}/v1/check` (SPEC §15.5) with the 6.0 s deadline from §6.2. The deadline is enforced here, not only by
/// URLSession, so a stalled connection still gives up on time.
struct PaywiseAPI: Sendable {
    enum Failure: Error, Equatable {
        /// The 6.0 s deadline passed.
        case timeout
        /// No network, DNS, TLS or a dropped connection.
        case offline
        /// 5xx, or a 2xx body that isn't a check response.
        case server(status: Int)
    }

    /// What came back from the server: a 2xx result, or a 4xx with the error shape.
    struct Reply: Sendable {
        var status: Int
        var body: Data
    }

    static let defaultTimeout: Duration = .seconds(6)
    /// Info.plist key holding the backend base URL.
    static let baseURLKey = "PaywiseAPIURL"

    var baseURL: URL
    var session: URLSession
    var timeout: Duration = PaywiseAPI.defaultTimeout

    /// The deployed backend from Info.plist, on an ephemeral session (no cookies, no cache).
    static func live(bundle: Bundle = .main) -> PaywiseAPI {
        let string = bundle.object(forInfoDictionaryKey: baseURLKey) as? String
        let url = string.flatMap(URL.init(string:)) ?? URL(string: "https://paywise-api-n0f9.onrender.com")!
        return PaywiseAPI(baseURL: url, session: makeSession(timeout: defaultTimeout))
    }

    static func makeSession(timeout: Duration, protocolClasses: [AnyClass] = []) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout.seconds
        configuration.timeoutIntervalForResource = timeout.seconds
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        if !protocolClasses.isEmpty {
            configuration.protocolClasses = protocolClasses + (configuration.protocolClasses ?? [])
        }
        return URLSession(configuration: configuration)
    }

    var checkURL: URL { baseURL.appending(path: "v1/check") }

    /// Sends one check body. Returns the reply for 2xx and 4xx; throws `Failure` for everything else.
    func postCheck(_ body: Data) async throws(Failure) -> Reply {
        var request = URLRequest(url: checkURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout.seconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body

        let session = session
        let urlRequest = request
        let result: (Data, URLResponse)
        do {
            result = try await withDeadline(timeout) {
                try await session.data(for: urlRequest)
            }
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
            return Reply(status: status, body: result.0)
        default:
            throw .server(status: status)
        }
    }
}

struct DeadlineExceeded: Error {}

/// Runs `operation`, or throws `DeadlineExceeded` once `limit` passes (the operation is cancelled).
func withDeadline<T: Sendable>(
    _ limit: Duration,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: limit)
            throw DeadlineExceeded()
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw DeadlineExceeded() }
        return first
    }
}

extension Duration {
    var seconds: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
