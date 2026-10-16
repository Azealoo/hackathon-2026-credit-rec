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
                    .environment(\.colorScheme, .light)
            }
            .accessibilityIdentifier("tab.check")
            Tab("Purchases", systemImage: "bag", value: AppModel.Tab.purchases) {
                PurchasesView(path: $app.purchasePath)
                    .environment(\.colorScheme, .dark)
            }
            .accessibilityIdentifier("tab.purchases")
            Tab("Settings", systemImage: "gearshape", value: AppModel.Tab.settings) {
                SettingsView(app: app)
            }
            .accessibilityIdentifier("tab.settings")
        }
        .onChange(of: app.tab) { _, tab in
            // A purchase saved from the Check tab (or a snippet) shows as soon as Purchases opens.
            if tab == .purchases { Task { await app.purchases.reload() } }
        }
    }
}

#Preview {
    ContentView()
}
