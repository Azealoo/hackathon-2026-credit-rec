import Foundation
import os
import Synchronization

/// os_signpost intervals for each link of a check (SPEC §15.7 step 6, §9's latency budget), so a press can be timed in
/// Instruments › os_signpost or with `log stream` (docs/spikes.md › "Timing a press"). Each finished link also logs its
/// duration once at `.info`. Only link names and durations: never OCR text, amounts, cards or stores.
///
/// | Interval | From → to |
/// |---|---|
/// | intent-to-checking | `CheckCheckoutIntent.perform()` starts → *Checking* requested from ActivityKit |
/// | read | crop + OCR + checkout gate + redaction, then the request body and its on-device privacy check |
/// | post | `POST /v1/check` (6.0 s timeout), including the replay lookup after a failure |
/// | record | `CheckRecord` built and written to the App Group |
/// | result | `CheckFlow`'s outcome → the snippet or confirmation handed to the system, or the island alert sent |
/// | press-to-result | `perform()` starts → the same moment `result` ends (not the island hold after it) |
///
/// "press" is the intent's start: the Action Button press, the Shortcut and Take Screenshot run before the app sees
/// anything, so that part is timed from a video. A link that doesn't happen (no checkout, so no POST) has no interval.
/// "Check a screenshot" in the app runs the same `CheckFlow`, so it logs `read`, `post` and `record` (source "in-app").
final class CheckTrace: Sendable {
    enum Link: String, CaseIterable, Sendable {
        case intentToChecking = "intent-to-checking"
        case read
        case post
        case record
        case result
        case pressToResult = "press-to-result"

        /// The signpost name (`OSSignposter` takes a `StaticString`): the same text as `rawValue`.
        var name: StaticString {
            switch self {
            case .intentToChecking: "intent-to-checking"
            case .read: "read"
            case .post: "post"
            case .record: "record"
            case .result: "result"
            case .pressToResult: "press-to-result"
            }
        }
    }

    enum Source: String, Sendable {
        /// `CheckCheckoutIntent`: a press.
        case intent
        /// `InAppCheck`: "Check a screenshot" and onboarding's first result.
        case inApp = "in-app"
    }

    static let subsystem = "com.azealoo.paywise"
    static let category = "check"
    static let signposter = OSSignposter(subsystem: subsystem, category: category)
    private static let log = Logger(subsystem: subsystem, category: category)

    let source: Source
    /// One ID per check, so Instruments pairs each check's begin and end.
    private let id: OSSignpostID

    private struct Running: Sendable {
        var state: OSSignpostIntervalState
        var start: ContinuousClock.Instant
    }

    private let running = Mutex<[Link: Running]>([:])
    private let finished = Mutex<[Finished]>([])

    struct Finished: Sendable, Equatable {
        var link: Link
        var duration: Duration
    }

    init(source: Source) {
        self.source = source
        id = Self.signposter.makeSignpostID()
    }

    func begin(_ link: Link) {
        let source = source.rawValue
        let state = Self.signposter.beginInterval(link.name, id: id, "\(source, privacy: .public)")
        running.withLock { $0[link] = Running(state: state, start: .now) }
    }

    /// Ends `link` and logs its duration at `.info`. A no-op if it isn't running, so each link logs once.
    func end(_ link: Link) {
        guard let run = running.withLock({ $0.removeValue(forKey: link) }) else { return }
        let duration = ContinuousClock.now - run.start
        Self.signposter.endInterval(link.name, run.state)
        finished.withLock { $0.append(Finished(link: link, duration: duration)) }
        let name = link.rawValue
        let source = source.rawValue
        let ms = Self.milliseconds(duration)
        Self.log.info("\(name, privacy: .public) \(ms, format: .fixed(precision: 0), privacy: .public) ms (\(source, privacy: .public))")
    }

    /// Ends `link` with no duration logged: what it waits for never happens (no screenshot, so no *Checking*).
    func abandon(_ link: Link) {
        guard let run = running.withLock({ $0.removeValue(forKey: link) }) else { return }
        Self.signposter.endInterval(link.name, run.state, "abandoned")
    }

    /// The result is on screen (or handed to the system): ends `result` and `press-to-result`.
    func resultShown() {
        end(.result)
        end(.pressToResult)
    }

    /// The links that ended, in the order they ended.
    var durations: [Finished] { finished.withLock { $0 } }

    /// Links still running (begun, never ended or abandoned).
    var runningLinks: Set<Link> { running.withLock { Set($0.keys) } }

    static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
    }
}
