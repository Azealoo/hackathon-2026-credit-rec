import ActivityKit
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Paywise

// Review round 2: per-check Live Activities (§6.2), Pattern B's 30 s bound (§6.2), 24 h record retention (§15.5),
// "What we sent" shows the exact payload (§10), replayed results are labelled (§5.2 E), and §6.6's "save later".

/// The real `LiveActivityController` on ActivityKit (the simulator): two overlapping presses never update or end each
/// other's activity, the newest press keeps the island, and nothing is left running. Serialized: every test here owns
/// all Paywise activities.
@MainActor
@Suite(.serialized, .enabled(if: ActivityAuthorizationInfo().areActivitiesEnabled))
struct LiveActivityControllerTests {
    typealias State = PaywiseActivityAttributes.ContentState

    /// (id, checkId, phase, line2) of every activity that is still showing.
    private static func live() -> [(id: String, checkId: String, phase: State.Phase, line2: String?)] {
        Activity<PaywiseActivityAttributes>.activities
            .filter { $0.activityState == .active || $0.activityState == .stale }
            .map { ($0.id, $0.attributes.checkId, $0.content.state.phase, $0.content.state.line2) }
    }

    /// Waits up to 2 s for ActivityKit to settle on `condition`.
    private static func settle(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<40 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    private static func verdict(_ line2: String) -> State {
        State(phase: .error, glyph: .warning, line1: "Couldn't check this time", line2: line2,
              lockScreenText: State.checkedLockScreenText)
    }

    /// The test host app is in front; these tests are about press order, not the app-in-front fallback.
    private let island = LiveActivityController(appIsActive: { false })

    /// With Paywise in front (as in Try it now), iOS shows none of the app's own Live Activities in the island, so
    /// `alert` reports that nothing showed and the intent falls back to the static snippet (§6.6).
    @Test func noIslandAlertWhileTheAppIsInFront() async {
        let front = LiveActivityController(appIsActive: { true })
        await island.endAll()
        let checkId = "front-\(UUID().uuidString.prefix(8))"
        let shown = await front.alert(checkId: checkId, state: Self.verdict("No connection · press again"), sound: .silent)
        #expect(shown == false)
        #expect(Self.live().isEmpty, "no activity was requested for it")
        await front.end(checkId: checkId)
    }

    /// Press 2 starts during press 1's hold: press 1's end leaves press 2's *Checking* alone, and press 2's verdict
    /// updates its own activity.
    @Test func secondPressDuringHold() async throws {
        await island.endAll()
        #expect(await Self.settle { Self.live().isEmpty })

        #expect(await island.startChecking(checkId: "press-1"))
        #expect(await island.alert(checkId: "press-1", state: Self.verdict("PRESS1"), sound: .silent))
        // Press 2: step 1 ends every activity, step 2 starts its own.
        await island.endAll()
        #expect(await island.startChecking(checkId: "press-2"))
        // Press 1's hold ends.
        await island.end(checkId: "press-1")
        #expect(await Self.settle { Self.live().map(\.checkId) == ["press-2"] })
        #expect(Self.live().first?.phase == .checking, "press 2 is still checking")

        #expect(await island.alert(checkId: "press-2", state: Self.verdict("PRESS2"), sound: .silent))
        #expect(await Self.settle { Self.live().first?.line2 == "PRESS2" })
        #expect(Self.live().count == 1)
        await island.end(checkId: "press-2")
        #expect(await Self.settle { Self.live().isEmpty }, "nothing left running")
    }

    /// The order that used to leak an activity and cross the verdicts: press 1's verdict lands between press 2's
    /// `endAll` and its `startChecking`.
    @Test func interleavedPressesNeverCrossOrLeak() async throws {
        await island.endAll()
        #expect(await Self.settle { Self.live().isEmpty })

        #expect(await island.startChecking(checkId: "press-1"))
        await island.endAll()                                                             // press 2, step 1
        #expect(await island.alert(checkId: "press-1", state: Self.verdict("PRESS1"), sound: .silent))
        #expect(await Self.settle { Self.live().map(\.checkId) == ["press-1"] })
        #expect(await island.startChecking(checkId: "press-2"))                           // press 2, step 2
        await island.end(checkId: "press-1")                                              // press 1's hold ends
        #expect(await Self.settle { Self.live().map(\.checkId) == ["press-2"] })
        #expect(await island.alert(checkId: "press-2", state: Self.verdict("PRESS2"), sound: .silent))
        #expect(await Self.settle { Self.live().first?.line2 == "PRESS2" })
        #expect(!Self.live().contains { $0.checkId == "press-2" && $0.line2 == "PRESS1" }, "verdicts never cross")
        await island.end(checkId: "press-2")
        #expect(await Self.settle { Self.live().isEmpty }, "no activity is left that no path ends")
    }

    /// Press 2 starts while press 1 is still checking, and press 1's verdict arrives first. Press 1's *Checking* is
    /// gone (press 2's start ended it), so its verdict is left off the island: press 2 keeps its *Checking* until its own
    /// verdict updates that same activity.
    @Test func olderVerdictWhileNewerPressChecks() async throws {
        await island.endAll()
        #expect(await Self.settle { Self.live().isEmpty })

        #expect(await island.startChecking(checkId: "press-1"))
        await island.endAll()                                                             // press 2, step 1
        #expect(await island.startChecking(checkId: "press-2"))                           // press 2, step 2
        #expect(await Self.settle { Self.live().map(\.checkId) == ["press-2"] })
        let checking = try #require(Self.live().first?.id)

        #expect(await island.alert(checkId: "press-1", state: Self.verdict("PRESS1"), sound: .silent),
                "left off the island, not a failure: no static snippet for press 1")
        try await Task.sleep(for: .milliseconds(300))
        #expect(Self.live().map(\.id) == [checking], "press 2's Checking is still the only activity")
        #expect(Self.live().first?.phase == .checking)
        await island.end(checkId: "press-1")                                              // press 1's hold ends
        #expect(Self.live().map(\.id) == [checking])

        #expect(await island.alert(checkId: "press-2", state: Self.verdict("PRESS2"), sound: .silent))
        #expect(await Self.settle { Self.live().first?.line2 == "PRESS2" })
        #expect(Self.live().map(\.id) == [checking], "press 2's verdict updates its own Checking activity")
        await island.end(checkId: "press-2")
        #expect(await Self.settle { Self.live().isEmpty }, "nothing left running")
    }

