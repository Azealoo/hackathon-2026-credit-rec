import SwiftUI

/// The app's root (SPEC §9.1 app screens): first-launch onboarding, then three tabs — Check, Purchases, Settings.
struct ContentView: View {
    @State private var app: AppModel
    #if DEBUG
    @State private var debugStatus = ""
    #endif

    init(app: AppModel? = nil) {
        _app = State(initialValue: app ?? AppModel())
    }

    var body: some View {
        Group {
            if app.onboarded {
                MainTabs(app: app)
            } else {
                OnboardingView(deps: app.deps, startingWallet: app.onboardingWallet) {
                    app.finishOnboarding()
                }
            }
        }
        .environment(app.purchases)
        // design.md §2: the `accent` asset for every control, never system blue.
        .tint(Color("accent"))
        // docs/design.md §1: light to buy, dark to claim. Applied on the root so the tab bar and navigation bars
        // follow too; nil (Settings, onboarding) follows the system.
        .preferredColorScheme(app.colorScheme)
        .task {
            // §6.2: on app launch, end any leftover activities. The debug hooks run after it in the same task,
            // so the cleanup can't end the activity they start.
            await LiveActivityController.shared.endAll()
            #if DEBUG
            if SampleActivity.autostartRequested {
                debugStatus = await SampleActivity.start()
            }
            // `-demoActivity <state|end>`: a Live Activity state for screenshots (Paywise/Debug/DemoActivity.swift).
            if let command = DemoActivity.command() {
                debugStatus = await DemoActivity.run(command)
            }
            if SetupDemo.simulateDoubleTap {
                await SetupDemo.simulateDoubleTap()
            }
            #endif
        }
    }
}

private struct MainTabs: View {
    @Bindable var app: AppModel

    var body: some View {
        TabView(selection: $app.tab) {
            Tab("Check", systemImage: "viewfinder", value: AppModel.Tab.check) {
                CheckTabView(deps: app.deps)
                    .modifier(dateOverridePill)
                    .environment(\.colorScheme, .light)
            }
            .accessibilityIdentifier("tab.check")
            Tab("Purchases", systemImage: "bag", value: AppModel.Tab.purchases) {
                PurchasesView(path: $app.purchasePath)
                    .modifier(dateOverridePill)
                    .environment(\.colorScheme, .dark)
            }
            .accessibilityIdentifier("tab.purchases")
            Tab("Settings", systemImage: "gearshape", value: AppModel.Tab.settings) {
                SettingsView(app: app)
                    .modifier(dateOverridePill)
            }
            .accessibilityIdentifier("tab.settings")
        }
        .onChange(of: app.tab) { _, tab in
            // A purchase saved from the Check tab (or a snippet) shows as soon as Purchases opens.
            if tab == .purchases { Task { await app.purchases.reload() } }
        }
    }

    /// On each tab's stack, at the bottom: a top inset leaves the stack's navigation bar where it is, under the pill.
    private var dateOverridePill: DateOverridePill.Inset {
        DateOverridePill.Inset(settings: app.deps.settings) { app.tab = .settings }
    }
}

/// While "Pretend today is…" is on, a pill over every tab says so: the override moves claim dates and which cover
/// Purchases shows as ended, and a demo left on it misleads the next run. Tapping it opens Settings to turn it off.
struct DateOverridePill: View {
    let settings: PaywiseSettings
    let openSettings: () -> Void
    // Read only so the pill redraws when Settings changes the override; the words come from `label`.
    @AppStorage private var enabled: Bool
    @AppStorage private var day: String

    init(settings: PaywiseSettings, openSettings: @escaping () -> Void) {
        self.settings = settings
        self.openSettings = openSettings
        _enabled = AppStorage(wrappedValue: false, PaywiseSettings.Key.dateOverrideEnabled, store: settings.defaults)
        _day = AppStorage(
            wrappedValue: PaywiseSettings.defaultDateOverride, PaywiseSettings.Key.dateOverride, store: settings.defaults
        )
    }

    /// "Pretend today: Dec 18, 2027", or nil while the override is off.
    static func label(settings: PaywiseSettings) -> String? {
        settings.dateOverrideDay.flatMap(Day.medium).map { "Pretend today: \($0)" }
    }

    /// The pill as a bottom inset of a tab's navigation stack, just above the tab bar on every screen.
    struct Inset: ViewModifier {
        let settings: PaywiseSettings
        let openSettings: () -> Void

        func body(content: Content) -> some View {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                DateOverridePill(settings: settings, openSettings: openSettings)
            }
        }
    }

    var body: some View {
        if enabled, !day.isEmpty, let label = Self.label(settings: settings) {
            Button(action: openSettings) {
                Label(label, systemImage: "calendar.badge.clock")
                    .font(.app(14, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.yellow, in: Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Settings, where you can turn it off.")
            .accessibilityIdentifier("dateOverride.pill")
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
    }
}

#Preview {
    ContentView()
}
