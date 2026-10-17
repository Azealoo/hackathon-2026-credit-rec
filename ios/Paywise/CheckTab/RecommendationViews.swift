import SwiftUI

struct RecommendationPreferencesView: View {
    let settings: PaywiseSettings
    @State private var preferences: RecommendationPreferences
    @State private var budget: String
    @Environment(\.dismiss) private var dismiss

    init(settings: PaywiseSettings) {
        self.settings = settings
        let saved = settings.recommendationPreferences
        _preferences = State(initialValue: saved)
        _budget = State(initialValue: saved.cashSacrificeBudgetMinor.map(RecommendationMoney.text) ?? "")
    }

    var body: some View {
        Form {
            Section("What matters most?") {
                Picker("Priority", selection: $preferences.mode) {
                    Text("Savings").tag("cash_first")
                    Text("Protection").tag("protection_target")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("recommendation.priority")
                Text(preferences.mode == "cash_first"
                     ? "Compare rewards after fees and interest."
                     : "Look for a card that meets your protection target, within your rewards budget.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Used by Compare with my preferences in your checkout result.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if preferences.mode == "protection_target" {
                Section {
                    Picker("Protection target", selection: $preferences.benefitType) {
                        Text("At least one extra warranty year").tag("extended_warranty")
                        Text("Damage or theft protection").tag("purchase_damage_theft")
                        Text("Return protection").tag("return_protection")
                    }
                    .accessibilityIdentifier("recommendation.target")
                    TextField("Maximum rewards to give up (USD)", text: $budget)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("recommendation.budget")
                    if !budget.isEmpty && RecommendationMoney.minor(budget) == nil {
                        Text("Enter a nonnegative USD amount with at most two decimal places.")
                            .font(.footnote).foregroundStyle(.red)
                    }
                } header: { Text("Protection and budget") }
                footer: { Text("Leave the budget empty to ask before giving up any rewards. Card eligibility still needs verification; return protection is not a refund guarantee.") }
            }
            Section {
                Toggle("Allow protection tradeoffs", isOn: $preferences.allowLossOfExistingProtection)
                    .accessibilityIdentifier("recommendation.allowTradeoffs")
            } footer: {
                Text("Off by default. Turning this on allows cash recommendations when protection may change or cannot be fully compared. It does not confirm eligibility for a protection target.")
            }
        }
        .navigationTitle("Card preferences")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    preferences.cashSacrificeBudgetMinor = RecommendationMoney.minor(budget)
                    settings.recommendationPreferences = preferences
                    dismiss()
                }
                .disabled(preferences.mode == "protection_target" && !budget.isEmpty && RecommendationMoney.minor(budget) == nil)
                .accessibilityIdentifier("recommendation.savePreferences")
            }
        }
    }
}

/// A deliberate comparison from the current checkout. No account facts are inferred from OCR.
struct CheckoutRecommendationView: View {
    let deps: AppDependencies
    let record: CheckRecord?
    @State private var amount: String
    @State private var products: [RecommendationCatalog.Product] = []
    @State private var cards: [RecommendationCardDraft] = []
    @State private var defaultId = ""
    @State private var paymentPath = "direct_card"
    @State private var amountConfirmed = false
    @State private var usableConfirmed = false
    @State private var interestFreeConfirmed = false
    @State private var noCheckoutFeesConfirmed = false
    @State private var preferences: RecommendationPreferences
    @State private var showingPreferences = false
    @State private var result: RecommendationResult?
    @State private var errorMessage: String?
    @State private var loading = false
    @State private var catalogLoaded = false
    @State private var omittedWalletNames: [String] = []

    init(deps: AppDependencies, record: CheckRecord?) {
        self.deps = deps
        self.record = record
        let total = record?.replayed == false ? record?.parsedResponse.cart?.totalUsd : nil
        _amount = State(initialValue: total.map { NSDecimalNumber(value: $0).stringValue } ?? "")
        _preferences = State(initialValue: deps.settings.recommendationPreferences)
    }

    private var chargeDate: String { Day.today(settings: deps.settings, now: deps.now(), timeZone: deps.timeZone) }
    private var service: RecommendationService { .init(api: deps.api) }
    private var supportedCurrency: Bool {
        record?.parsedResponse.cart?.currency.map { $0 == "USD" } ?? true
    }
    private var request: RecommendationRequest? {
        RecommendationRequest.build(requestId: "comparison-request", amount: amount, chargeDate: chargeDate,
            cards: cards, defaultId: defaultId, path: paymentPath, usableConfirmed: usableConfirmed,
            interestFreeConfirmed: interestFreeConfirmed, noCheckoutFeesConfirmed: noCheckoutFeesConfirmed,
            preferences: preferences)
    }