    /// Press 1's late verdict arrives while press 2 holds its own: press 2's result stays on the island.
    @Test func olderVerdictDuringNewerHold() async throws {
        await island.endAll()
        #expect(await island.startChecking(checkId: "press-1"))
        await island.endAll()
        #expect(await island.startChecking(checkId: "press-2"))
        #expect(await island.alert(checkId: "press-2", state: Self.verdict("PRESS2"), sound: .silent))
        #expect(await Self.settle { Self.live().first?.line2 == "PRESS2" })

        #expect(await island.alert(checkId: "press-1", state: Self.verdict("PRESS1"), sound: .silent))
        try await Task.sleep(for: .milliseconds(300))
        #expect(Self.live().map(\.checkId) == ["press-2"])
        #expect(Self.live().first?.line2 == "PRESS2")
        await island.end(checkId: "press-1")
        await island.end(checkId: "press-2")
        #expect(await Self.settle { Self.live().isEmpty })
    }

    /// The newer press's activity is gone (swiped away, or ActivityKit refused it): press 1's late verdict still
    /// stays off the island, and press 2's verdict gets an activity of its own.
    @Test func newerPressWithoutActivityStillGetsItsVerdict() async throws {
        await island.endAll()
        #expect(await island.startChecking(checkId: "press-1"))
        await island.endAll()
        #expect(await island.startChecking(checkId: "press-2"))
        for activity in Activity<PaywiseActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)                          // not through the island
        }
        #expect(await Self.settle { Self.live().isEmpty })

        #expect(await island.alert(checkId: "press-1", state: Self.verdict("PRESS1"), sound: .silent))
        try await Task.sleep(for: .milliseconds(300))
        #expect(Self.live().isEmpty, "the older verdict never takes the island from a running newer press")
        await island.end(checkId: "press-1")

        #expect(await island.alert(checkId: "press-2", state: Self.verdict("PRESS2"), sound: .silent))
        #expect(await Self.settle { Self.live().map(\.checkId) == ["press-2"] })
        #expect(Self.live().first?.line2 == "PRESS2")
        await island.end(checkId: "press-2")
        #expect(await Self.settle { Self.live().isEmpty })
    }

    /// Once the newer press has ended, an older press's late verdict shows again (§6.2: after ending every activity).
    @Test func olderVerdictAfterNewerPressEnded() async throws {
        await island.endAll()
        #expect(await island.startChecking(checkId: "press-1"))
        await island.endAll()
        #expect(await island.startChecking(checkId: "press-2"))
        await island.end(checkId: "press-2")

        #expect(await island.alert(checkId: "press-1", state: Self.verdict("PRESS1"), sound: .silent))
        #expect(await Self.settle { Self.live().map(\.checkId) == ["press-1"] })
        #expect(Self.live().first?.line2 == "PRESS1")
        await island.end(checkId: "press-1")
        #expect(await Self.settle { Self.live().isEmpty })
    }

    /// What the sampler saw, on the main actor.
    @MainActor private final class Samples {
        var rows: [[(id: String, checkId: String, phase: State.Phase, line2: String?)]] = []
        /// `rows.count` when press 1's `perform()` returned.
        var press1Returned: Int?
    }

    /// The review's scenario end to end, with two real intents: press 2 starts while press 1 is checking, and press 1's
    /// *Couldn't check* arrives first. Press 1 runs to the end (verdict, hold, end) while press 2 keeps one *Checking*
    /// activity, which press 2's own verdict then updates.
    @Test func twoIntentsSecondPressWhileFirstChecks() async throws {
        await island.endAll()
        #expect(await Self.settle { Self.live().isEmpty })
        func press(_ route: StubURLProtocol.Route, timeout: Duration) throws -> (TestEnvironment, AppDependencies) {
            let env = TestEnvironment(reading: try Fixtures.laptopReading(), route: route, timeout: timeout)
            var deps = env.deps
            deps.island = island
            deps.islandHold = .milliseconds(300)
            return (env, deps)
        }
        let press1 = try press(.init(behavior: .fail(.notConnectedToInternet), delay: 0.8), timeout: .seconds(6))
        let press2 = try press(.init(behavior: .fail(.notConnectedToInternet), delay: 10), timeout: .seconds(2))

        let samples = Samples()
        let sampler = Task { @MainActor in
            while !Task.isCancelled {
                samples.rows.append(Self.live())
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
        let first = Task { @MainActor in
            try await press1.0.perform(TestEnvironment.screenshot(), trace: CheckTrace(source: .intent), deps: press1.1)
            samples.press1Returned = samples.rows.count
        }
        try await Task.sleep(for: .milliseconds(300))
        let second = Task { @MainActor in
            try await press2.0.perform(TestEnvironment.screenshot(), trace: CheckTrace(source: .intent), deps: press2.1)
        }
        try await first.value
        try await second.value
        try await Task.sleep(for: .milliseconds(200))
        sampler.cancel()

        let c1 = try #require(press1.0.deps.checkStore.latest()?.checkId)
        let c2 = try #require(press2.0.deps.checkStore.latest()?.checkId)
        let rows = samples.rows
        let checkingAt = try #require(rows.firstIndex { $0.contains { $0.checkId == c2 && $0.phase == .checking } })
        let checking = try #require(rows[checkingAt].first { $0.checkId == c2 }?.id)
        let verdictAt = try #require(rows.firstIndex { $0.contains { $0.checkId == c2 && $0.phase != .checking } })
        let press1Returned = try #require(samples.press1Returned)
        #expect(checkingAt < press1Returned && press1Returned < verdictAt,
                "press 1 ran to the end while press 2 was checking")
        #expect(rows[checkingAt..<verdictAt].allSatisfy { $0.map(\.id) == [checking] && $0.first?.phase == .checking },
                "press 2's Checking is the only activity, unbroken, until its verdict")
        #expect(rows[verdictAt].map(\.id) == [checking], "press 2's verdict updates its own Checking activity")
        #expect(rows[verdictAt].first?.line2?.hasPrefix("Took too long") == true)
        #expect(!rows.joined().contains { $0.checkId == c1 && $0.phase != .checking },
                "press 1's late verdict is left off the island")
        #expect(Self.live().isEmpty, "nothing left running")
    }

    /// `end(checkId:)` ends every activity its check requested, and only those.
    @Test func endOnlyEndsItsOwnCheck() async throws {
        await island.endAll()
        #expect(await island.startChecking(checkId: "press-1"))
        await island.end(checkId: "someone-else")
        #expect(await Self.settle { Self.live().map(\.checkId) == ["press-1"] })
        await island.end(checkId: "press-1")
        #expect(await Self.settle { Self.live().isEmpty })
    }
}

