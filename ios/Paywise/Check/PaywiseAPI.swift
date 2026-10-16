import Foundation
import Synchronization

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

/// Like `withDeadline`, but returns at `limit` even when `operation` ignores cancellation: a task group waits for every
/// child, so `withDeadline` is only as prompt as its operation's cancellation. Here the operation runs in its own task
/// (which inherits task-local values, as a child would), is cancelled at the deadline and left to finish on its own;
/// its late result is dropped. For waits on the system that must not hold the intent past §6.2's 30 s (Pattern B's
/// confirmation prompt). Cancelling the caller cancels the operation and throws `CancellationError`.
func withHardDeadline<T: Sendable>(
    _ limit: Duration,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let once = ResumeOnce<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            once.set(continuation)
            let work = Task {
                do {
                    once.resume(with: .success(try await operation()))
                } catch {
                    once.resume(with: .failure(error))
                }
            }
            let timer = Task {
                try? await Task.sleep(for: limit)
                if once.resume(with: .failure(DeadlineExceeded())) { work.cancel() }
            }
            once.onFinish { work.cancel(); timer.cancel() }
        }
    } onCancel: {
        once.resume(with: .failure(CancellationError()))
    }
}

/// Resumes a continuation at most once, from whichever task gets there first; `onFinish` runs after that resume.
private final class ResumeOnce<T: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<T, any Error>?
        /// A result that arrived before the continuation was set (cancellation can come first).
        var early: Result<T, any Error>?
        var finished = false
        var cleanup: (@Sendable () -> Void)?
    }

    private let state = Mutex(State())

    func set(_ continuation: CheckedContinuation<T, any Error>) {
        let early: Result<T, any Error>? = state.withLock { state in
            if let early = state.early {
                state.early = nil
                return early
            }
            state.continuation = continuation
            return nil
        }
        if let early { continuation.resume(with: early) }
    }

    func onFinish(_ cleanup: @escaping @Sendable () -> Void) {
        let runNow = state.withLock { state in
            if state.finished { return true }
            state.cleanup = cleanup
            return false
        }
        if runNow { cleanup() }
    }

    /// true if this call delivered the result.
    @discardableResult
    func resume(with result: Result<T, any Error>) -> Bool {
        let (continuation, cleanup, delivered): (CheckedContinuation<T, any Error>?, (@Sendable () -> Void)?, Bool) =
            state.withLock { state in
                guard !state.finished else { return (nil, nil, false) }
                state.finished = true
                guard let continuation = state.continuation else {
                    state.early = result
                    return (nil, nil, true)
                }
                state.continuation = nil
                let cleanup = state.cleanup
                state.cleanup = nil
                return (continuation, cleanup, true)
            }
        continuation?.resume(with: result)
        cleanup?()
        return delivered
    }
}

extension Duration {
    var seconds: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
