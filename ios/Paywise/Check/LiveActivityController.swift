import ActivityKit
import Foundation
import os
import UIKit

/// Alert sound for an island update (R5: "silentAlerts" picks between these; the switch fallback always uses `.default`).
enum AlertSoundChoice: Sendable, Equatable {
    case silent
    case standard
}

/// The Dynamic Island / Live Activity side of a check (SPEC §6.2). Tests use a recording fake.
protocol IslandPresenting: Sendable {
    /// End every Paywise activity with `.immediate`.
    func endAll() async
    /// Request *Checking*. false when ActivityKit refused; the check then continues without it (§6.6).
    func startChecking(checkId: String) async -> Bool
    /// Alerting update of this check's activity (requesting one if none is running). true when it shows, and also when
    /// a newer press holds the island (this result is then left off it). false when no activity could show, or the
    /// island wouldn't show it because Paywise is in front.
    func alert(checkId: String, state: PaywiseActivityAttributes.ContentState, sound: AlertSoundChoice) async -> Bool
    /// End this check's activities with `.immediate`; any other check's are left alone.
    func end(checkId: String) async
}

/// ActivityKit implementation. Every request and update sets `staleDate = now + 2 min`.
///
/// Each call acts on the activities of *its* check, found by `attributes.checkId`, never on whichever activity started
/// last: two overlapping presses (the Action Button, Back Tap and the Share Sheet are separate triggers) then never
/// update or end each other's activity, and every activity a check requested is ended by that check's `end`. Per §6.2,
/// every Paywise activity is ended before each `Activity.request` (and by `endAll`, on launch and at a check's start),
/// so one shows at a time.
///
/// The newest press owns the island (a repeat press within `AppDependencies.repeatWindow` never starts: `PressGate`
/// turns it away first). A check's start ends any older press's *Checking*, so the older result has no
/// activity left to update. If it arrives while the newer press is still running (checking or holding its result), it
/// is left off the island; a result that was sent stays in What we sent. Requesting an activity for it would first
/// end the newer press's activity (§6.2) and leave that press with no island while it is still checking.
@MainActor
final class LiveActivityController: IslandPresenting {
    nonisolated static let shared = LiveActivityController()
    nonisolated static let staleAfter: TimeInterval = 120
    /// The silent alert sound (design.md §7), bundled with the app and the widget extension.
    nonisolated static let silentSoundName = "silent.caf"

    /// Each running check's place in press order: set when it asks for *Checking*, removed by its `end`.
    private var pressOrder: [String: Int] = [:]
    private var presses = 0

    /// Whether Paywise is in front (as in Try it now): iOS then shows none of the app's own Live Activities in the
    /// Dynamic Island.
    private let appIsActive: @MainActor @Sendable () -> Bool

    nonisolated init(
        appIsActive: @escaping @MainActor @Sendable () -> Bool = { UIApplication.shared.applicationState == .active }
    ) {
        self.appIsActive = appIsActive
    }

    func endAll() async {
        for activity in Activity<PaywiseActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func startChecking(checkId: String) async -> Bool {
        presses += 1
        pressOrder[checkId] = presses
        // §6.2: every Paywise activity is ended before each request.
        await endAll()
        return Self.request(checkId: checkId, state: .checking) != nil
    }

    func alert(checkId: String, state: PaywiseActivityAttributes.ContentState, sound: AlertSoundChoice) async -> Bool {
        // With Paywise in front, an island answer would never be seen: report that nothing showed, so the intent shows
        // the static snippet instead (§6.6).
        guard !appIsActive() else { return false }
        let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(Self.staleAfter))
        // Phones without a Dynamic Island show this as a Lock Screen banner: no card, amount or store (§6.4).
        let alert = AlertConfiguration(
            title: "Paywise",
            body: LocalizedStringResource(stringLiteral: state.lockScreenText),
            sound: sound == .silent ? .named(Self.silentSoundName) : .default
        )
        if let activity = Self.running(checkId: checkId) {
            await activity.update(content, alertConfiguration: alert)
            return true
        }
        // This check's *Checking* never started, or a newer press's start ended it. While a newer press runs, it keeps
        // the island. Otherwise request an activity for the result, after ending every Paywise activity (§6.2).
        if newerPressIsRunning(than: checkId) { return Self.leftOff() }
        await endAll()
        // A newer press may have started while `endAll` was suspended. Nothing suspends between this check and the
        // request.
        if newerPressIsRunning(than: checkId) { return Self.leftOff() }
        guard let activity = Self.request(checkId: checkId, state: state) else { return false }
        await activity.update(content, alertConfiguration: alert)
        return true
    }

    func end(checkId: String) async {
        pressOrder[checkId] = nil
        for activity in Activity<PaywiseActivityAttributes>.activities where activity.attributes.checkId == checkId {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Whether a check that asked for *Checking* after this one hasn't ended yet. An activity this controller didn't
    /// start (a leftover or the debug sample) never counts.
    private func newerPressIsRunning(than checkId: String) -> Bool {
        let mine = pressOrder[checkId] ?? 0
        return pressOrder.contains { $0.key != checkId && $0.value > mine }
    }

    /// An older press's result, left off the island because a newer press holds it.
    private static func leftOff() -> Bool {
        Logger(subsystem: "com.azealoo.paywise", category: "island")
            .info("Result left off the island: a newer press holds it")
        return true
    }

    /// This check's activity that can still be updated.
    private nonisolated static func running(checkId: String) -> sending Activity<PaywiseActivityAttributes>? {
        Activity<PaywiseActivityAttributes>.activities.first {
            $0.attributes.checkId == checkId && ($0.activityState == .active || $0.activityState == .stale)
        }
    }

    /// nil when ActivityKit refused (§6.6: the check then continues without it).
    private nonisolated static func request(
        checkId: String, state: PaywiseActivityAttributes.ContentState
    ) -> sending Activity<PaywiseActivityAttributes>? {
        do {
            return try Activity.request(
                attributes: PaywiseActivityAttributes(checkId: checkId),
                content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(staleAfter))
            )
        } catch {
            Logger(subsystem: "com.azealoo.paywise", category: "island")
                .error("Live Activity request failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