/// The intent ends the activity of its own check on every path (with the recording island).
@MainActor
struct IntentEndsItsOwnActivityTests {
    @Test func snippetPathEndsItsOwnCheck() async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample()))
        )
        try await env.perform(TestEnvironment.screenshot())
        let record = try #require(env.deps.checkStore.latest())
        #expect(await env.island.events == [.endAll, .startChecking, .end])
        #expect(await env.island.checkIds == [record.checkId, record.checkId])
    }

    @Test func islandPathEndsItsOwnCheck() async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample())),
            snippetMode: .island
        )
        try await env.perform(TestEnvironment.screenshot())
        let record = try #require(env.deps.checkStore.latest())
        #expect(await env.island.events.last == .end)
        #expect(await env.island.checkIds == Array(repeating: record.checkId, count: 3))
    }
}

/// §6.2 "the intent never runs past 30 s": Pattern B's prompt is given up in time, even if it ignores cancellation.
struct ConfirmationDeadlineTests {
    /// A prompt that never answers and ignores cancellation (it would hold `withDeadline`'s task group).
    private static let unanswered: @Sendable () async throws -> Void = {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { continuation.resume() }
        }
    }

    @Test func unansweredPromptTimesOutOnTime() async {
        let clock = ContinuousClock()
        let start = clock.now
        let answer = await CheckCheckoutIntent.confirmation(within: .milliseconds(200), Self.unanswered)
        #expect(answer == .timedOut)
        #expect(clock.now - start < .seconds(1.5), "returned at the deadline, not when the prompt gave up")
    }

    @Test func answersPassThrough() async {
        #expect(await CheckCheckoutIntent.confirmation(within: .seconds(5)) {} == .confirmed)
        #expect(await CheckCheckoutIntent.confirmation(within: .seconds(5)) { throw CancellationError() } == .declined)
    }

    @Test func noTimeLeftMeansNoPrompt() async {
        let asked = PromptCounter()
        let answer = await CheckCheckoutIntent.confirmation(within: .zero) { asked.increment() }
        #expect(answer == .timedOut)
        #expect(asked.count == 0)
    }

    @Test func hardDeadlineHonoursCallerCancellation() async {
        let task = Task { try await withHardDeadline(.seconds(10), Self.unanswered) }
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
    }

    /// The default limit leaves room inside §6.2's 30 s.
    @Test func defaultLimitIsUnderThirtySeconds() {
        #expect(AppDependencies.live.intentLimit < .seconds(30))
        #expect(AppDependencies.live.intentLimit >= .seconds(20), "room for reading, the request and a real answer")
    }
}

