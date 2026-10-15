import ActivityKit
import Foundation
import os

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
    /// Alerting update of this check's activity (requesting one if none is running). false when no activity could show.
    func alert(checkId: String, state: PaywiseActivityAttributes.ContentState, sound: AlertSoundChoice) async -> Bool
    /// End this check's activity with `.immediate`.
    func end() async
}

/// ActivityKit implementation. One activity at a time; every request and update sets `staleDate = now + 2 min`.
@MainActor
final class LiveActivityController: IslandPresenting {
    nonisolated static let shared = LiveActivityController()
    nonisolated static let staleAfter: TimeInterval = 120
    /// The silent alert sound (design.md §7), bundled with the app and the widget extension.
    nonisolated static let silentSoundName = "silent.caf"

    /// The activity this controller started. Looked up by ID each time (ActivityKit's `Activity` isn't Sendable,
    /// so it isn't kept across suspension points).
    private var currentId: String?

    nonisolated init() {}

    func endAll() async {
        for activity in Activity<PaywiseActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentId = nil
    }

    func startChecking(checkId: String) async -> Bool {
        guard let activity = Self.request(checkId: checkId, state: .checking) else { return false }
        currentId = activity.id
        return true
    }

    func alert(checkId: String, state: PaywiseActivityAttributes.ContentState, sound: AlertSoundChoice) async -> Bool {
        let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(Self.staleAfter))
        // Phones without a Dynamic Island show this as a Lock Screen banner: no card, amount or store (§6.4).
        let alert = AlertConfiguration(
            title: "Paywise",
            body: LocalizedStringResource(stringLiteral: state.lockScreenText),
            sound: sound == .silent ? .named(Self.silentSoundName) : .default
        )
        if let activity = Self.activity(id: currentId), activity.activityState == .active || activity.activityState == .stale {
            await activity.update(content, alertConfiguration: alert)
            return true
        }
        guard let activity = Self.request(checkId: checkId, state: state) else { return false }
        currentId = activity.id
        await activity.update(content, alertConfiguration: alert)
        return true
    }

    func end() async {
        if let activity = Self.activity(id: currentId) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentId = nil
    }

    private nonisolated static func activity(id: String?) -> sending Activity<PaywiseActivityAttributes>? {
        guard let id else { return nil }
        return Activity<PaywiseActivityAttributes>.activities.first { $0.id == id }
    }

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
