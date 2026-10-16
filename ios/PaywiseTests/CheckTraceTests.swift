import Foundation
import Testing
@testable import Paywise

/// SPEC §15.7 step 6, "os_signpost per link": `CheckTrace` opens one interval per link of a press and ends each once
/// (each end also logs the duration at `.info`). The flow's answers are unchanged.
@MainActor
struct CheckTraceTests {
    typealias Link = CheckTrace.Link

    @Test func signpostNamesSubsystemAndCategory() {
        #expect(CheckTrace.subsystem == "com.azealoo.paywise")
        #expect(CheckTrace.category == "check")
        #expect(Link.allCases.map(\.rawValue) == [
            "intent-to-checking", "read", "post", "record", "result", "press-to-result",
        ])
        // The StaticString handed to OSSignposter is the documented name (docs/spikes.md).
        for link in Link.allCases {
            #expect("\(link.name)" == link.rawValue)
        }
    }

    @Test func millisecondsFromDuration() {
        #expect(CheckTrace.milliseconds(.seconds(2)) == 2000)
        #expect(CheckTrace.milliseconds(.milliseconds(412)) == 412)
        #expect(abs(CheckTrace.milliseconds(.microseconds(1500)) - 1.5) < 0.000_1)
    }

    /// A Switch press (Pattern A snippet): every link, once, in order, and nothing left open.
    @Test func snippetPressTimesEveryLinkOnceInOrder() async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample()))
        )
        let trace = CheckTrace(source: .intent)
        try await env.perform(TestEnvironment.screenshot(), trace: trace)

        #expect(trace.durations.map(\.link) == [.intentToChecking, .read, .post, .record, .result, .pressToResult])
        #expect(trace.runningLinks.isEmpty)
        let total = try #require(trace.durations.last?.duration)
        for finished in trace.durations {
            #expect(finished.duration >= .zero, "\(finished.link.rawValue)")
            #expect(finished.duration <= total, "\(finished.link.rawValue) is longer than press-to-result")
        }

        // The flow still answers as before.
        let record = try #require(env.deps.checkStore.latest(now: Fixtures.demoNow))
        #expect(record.filledCopy.line1 == "Use Freedom ••1234")
        #expect(await env.island.events == [.endAll, .startChecking, .end])
    }

    /// No checkout on the phone: no POST and no record, so those links have no interval. The island hold comes after
    /// `result`, so press-to-result doesn't include it.
    @Test func noCheckoutPressSkipsPostAndRecordAndExcludesTheHold() async throws {
        let env = TestEnvironment(reading: .notCheckout)
        var deps = env.deps
        deps.islandHold = .seconds(1)
        let trace = CheckTrace(source: .intent)
        let clock = ContinuousClock()
        let start = clock.now
        try await env.perform(TestEnvironment.screenshot(), trace: trace, deps: deps)
        let elapsed = clock.now - start

        #expect(trace.durations.map(\.link) == [.intentToChecking, .read, .result, .pressToResult])
        #expect(trace.runningLinks.isEmpty)
        #expect(elapsed >= .seconds(1))
        let total = try #require(trace.durations.last?.duration)
        #expect(total < .seconds(1), "press-to-result includes the island hold")

        let alert = try #require(await env.island.alerts.first)
        #expect(alert == CheckFlow.noCheckoutOnDevice)
        #expect(env.requests.isEmpty)
    }

    /// No screenshot (§6.3 *Not set up*): *Checking* is never requested, so its interval is abandoned, not timed.
    @Test func notSetUpAbandonsIntentToChecking() async throws {
        let env = TestEnvironment(reading: .laptopCheckout)
        let trace = CheckTrace(source: .intent)
        try await env.perform(CheckCheckoutIntent(image: nil), trace: trace)

        #expect(trace.durations.map(\.link) == [.result, .pressToResult])
        #expect(trace.runningLinks.isEmpty)
        #expect(await env.island.events == [.endAll])
    }

    /// "Check a screenshot" runs the same flow: `read`, `post` and `record`, with no intent links.
    @Test func inAppCheckTimesTheFlowLinks() async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample()))
        )
        let trace = CheckTrace(source: .inApp)
        let outcome = await Dependencies.$current.withValue(env.deps) {
            await CheckFlow(deps: env.deps).run(imageData: Data([0x89]), trace: trace)
        }
        guard case .snippet = outcome else {
            Issue.record("expected the snippet, got \(outcome)")
            return
        }
        #expect(trace.durations.map(\.link) == [.read, .post, .record])
        #expect(trace.runningLinks.isEmpty)
        #expect(trace.source.rawValue == "in-app")
    }
}
