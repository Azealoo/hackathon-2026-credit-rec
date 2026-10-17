import Foundation
import Synchronization
@testable import Paywise

/// Locates the test bundle (the contract examples are copied into it).
final class TestBundleToken {}

enum Fixtures {
    static let bundle = Bundle(for: TestBundleToken.self)

    static func data(_ name: String) throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).json"])
        }
        return try Data(contentsOf: url)
    }

    /// contracts/check.response.example.json: the §15.5 laptop Switch / protection response.
    static func responseExample() throws -> Data { try data("check.response.example") }

    /// contracts/check-record.example.json.
    static func recordExample() throws -> CheckRecord {
        try JSONDecoder().decode(CheckRecord.self, from: data("check-record.example"))
    }

    /// The §15.5 request example's OCR text, as on-device reading would return it.
    static func laptopReading() throws -> ScreenReading {
        let request = try JSONDecoder().decode(CheckRequest.self, from: data("check.request.example"))
        return ScreenReading(
            redactedText: request.screen.ocrText,
            redactions: request.screen.redactions,
            ocrConfidence: request.screen.ocrConfidence,
            isCheckout: true
        )
    }

    /// 2026-10-17 14:02:11 in Seattle (the demo day in §6.3).
    static let demoNow = Date(timeIntervalSince1970: 1_792_270_931)
    static let seattle = TimeZone(identifier: "America/Los_Angeles")!
}

/// Serves canned responses for one host per test, so tests can run in parallel. Records every request body.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Behavior: Sendable {
        case respond(status: Int, body: Data)
        case fail(URLError.Code)
    }

    struct Route: Sendable {
        var behavior: Behavior
        var delay: TimeInterval = 0
    }

    private static let routes = Mutex<[String: Route]>([:])
    private static let bodies = Mutex<[String: [Data]]>([:])

    static func register(host: String, route: Route) {
        routes.withLock { $0[host] = route }
        bodies.withLock { $0[host] = [] }
    }

    static func requests(host: String) -> [Data] {
        bodies.withLock { $0[host] ?? [] }
    }

    private let lock = NSLock()
    private var pending: DispatchWorkItem?

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return routes.withLock { $0[host] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let body = request.httpBody ?? Self.read(request.httpBodyStream)
        Self.bodies.withLock { $0[host, default: []].append(body) }
        guard let route = Self.routes.withLock({ $0[host] }) else { return }

        let deliver = DispatchWorkItem { [weak self] in
            guard let self, let client = self.client else { return }
            switch route.behavior {
            case .respond(let status, let data):
                let response = HTTPURLResponse(
                    url: self.request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client.urlProtocol(self, didLoad: data)
                client.urlProtocolDidFinishLoading(self)
            case .fail(let code):
                client.urlProtocol(self, didFailWithError: URLError(code))
            }
        }
        lock.withLock { pending = deliver }
        if route.delay <= 0 {
            deliver.perform()
        } else {
            DispatchQueue.global().asyncAfter(deadline: .now() + route.delay, execute: deliver)
        }
    }

    override func stopLoading() {
        lock.withLock { pending?.cancel() }
    }

    private static func read(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// Records what the intent asked of the island, in order.
actor RecordingIsland: IslandPresenting {
    enum Event: Equatable, Sendable {
        case endAll
        case startChecking
        case alert(PaywiseActivityAttributes.ContentState, AlertSoundChoice)
        case end
    }

    private(set) var events: [Event] = []
    /// The check ID passed to each `startChecking`, `alert` and `end`, in order.
    private(set) var checkIds: [String] = []
    private let available: Bool

    init(available: Bool = true) {
        self.available = available
    }

    func endAll() async { events.append(.endAll) }

    func startChecking(checkId: String) async -> Bool {
        events.append(.startChecking)
        checkIds.append(checkId)
        return available
    }

    func alert(checkId: String, state: PaywiseActivityAttributes.ContentState, sound: AlertSoundChoice) async -> Bool {
        events.append(.alert(state, sound))
        checkIds.append(checkId)
        return available
    }

    func end(checkId: String) async {
        events.append(.end)
        checkIds.append(checkId)
    }

    var alerts: [PaywiseActivityAttributes.ContentState] {
        events.compactMap { if case .alert(let state, _) = $0 { state } else { nil } }
    }
}

/// A fresh, isolated set of dependencies: temp check folder, unique defaults suite, in-memory SwiftData,
/// a stub host, the bundled catalog and replay files, a fixed clock.
struct TestEnvironment {
    let host: String
    let deps: AppDependencies
    let island: RecordingIsland
    let directory: URL

    init(
        reading: ScreenReading,
        route: StubURLProtocol.Route? = nil,
        timeout: Duration = PaywiseAPI.defaultTimeout,
        replayEnabled: Bool = false,
        snippetMode: SnippetMode = .snippet,
        islandAvailable: Bool = true,
        wallet: Wallet = .demo3Card
    ) {
        host = "t\(UUID().uuidString.lowercased().prefix(8)).paywise.test"
        directory = FileManager.default.temporaryDirectory.appending(path: "paywise-tests-\(UUID().uuidString)")
        if let route { StubURLProtocol.register(host: host, route: route) }

        let settings = PaywiseSettings(suiteName: "paywise.tests.\(UUID().uuidString)")
        settings.replayEnabled = replayEnabled
        settings.snippetMode = snippetMode
        WalletStore(settings: settings).save(wallet)

        let island = RecordingIsland(available: islandAvailable)
        self.island = island
        deps = AppDependencies(
            screenReader: FixtureScreenReader(reading: reading),
            api: PaywiseAPI(
                baseURL: URL(string: "https://\(host)")!,
                session: PaywiseAPI.makeSession(timeout: timeout, protocolClasses: [StubURLProtocol.self]),
                timeout: timeout
            ),
            // Aged against the same fixed clock as `now`, so the demo-day records never expire mid-run.
            checkStore: CheckStore(containerURL: directory, now: { Fixtures.demoNow }),
            settings: settings,
            catalog: .bundled(.main),
            replay: ReplayStore(bundle: .main),
            purchases: .inMemory(),
            island: island,
            coverage: CoverageAPI(
                baseURL: URL(string: "https://\(host)")!,
                session: PaywiseAPI.makeSession(timeout: CoverageAPI.defaultTimeout, protocolClasses: [StubURLProtocol.self])
            ),
            offers: OfferStore(containerURL: directory),
            now: { Fixtures.demoNow },
            timeZone: Fixtures.seattle,
            islandHold: .zero,
            fallbackHold: .zero
        )
    }

    var requests: [Data] { StubURLProtocol.requests(host: host) }

    /// Runs the intent with these dependencies.
    @MainActor
    func perform(_ intent: CheckCheckoutIntent) async throws {
        try await Dependencies.$current.withValue(deps) {
            _ = try await intent.perform()
        }
    }

    /// Runs the intent with these dependencies, timed by `trace`.
    @MainActor
    func perform(_ intent: CheckCheckoutIntent, trace: CheckTrace, deps: AppDependencies? = nil) async throws {
        try await Dependencies.$current.withValue(deps ?? self.deps) {
            _ = try await intent.perform(trace: trace)
        }
    }

    static func screenshot() -> CheckCheckoutIntent {
        CheckCheckoutIntent(image: .init(data: Data([0x89, 0x50, 0x4e, 0x47]), filename: "screenshot.png", type: .png))
    }
}