private final class PromptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}

/// §15.5: records older than 24 h never show, even before the next write prunes them, and launch prunes them.
@MainActor
struct CheckRetentionTests {
    private static let day: TimeInterval = 24 * 3600

    private static func oldRecord(id: String, age: TimeInterval) throws -> CheckRecord {
        var record = try Fixtures.recordExample()
        record.checkId = id
        record.createdAt = CheckRecord.timestamp(Fixtures.demoNow.addingTimeInterval(-age), timeZone: Fixtures.seattle)
        return record
    }

    @Test func readsLeaveOutExpiredRecordsWithoutAWrite() throws {
        let env = TestEnvironment(reading: try Fixtures.laptopReading())
        // Written when it was fresh, so the write itself pruned nothing.
        let old = try Self.oldRecord(id: "old-1", age: Self.day + 60)
        try env.deps.checkStore.write(old, now: Fixtures.demoNow.addingTimeInterval(-Self.day))
        try env.deps.checkStore.write(try Self.oldRecord(id: "new-1", age: 60), now: Fixtures.demoNow.addingTimeInterval(-Self.day))
        let file = env.deps.checkStore.directory.appending(path: "old-1.json")
        #expect(FileManager.default.fileExists(atPath: file.path()))

        // No further write: the store's own clock (the demo day) ages them on read.
        let store = env.deps.checkStore
        #expect(store.record(id: "old-1") == nil)
        #expect(store.all().map(\.checkId) == ["new-1"])
        #expect(store.newestFirst().map(\.checkId) == ["new-1"])
        #expect(store.latest()?.checkId == "new-1")
        #expect(throws: CheckStore.StoreError.notFound) { try store.update(id: "old-1") { $0.view = .sent } }
        #expect(store.record(id: "new-1") != nil)
    }

