import SwiftUI

/// First-launch onboarding (SPEC §5.1, §10, §15.7 steps 11 and 14): consent → "Add my cards" → a real first result
/// on the bundled $1,499 laptop checkout → "Make it one press" (skippable). Follows the system appearance, except the
/// result card, a paying moment, which is light (docs/design.md §1). Can be run again from Settings.
struct OnboardingView: View {
    enum Step: Hashable {
        case cards, firstResult, trigger
    }

    let deps: AppDependencies
    let finish: () -> Void
    @State private var path: [Step] = []
    @State private var draft: WalletDraft

    init(deps: AppDependencies, startingWallet: Wallet?, finish: @escaping () -> Void) {
        self.deps = deps
        self.finish = finish
        _draft = State(initialValue: startingWallet.map(WalletDraft.init) ?? WalletDraft())
    }

    var body: some View {
        NavigationStack(path: $path) {
            ConsentStep { path.append(.cards) }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .cards:
                        CardsStep(draft: $draft, catalog: deps.catalog) {
                            deps.walletStore.save(draft.wallet(order: deps.catalog.cards.map(\.id)))
                            path.append(.firstResult)
                        }
                    case .firstResult:
                        FirstResultStep(deps: deps) { path.append(.trigger) }
                    case .trigger:
                        TriggerSetupView(mode: .onboarding, settings: deps.settings, finish: finish)
                    }
                }
        }
    }
}

// MARK: Consent

/// §10: the onboarding privacy copy (three lines) and the consent paragraph, which names Anthropic and its retention.
private struct ConsentStep: View {
    let next: () -> Void

    private static let symbols = ["hand.tap", "eye.slash", "paperplane"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    PaywiseMark(size: 44)
                    Text("Paywise")
                        .font(.app(34, .bold))
                        .tracking(-0.8)
                        .accessibilityAddTraits(.isHeader)
                    Text("The perks buried in your card's fine print — at the moment you pay.")
                        .font(.app(17))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(PrivacyCopy.onboardingLines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: Self.symbols[index])
                                .font(.app(20))
                                .foregroundStyle(Color("accent"))
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            Text(line)
                                .font(.app(17, .medium))
                                .tracking(-0.3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityIdentifier("onboarding.privacy.\(index)")
                    }
                }

                Text(PrivacyCopy.consent)
                    .font(.app(13))
                    // "$1,499.00": money in tabular figures (design.md §3).
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboarding.consent")

                Button("Continue", action: next)
                    .buttonStyle(AppButtonStyle(prominent: true))
                    .accessibilityIdentifier("onboarding.consent.continue")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: Cards

/// §5.1 step 1 "Add my cards": tiles from the bundled cards.json, the default, an optional last 4, or the demo wallet.
private struct CardsStep: View {
    @Binding var draft: WalletDraft
    let catalog: CardCatalog
    let next: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Pick your cards and set your default.")
                    .font(.app(15))
                    .foregroundStyle(.secondary)
                WalletEditor(draft: $draft, catalog: catalog)
                VStack(spacing: 10) {
                    Button("Continue", action: next)
                        .buttonStyle(AppButtonStyle(prominent: true))
                        .disabled(!draft.isValid)
                        .accessibilityIdentifier("onboarding.cards.continue")
                    Button("Use demo wallet") {
                        draft = WalletDraft(.demo3Card)
                    }
                    .buttonStyle(AppButtonStyle(prominent: false))
                    .accessibilityIdentifier("onboarding.cards.demoWallet")
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Add my cards")
    }
}

// MARK: First result

/// §5.1 step 2: the real check (on-device reading, `/v1/check`, replay, `CheckRecord`) on the bundled $1,499 laptop
/// checkout, with the wallet just set up.
private struct FirstResultStep: View {
    @State private var check: InAppCheck
    let next: () -> Void

    init(deps: AppDependencies, next: @escaping () -> Void) {
        _check = State(initialValue: InAppCheck(deps: deps))
        self.next = next
    }

    static func sampleScreenshot(bundle: Bundle = .main) -> Data? {
        bundle.url(forResource: "laptop-checkout", withExtension: "png").flatMap { try? Data(contentsOf: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("A sample $1,499 laptop checkout from Northbay Electronics, checked against your own cards.")
                    .font(.app(15))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                InAppResultCard(check: check, catalog: check.deps.catalog, showsSaveButton: false)
                if let record = check.record, record.parsedResponse.decision?.kind == .error {
                    Button("Check again") { Task { await run() } }
                        .buttonStyle(AppButtonStyle(prominent: false))
                        .accessibilityIdentifier("onboarding.firstResult.retry")
                }
                Button("Continue", action: next)
                    .buttonStyle(AppButtonStyle(prominent: true))
                    .disabled(check.isChecking)
                    .accessibilityIdentifier("onboarding.firstResult.continue")
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Your first result")
        .task {
            if check.phase == .idle { await run() }
        }
    }

    private func run() async {
        guard let data = Self.sampleScreenshot() else { return }
        await check.run(imageData: data)
    }
}
