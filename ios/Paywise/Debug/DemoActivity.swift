#if DEBUG
import ActivityKit
import Foundation
import os

/// Debug-only screenshot hook: `-demoActivity <state>` starts that Live Activity state on launch, with the §6.3 copy
/// for the demo wallet, and leaves it running; `-demoActivity end` ends every Paywise activity.
///
///     xcrun simctl launch <device> com.azealoo.paywise -demoActivity keep
///     xcrun simctl launch --terminate-running-process <device> com.azealoo.paywise -demoActivity end
///
/// Result states are requested and then updated with an alert, as a real press does, so the island expands.
/// Unlike a real check (staleDate = now + 2 min, §6.2) a demo state never goes stale, so a screenshot taken minutes
/// later still shows it; `stale` uses a staleDate in the past.
enum DemoActivity: String, CaseIterable, Sendable {
    case checking
    case keep
    case keepMethod
    case noCheckout
    case couldntCheck
    case switchFallback
    case stale

    typealias State = PaywiseActivityAttributes.ContentState

    /// The state, built the way a real press builds it: backend-style copy filled for `wallet` by `CopyFill`, then
    /// `CheckFlow.islandState` (or `CheckFlow`'s own on-device states).
    func state(deps: AppDependencies, wallet: Wallet = .demo3Card) -> State {
        let flow = CheckFlow(deps: deps)
        func island(_ decision: CheckResponse.Decision?) -> State {
            let copy = CopyFill.fill(
                decision?.copy, wallet: wallet, ppCap: CopyFill.ppCap(decision: decision, catalog: deps.catalog)
            )
            return flow.islandState(decision: decision, copy: copy, wallet: wallet)
        }
        switch self {
        case .checking, .stale:
            return .checking
        case .keep:
            return island(DemoChecks.keepDefaultBest(deps.catalog))
        case .keepMethod:
            return island(DemoChecks.keepMethod(deps.catalog))
        case .noCheckout:
            return CheckFlow.noCheckoutOnDevice
        case .couldntCheck:
            let response = CheckFlow.couldntCheckResponse(checkId: "demo", failure: .offline)
            return island((try? response.decode(CheckResponse.self))?.decision)
        case .switchFallback:
            return island(DemoChecks.laptopSwitch()?.decision)
        }
    }

    /// Result states alert (the island expands); *Checking* and stale don't.
    var alerts: Bool {
        switch self {
        case .checking, .stale: false
        default: true
        }
    }

    /// The sound a real press would use: `.default` for the switch fallback (§6.6), else the silent setting.
    func sound(settings: PaywiseSettings) -> AlertSoundChoice {
        if self == .switchFallback { return .standard }
        return settings.silentAlerts ? .silent : .standard
    }

    enum Command: Equatable, Sendable {
        case start(DemoActivity)
        case end
    }

    /// `-demoActivity <state|end>` from the launch arguments.
    static func command(arguments: [String] = ProcessInfo.processInfo.arguments) -> Command? {
        guard let index = arguments.firstIndex(of: "-demoActivity") else { return nil }
        guard index + 1 < arguments.count else {
            log.error("-demoActivity needs a state: \(allCases.map(\.rawValue).joined(separator: "|"), privacy: .public)|end")
            return nil
        }
        let value = arguments[index + 1]
        if value == "end" { return .end }
        guard let demo = DemoActivity(rawValue: value) else {
            log.error("-demoActivity: unknown state \(value, privacy: .public)")
            return nil
        }
        return .start(demo)
    }

    static let log = Logger(subsystem: "com.azealoo.paywise", category: "demo")

    /// Ends every Paywise activity, then starts the demo state (if any). Returns a status line for the debug UI.
    static func run(_ command: Command, deps: AppDependencies = Dependencies.current) async -> String {
        for activity in Activity<PaywiseActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard case .start(let demo) = command else {
            log.notice("demoActivity end: ended all Paywise activities")
            return "Ended all Paywise activities"
        }

        let state = demo.state(deps: deps)
        let staleDate: Date? = demo == .stale ? .now.addingTimeInterval(-60) : nil
        let content = ActivityContent(state: state, staleDate: staleDate)
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        let activity: Activity<PaywiseActivityAttributes>
        do {
            activity = try Activity.request(
                attributes: PaywiseActivityAttributes(checkId: "demo-\(demo.rawValue)"),
                content: content
            )
        } catch {
            log.error("""
            demoActivity \(demo.rawValue, privacy: .public): request failed (activities enabled: \(enabled, privacy: .public)): \
            \(String(describing: error), privacy: .public)
            """)
            return "Couldn't start \(demo.rawValue): \(error)"
        }
        let id = activity.id
        log.notice("""
        demoActivity \(demo.rawValue, privacy: .public): requested \(id, privacy: .public), \
        state \(String(describing: activity.activityState), privacy: .public), activities enabled: \(enabled, privacy: .public), \
        line1 \(state.line1, privacy: .public)
        """)
        if demo.alerts {
            let alert = AlertConfiguration(
                title: "Paywise",
                body: LocalizedStringResource(stringLiteral: state.lockScreenText),
                sound: demo.sound(settings: deps.settings) == .silent
                    ? .named(LiveActivityController.silentSoundName) : .default
            )
            await activity.update(content, alertConfiguration: alert)
            log.notice("demoActivity \(demo.rawValue, privacy: .public): alert update sent to \(id, privacy: .public)")
        }
        return "Started \(demo.rawValue) (\(id))"
    }
}
#endif
