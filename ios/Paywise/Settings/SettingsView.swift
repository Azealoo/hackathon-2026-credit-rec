import ActivityKit
import SwiftUI

/// Settings (SPEC §9.1, §10, R5): the wallet, how results appear, "Pretend today is…", the setup screens, and the
/// privacy copy. Follows the system appearance.
struct SettingsView: View {
    let app: AppModel

    @AppStorage(PaywiseSettings.Key.snippetMode, store: PaywiseSettings.appGroup.defaults)
    private var snippetMode = SnippetMode.snippet.rawValue
    @AppStorage(PaywiseSettings.Key.silentAlerts, store: PaywiseSettings.appGroup.defaults)
    private var silentAlerts = true
    @AppStorage(PaywiseSettings.Key.replayEnabled, store: PaywiseSettings.appGroup.defaults)
    private var replayEnabled = true
    @AppStorage(PaywiseSettings.Key.dateOverrideEnabled, store: PaywiseSettings.appGroup.defaults)
    private var dateOverrideEnabled = false
    @AppStorage(PaywiseSettings.Key.dateOverride, store: PaywiseSettings.appGroup.defaults)
    private var dateOverride = PaywiseSettings.defaultDateOverride
    @State private var wallet: Wallet?

    #if DEBUG
    @State private var debugStatus = ""
    #endif

    private var deps: AppDependencies { app.deps }

    var body: some View {
        NavigationStack {
            Form {
                Section("Cards") {
                    NavigationLink {
                        WalletSettingsView(deps: deps)
                    } label: {
                        WalletSummary(wallet: wallet ?? deps.walletStore.load(), catalog: deps.catalog)
                    }
                    .accessibilityIdentifier("settings.wallet")
                }

                Section {
                    // R5: the App Group "snippetMode" keys snippet / confirm / island.
                    Picker("Switch results", selection: $snippetMode) {
                        Text("Snippet with a Paying with button").tag(SnippetMode.snippet.rawValue)
                        Text("System confirm prompt").tag(SnippetMode.confirm.rawValue)
                        Text("Island alert, held 8 s").tag(SnippetMode.island.rawValue)
                    }
                    .pickerStyle(.inline)
                    .accessibilityIdentifier("settings.snippetMode")
                    Toggle("Silent island alerts", isOn: $silentAlerts)
                        .accessibilityIdentifier("settings.silentAlerts")
                    Toggle("Replay when offline", isOn: $replayEnabled)
                        .accessibilityIdentifier("settings.replay")
                } header: {
                    Text("Results")
                } footer: {
                    Text("Use the island alert if results don't appear over other apps; save those purchases later with I bought this. A replayed result is always labelled.")
                }

                Section {
                    Toggle("Pretend today is…", isOn: $dateOverrideEnabled)
                        .accessibilityIdentifier("settings.dateOverride.toggle")
                    if dateOverrideEnabled {
                        DatePicker("Today", selection: overrideDate, displayedComponents: .date)
                            .accessibilityIdentifier("settings.dateOverride.date")
                    }
                } header: {
                    Text("Demo")
                } footer: {
                    Text("For the \"14 months later\" claim demo. Checks and claims use this date instead of today's.")
                }

                Section {
                    NavigationLink("What we sent") {
                        SentListView(checkStore: deps.checkStore, catalog: deps.catalog)
                    }
                    .accessibilityIdentifier("settings.whatWeSent")
                    NavigationLink("Make it one press") {
                        TriggerSetupView(mode: .standalone, settings: deps.settings) {}
                    }
                    .accessibilityIdentifier("settings.trigger")
                    Button("Run setup again") { app.rerunOnboarding() }
                        .accessibilityIdentifier("settings.rerunOnboarding")
                }

                Section("Privacy") {
                    Text(PrivacyCopy.retention)
                        .font(.footnote)
                        .accessibilityIdentifier("settings.retention")
                    Text(PrivacyCopy.disclaimer(catalog: deps.catalog))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.disclaimer")
                }

                #if DEBUG
                DebugLiveActivitySection(status: $debugStatus)
                #endif
            }
            .navigationTitle("Settings")
            .onAppear { wallet = deps.walletStore.load() }
        }
    }

    private var overrideDate: Binding<Date> {
        Binding(
            get: { Day.date(dateOverride) ?? Day.date(PaywiseSettings.defaultDateOverride) ?? .now },
            set: { dateOverride = Day.string($0) }
        )
    }
}

private struct WalletSummary: View {
    let wallet: Wallet
    let catalog: CardCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Your cards")
            Text(wallet.cards.map { PurchaseText.card($0.cardId, wallet: wallet, catalog: catalog) + ($0.isDefault ? " (default)" : "") }
                .joined(separator: ", "))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

/// Edit the wallet: the onboarding tiles, the default and last 4. [Save] writes it to the App Group, where every
/// check (in the app or from a press) reads it.
struct WalletSettingsView: View {
    let deps: AppDependencies
    @State private var draft: WalletDraft
    @State private var saved: WalletDraft

    init(deps: AppDependencies) {
        self.deps = deps
        let current = WalletDraft(deps.walletStore.load())
        _draft = State(initialValue: current)
        _saved = State(initialValue: current)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WalletEditor(draft: $draft, catalog: deps.catalog)
                Button("Use demo wallet") { draft = WalletDraft(.demo3Card) }
                    .buttonStyle(AppButtonStyle(prominent: false))
                    .accessibilityIdentifier("wallet.demoWallet")
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Your cards")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    deps.walletStore.save(draft.wallet(order: deps.catalog.cards.map(\.id)))
                    saved = draft
                }
                .disabled(!draft.isValid || draft == saved)
                .accessibilityIdentifier("wallet.save")
            }
        }
    }
}

#if DEBUG
/// Debug-only: start and end a sample *Checking* Live Activity, or any demo state, to check the island on a phone.
struct DebugLiveActivitySection: View {
    @Binding var status: String

    var body: some View {
        Section {
            Button("Start sample Live Activity") {
                Task { status = await SampleActivity.start() }
            }
            Menu("Start demo state") {
                ForEach(DemoActivity.allCases, id: \.self) { demo in
                    Button(demo.rawValue) {
                        Task { status = await DemoActivity.run(.start(demo)) }
                    }
                }
            }
            Button("End Live Activity", role: .destructive) {
                Task {
                    await SampleActivity.endAll()
                    status = "Ended all Paywise activities"
                }
            }
            if !status.isEmpty {
                Text(status)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Debug")
        } footer: {
            Text("Live Activities enabled: \(ActivityAuthorizationInfo().areActivitiesEnabled ? "yes" : "no")")
        }
    }
}
#endif