    @Test func launchPrunesExpiredRecords() throws {
        let env = TestEnvironment(reading: try Fixtures.laptopReading())
        try env.deps.checkStore.write(
            try Self.oldRecord(id: "old-2", age: 2 * Self.day), now: Fixtures.demoNow.addingTimeInterval(-2 * Self.day)
        )
        let file = env.deps.checkStore.directory.appending(path: "old-2.json")
        #expect(FileManager.default.fileExists(atPath: file.path()))

        _ = AppModel(deps: env.deps, launch: LaunchOptions())
        #expect(!FileManager.default.fileExists(atPath: file.path()), "pruned on launch, not only on the next write")
    }
}

/// §10: "What we sent" shows the exact payload: the redacted text, then every other field as sent.
struct SentPayloadTests {
    @Test func everyFieldIsShownAsSent() throws {
        let record = try Fixtures.recordExample()
        #expect(record.sentFields == [
            #"client.app: "paywise-ios""#,
            #"client.version: "0.1.0""#,
            #"clientDate: "2026-10-17""#,
            "prefs.paysInFull: null",
            #"requestId: "5f0c0000-aaaa-4bbb-8ccc-ddddeeeeffff""#,
            "screen.ocrConfidence: 0.93",
            #"screen.redactions: ["card_number","address","email","phone"]"#,
            #"wallet.cards[0].cardId: "apple-card""#,
            "wallet.cards[0].isDefault: true",
            #"wallet.cards[1].cardId: "wf-active-cash""#,
            "wallet.cards[1].isDefault: false",
            #"wallet.cards[2].cardId: "chase-freedom-unlimited""#,
            "wallet.cards[2].isDefault: false",
        ])
        // The text itself shows above the fields, verbatim.
        #expect(!record.sentFields.contains { $0.hasPrefix("screen.ocrText") })
        #expect(record.sentText.hasPrefix("Northbay Electronics\nCheckout\n"))
    }

    /// The fields come from the stored body itself: a check's record lists what that request carried.
    @Test func fieldsFollowTheRequestThatWasSent() async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample()))
        )
        try await env.perform(TestEnvironment.screenshot())
        let body = try #require(env.requests.first)
        let sent = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let record = try #require(env.deps.checkStore.latest())
        let requestId = try #require(sent["requestId"] as? String)
        #expect(record.sentFields.contains("requestId: \"\(requestId)\""))
        #expect(record.sentFields.contains(#"clientDate: "2026-10-17""#))
        #expect(record.sentFields.contains(#"wallet.cards[2].cardId: "chase-freedom-unlimited""#))
        #expect(record.sentText == (sent["screen"] as? [String: Any])?["ocrText"] as? String)
    }
}

