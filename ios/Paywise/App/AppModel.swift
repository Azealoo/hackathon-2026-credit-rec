import Foundation
import os
import SwiftData
import SwiftUI

/// The app shell's state: onboarding or the three tabs, the selected tab and the appearance it forces.
@MainActor
@Observable
final class AppModel {
    enum Tab: String, CaseIterable, Hashable, Sendable {
        case check, purchases, settings
    }

    let deps: AppDependencies
    let purchases: PurchasesModel
    var tab: Tab
    private(set) var onboarded: Bool
    /// Onboarding run again from Settings starts from the current wallet; the first run starts empty.
    private(set) var onboardingWallet: Wallet?
    var purchasePath: [PurchaseRoute] = []

    init(deps: AppDependencies = Dependencies.current, launch: LaunchOptions = .current) {
        launch.applyOnce(deps: deps)
        // §15.5: check records older than 24 h are pruned on launch too, not only when the next check is written.
        deps.checkStore.prune(now: deps.now())
        self.deps = deps
        purchases = PurchasesModel(deps: deps)
        tab = launch.tab ?? .check
        onboarded = deps.settings.onboarded
    }

    /// docs/design.md §1: paying is light, "14 months later" is dark; Settings (and onboarding) follow the system.
    var colorScheme: ColorScheme? {
        guard onboarded else { return nil }
        return switch tab {
        case .check: .light
        case .purchases: .dark
        case .settings: nil
        }
    }

    func finishOnboarding() {
        deps.settings.onboarded = true
        onboarded = true
        onboardingWallet = nil
        tab = .check
    }

    func rerunOnboarding() {
        onboardingWallet = deps.walletStore.load()
        onboarded = false
    }
}

/// Launch arguments for tests and screenshots (debug builds only):
/// `-resetState` (clear the wallet, purchases, check records and onboarding), `-skipOnboarding` (seed the demo
/// wallet), `-dateOverride YYYY-MM-DD` ("Pretend today is…" on), `-tab check|purchases|settings`.
/// `-demoActivity` and `-gallery` are read by their own hooks.
struct LaunchOptions: Equatable, Sendable {
    var resetState = false
    var skipOnboarding = false
    var dateOverride: String?
    var tab: AppModel.Tab?

    static var current: LaunchOptions {
        #if DEBUG
        parse(ProcessInfo.processInfo.arguments)
        #else
        LaunchOptions()
        #endif
    }

    static func parse(_ arguments: [String]) -> LaunchOptions {
        var options = LaunchOptions()
        options.resetState = arguments.contains("-resetState")
        options.skipOnboarding = arguments.contains("-skipOnboarding")
        if let value = value(after: "-dateOverride", in: arguments), PaywiseSettings.isDay(value) {
            options.dateOverride = value
        }
        if let value = value(after: "-tab", in: arguments) {
            options.tab = AppModel.Tab(rawValue: value)
        }
        return options
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private static let log = Logger(subsystem: "com.azealoo.paywise", category: "launch")

    @MainActor private static var applied = false

    /// `apply` once per launch: SwiftUI may build the root view (and so an `AppModel`) more than once, and a second
    /// `-resetState` would wipe what the session has done since.
    @MainActor
    func applyOnce(deps: AppDependencies) {
        guard !Self.applied else { return }
        Self.applied = true
        apply(deps: deps)
    }

    /// Applies the options before any screen reads state: reset first, then the seeds.
    @MainActor
    func apply(deps: AppDependencies) {
        let settings = deps.settings
        if resetState {
            for key in [
                PaywiseSettings.Key.wallet, PaywiseSettings.Key.onboarded, PaywiseSettings.Key.dateOverrideEnabled,
                PaywiseSettings.Key.dateOverride, PaywiseSettings.Key.inAppCheckCount, PaywiseSettings.Key.triggerSetupDone,
                PaywiseSettings.Key.lastPressCheckId, PaywiseSettings.Key.triggerSetupConfirmed,
                PaywiseSettings.Key.backTapPromptDeclined, PaywiseSettings.Key.backTapPromptReoffered,
            ] {
                settings.defaults.removeObject(forKey: key)
            }
            deps.checkStore.removeAll()
            do {
                let context = ModelContext(try deps.purchases.store().modelContainer)
                try context.delete(model: Purchase.self)
                try context.save()
            } catch {
                Self.log.error("-resetState couldn't clear purchases: \(String(describing: error), privacy: .public)")
            }
        }
        if skipOnboarding {
            deps.walletStore.save(.demo3Card)
            settings.onboarded = true
        }
        if let dateOverride {
            settings.dateOverrideValue = dateOverride
            settings.dateOverrideEnabled = true
        }
    }
}