    var body: some View {
        Form {
            if loading && !catalogLoaded {
                Section { ProgressView("Loading cards…") }
            }
            Section {
                Button { showingPreferences = true } label: {
                    LabeledContent("Your priority", value: preferences.title)
                }
                .accessibilityIdentifier("comparison.preferences")
                if preferences.mode == "protection_target" {
                    Text(preferences.cashSacrificeBudgetMinor.map { "Give up at most \(RecommendationMoney.dollars($0)) in rewards" }
                         ?? "Ask before giving up rewards")
                        .font(.footnote)
                }
            }
            Section("This checkout") {
                TextField("Order total (USD)", text: $amount).keyboardType(.decimalPad)
                    .accessibilityIdentifier("comparison.amount")
                Text("Purchase date: \(chargeDate)").font(.footnote).foregroundStyle(.secondary)
                Picker("Payment method", selection: $paymentPath) {
                    Text("Enter card directly").tag("direct_card")
                    Text("Apple Pay").tag("apple_pay")
                }
                Toggle("I confirm this is the order total in USD", isOn: $amountConfirmed)
                    .accessibilityIdentifier("comparison.confirmAmount")
                if !supportedCurrency {
                    Text("This checkout is not in USD. Currency conversion is not available in this comparison.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if catalogLoaded {
                cardSection
                confirmationSection
                Section {
                    Button {
                        Task { await compare() }
                    } label: {
                        if loading { ProgressView() } else { Text("Compare selected cards") }
                    }
                    .disabled(!supportedCurrency || !amountConfirmed || request == nil || loading)
                    .accessibilityIdentifier("comparison.submit")
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.secondary) }
                    .accessibilityIdentifier("comparison.error")
            }
            if let result { resultSection(result) }
            if !catalogLoaded && !loading {
                Button("Load available cards") { Task { await loadCatalog() } }
            }
        }
        .disabled(loading)
        .navigationTitle("Compare my cards")
        .task { if !catalogLoaded { await loadCatalog() } }
        .sheet(isPresented: $showingPreferences, onDismiss: {
            preferences = deps.settings.recommendationPreferences
            result = nil
        }) {
            NavigationStack { RecommendationPreferencesView(settings: deps.settings) }
        }
        .onChange(of: amount) { _, _ in amountConfirmed = false; noCheckoutFeesConfirmed = false; invalidate() }
        .onChange(of: cards) { old, updated in
            if old.map(\.id) != updated.map(\.id) { resetConfirmations() }
            var revised = updated
            for index in revised.indices {
                if let previous = old.first(where: { $0.id == revised[index].id }),
                   previous.network != revised[index].network {
                    revised[index].termsConfirmed = false
                    revised[index].category = "unknown"
                    revised[index].foreignFeeApplies = "unknown"
                    resetConfirmations()
                }
            }
            if revised != updated { cards = revised }
            invalidate()
        }
        .onChange(of: defaultId) { _, _ in invalidate() }
        .onChange(of: paymentPath) { _, _ in
            resetConfirmations()
            for index in cards.indices {
                cards[index].termsConfirmed = false
                cards[index].category = "unknown"
                cards[index].foreignFeeApplies = "unknown"
            }
            invalidate()
        }
        .onChange(of: amountConfirmed) { _, _ in invalidate() }
        .onChange(of: usableConfirmed) { _, _ in invalidate() }
        .onChange(of: interestFreeConfirmed) { _, _ in invalidate() }
        .onChange(of: noCheckoutFeesConfirmed) { _, _ in invalidate() }
    }

    private var cardSection: some View {
        Section {
            Picker("Compare against", selection: $defaultId) {
                Text("Choose a card").tag("")
                ForEach(cards) { card in Text(name(card.productId)).tag(card.id) }
            }
            ForEach($cards) { $card in
                DisclosureGroup(name(card.productId)) { accountFields($card) }
            }
            .onDelete { offsets in
                cards.remove(atOffsets: offsets)
                if !cards.contains(where: { $0.id == defaultId }) { defaultId = "" }
            }
            Menu("Add a card I already have") {
                ForEach(products) { product in
                    Button(product.name) {
                        cards.append(.init(id: "card-" + RequestID.make().lowercased(), productId: product.id))
                    }
                }
            }
            .disabled(cards.count >= 30)
            if !omittedWalletNames.isEmpty {
                Text("Not included from your wallet: " + omittedWalletNames.joined(separator: ", "))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } header: { Text("Cards in this comparison") }
        footer: { Text("Only the selected cards are compared. Swipe to remove a card. Account confirmations and credit amounts are used for this comparison and are not saved.") }
    }

    @ViewBuilder private func accountFields(_ binding: Binding<RecommendationCardDraft>) -> some View {
        let card = binding.wrappedValue
        Picker("Card network", selection: binding.network) {
            Text("Not sure").tag("unknown")
            Text("Visa").tag("visa")
            Text("Mastercard").tag("mastercard")
            Text("American Express").tag("amex")
            Text("Discover").tag("discover")
        }
        TextField("Available credit (USD)", text: binding.availableCredit).keyboardType(.decimalPad)
        if let product = products.first(where: { $0.id == card.productId }) {
            if let url = product.termsUrls.first.flatMap(URL.init(string:)) { Link("Review official card terms", destination: url) }
            Text("Terms reviewed \(product.observedAt)").font(.caption).foregroundStyle(.secondary)
            Toggle("These terms apply to my account and this eligible purchase", isOn: binding.termsConfirmed)
            Picker("Reward category under these terms", selection: binding.category) {
                Text("Not confirmed").tag("unknown")
                Text("No category bonus applies").tag("ordinary_merchandise")
                ForEach(product.categoryOptions, id: \.self) { category in
                    Text(category.replacingOccurrences(of: "_", with: " ").capitalized).tag(category)
                }
            }
            if !product.membershipBonusOptionsBps.isEmpty {
                Picker("Membership rewards bonus", selection: binding.membershipBonusBps) {
                    Text("Not confirmed").tag(Int?.none)
                    ForEach(product.membershipBonusOptionsBps, id: \.self) { bps in
                        Text("\(bps / 100)%").tag(Optional(bps))
                    }
                }
            }
        }
        Picker("Foreign transaction fee applies", selection: binding.foreignFeeApplies) {
            Text("Not sure").tag("unknown")
            Text("No").tag("no")
            Text("Yes").tag("yes")
        }
        if card.productId == "citi-double-cash" {
            Toggle("Eligible payment and Purchase Tracker confirmed", isOn: binding.paymentTrackerConfirmed)
        }
    }

    private var confirmationSection: some View {
        Section {
            Toggle("All selected cards can be used for this order and payment method", isOn: $usableConfirmed)
            Toggle("All selected cards will be paid in full and have an active purchase grace period", isOn: $interestFreeConfirmed)
            Toggle("No additional checkout fee applies to any selected card", isOn: $noCheckoutFeesConfirmed)
        } header: { Text("Confirm what you know") }
        footer: { Text("Leave uncertain facts unconfirmed. We will show the missing information rather than assume no fees or interest. Category caps and unresolved policies can still limit the comparison.") }
    }

    @ViewBuilder private func resultSection(_ value: RecommendationResult) -> some View {
        Section {
            Text(value.title).font(.headline)
            if let chosen = value.selected, let card = cards.first(where: { $0.id == chosen.walletCardId }) {
                Text(name(card.productId)).font(.title3.weight(.semibold))
            }
            Text(value.explanation)
            if let delta = value.cashDelta { Text("Net rewards change: \(delta.text)") }
            ForEach(value.options, id: \.walletCardId) { option in
                VStack(alignment: .leading, spacing: 4) {
                    Text(name(option.productId)).font(.subheadline.weight(.semibold))
                    if let net = option.net { Text("Estimated eventual net rewards: \(net.text)") }
                    else if let reward = option.reward { Text("Estimated purchase rewards before costs: \(reward.text)") }
                    if option.availability == "ineligible" { Text("Not available for this purchase") }
                    let missing = Array(Set(option.missingFields.map(RecommendationResult.missingLabel))).sorted()
                    ForEach(missing, id: \.self) { Text("Confirm: \($0)").font(.caption).foregroundStyle(.secondary) }
                }
            }
            Text("Among selected cards only. Ordinary rewards estimates exclude personalized offers and welcome bonuses. Protection and refunds are not guaranteed.")
                .font(.footnote).foregroundStyle(.secondary)
        } header: { Text("Comparison result") }
        .accessibilityIdentifier("comparison.result")
    }

    private func name(_ productId: String) -> String { products.first { $0.id == productId }?.name ?? "Card" }
    private func invalidate() { result = nil; errorMessage = nil }
    private func resetConfirmations() {
        usableConfirmed = false
        interestFreeConfirmed = false
        noCheckoutFeesConfirmed = false
    }

    @MainActor private func loadCatalog() async {
        loading = true
        defer { loading = false }
        do {
            products = try await service.catalog().products
            let wallet = deps.walletStore.load()
            for existing in wallet.cards {
                let id = RecommendationCardDraft.productId(forLegacyId: existing.cardId)
                if products.contains(where: { $0.id == id }) {
                    cards.append(.init(id: "card-\(cards.count)", productId: id,
                                       network: deps.catalog.card(existing.cardId)?.network?.rawValue ?? "unknown"))
                    if existing.isDefault { defaultId = cards.last?.id ?? "" }
                } else {
                    omittedWalletNames.append(deps.catalog.shortName(existing.cardId) ?? "Other wallet card")
                }
            }
            catalogLoaded = true
        } catch { show(error) }
    }

    @MainActor private func compare() async {
        guard var request else { return }
        request.requestId = "compare-" + RequestID.make()
        result = nil
        errorMessage = nil
        loading = true
        defer { loading = false }
        do { result = try await service.compare(request) }
        catch { show(error) }
    }

    @MainActor private func show(_ error: Error) {
        switch error as? RecommendationService.Failure {
        case .unavailable: errorMessage = "Card comparison is not available yet. Please try again later."
        case .privacy: errorMessage = "This comparison could not be sent. Check the amounts and try again."
        case .offline: errorMessage = "Could not connect. Try the comparison again."
        default: errorMessage = "Could not complete this comparison. Review your entries and try again."
        }
    }
}