/// §5.2 E: a replayed result is labelled in the Result and Saved views too, not only in Sent.
@MainActor
struct ReplayedLabelTests {
    private static func png(_ record: CheckRecord) throws -> Data {
        let renderer = ImageRenderer(
            content: CheckResultView(record: record, catalog: .bundled())
                .frame(width: 371)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 1
        return try #require(renderer.uiImage?.pngData())
    }

    @Test(arguments: [CheckRecord.Screen.result, .saved, .sent])
    func replayedRecordRendersTheLabel(view: CheckRecord.Screen) throws {
        var live = try #require(CheckRecord.preview(view: view))
        live.replayed = false
        var replayed = live
        replayed.replayed = true
        #expect(try Self.png(live) != (try Self.png(replayed)), "\(view): the replayed label shows")
    }
}

/// §6.3 *Switch fallback* / §6.6: with the island alert, the press's result is saved later from the Check tab.
@MainActor
struct SaveLaterTests {
    private func islandPress() async throws -> (TestEnvironment, CheckRecord) {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample())),
            snippetMode: .island
        )
        try await env.perform(TestEnvironment.screenshot())
        let record = try #require(env.deps.checkStore.latest())
        return (env, record)
    }

    @Test func islandFallbackResultIsSavedLaterInTheApp() async throws {
        let (env, record) = try await islandPress()
        #expect(record.savedPurchaseId == nil, "the island alert saves nothing")
        #expect(env.deps.settings.lastPressCheckId == record.checkId)

        let check = InAppCheck(deps: env.deps)
        check.offerLastPress()
        #expect(check.showsLastPress)
        #expect(check.record?.checkId == record.checkId)
        #expect(CheckResultView.showsSaveButton(try #require(check.record), catalog: env.deps.catalog))

        await check.save()
        let purchases = try await env.deps.purchases.store().all()
        #expect(purchases.count == 1)
        #expect(purchases.first?.status == .planned)
        #expect(check.record?.view == .saved)

        // Saved: never offered again.
        let later = InAppCheck(deps: env.deps)
        later.offerLastPress()
        #expect(later.phase == .idle)
    }

    @Test func notOfferedOnceExpiredOrAfterAnInAppCheck() async throws {
        let (env, _) = try await islandPress()

        // A day later the record has expired.
        var tomorrow = env.deps
        tomorrow.checkStore = CheckStore(
            containerURL: env.directory, now: { Fixtures.demoNow.addingTimeInterval(24 * 3600 + 60) }
        )
        let expired = InAppCheck(deps: tomorrow)
        expired.offerLastPress()
        #expect(expired.phase == .idle)

        // A check run in the app is the latest check now.
        let check = InAppCheck(deps: env.deps)
        await check.run(imageData: Data([0x89]))
        #expect(env.deps.settings.lastPressCheckId == nil)
        #expect(!check.showsLastPress)
    }

    @Test func aResultWithNothingToSaveIsNotOffered() async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(), route: .init(behavior: .fail(.notConnectedToInternet)),
            snippetMode: .island
        )
        try await env.perform(TestEnvironment.screenshot())
        #expect(env.deps.settings.lastPressCheckId != nil)
        let check = InAppCheck(deps: env.deps)
        check.offerLastPress()
        #expect(check.phase == .idle, "Couldn't check has no [Paying with …]")
    }

    /// Pattern A's snippet carries [Paying with …] itself, so nothing is offered later (and an older offer is dropped).
    @Test func snippetModePressIsNotOffered() async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample()))
        )
        env.deps.settings.lastPressCheckId = "older-press"
        try await env.perform(TestEnvironment.screenshot())
        #expect(env.deps.settings.lastPressCheckId == nil)
        let check = InAppCheck(deps: env.deps)
        check.offerLastPress()
        #expect(check.phase == .idle)
    }

    @Test func confirmModeStaticSnippetIsOffered() async throws {
        let env = TestEnvironment(
            reading: try Fixtures.laptopReading(),
            route: .init(behavior: .respond(status: 200, body: try Fixtures.responseExample())),
            snippetMode: .confirm
        )
        try await env.perform(TestEnvironment.screenshot())
        let record = try #require(env.deps.checkStore.latest())
        #expect(env.deps.settings.lastPressCheckId == record.checkId)
        let check = InAppCheck(deps: env.deps)
        check.offerLastPress()
        #expect(check.record?.checkId == record.checkId)
    }

    @Test func aRunningCheckIsNeverInterrupted() async throws {
        let (env, _) = try await islandPress()
        let check = InAppCheck(deps: env.deps)
        check.show(.checking)
        check.offerLastPress()
        #expect(check.phase == .checking)
    }
}
