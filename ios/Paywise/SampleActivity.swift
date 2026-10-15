import ActivityKit
import Foundation

/// Starts and ends the sample *Checking* activity (debug button) and clears leftovers on launch.
/// Follows §6.2: end every existing Paywise activity with `.immediate` before a request,
/// and set `staleDate = now + 2 min` on every request.
@MainActor
enum SampleActivity {
    /// Debug builds launched with `-autostartSampleActivity` start the sample activity on launch,
    /// so the island can be checked without tapping (e.g. `devicectl device process launch … -autostartSampleActivity`).
    static var autostartRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-autostartSampleActivity")
    }

    static func start() async -> String {
        await endAll()
        let content = ActivityContent(
            state: PaywiseActivityAttributes.ContentState.checking,
            staleDate: .now.addingTimeInterval(120)
        )
        do {
            let activity = try Activity.request(
                attributes: PaywiseActivityAttributes(checkId: UUID().uuidString),
                content: content
            )
            #if DEBUG
            print("[Paywise] requested \(activity.id) state=\(activity.activityState) enabled=\(ActivityAuthorizationInfo().areActivitiesEnabled)")
            Task {
                for await state in activity.activityStateUpdates {
                    print("[Paywise] \(activity.id) state=\(state)")
                }
            }
            #endif
            return "Started \(activity.id)"
        } catch {
            #if DEBUG
            print("[Paywise] request failed: \(error)")
            #endif
            return "Couldn't start: \(error)"
        }
    }

    static func endAll() async {
        for activity in Activity<PaywiseActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
