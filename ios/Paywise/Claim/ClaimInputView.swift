import SwiftUI
import WebKit

/// "Can I claim?" input (SPEC §5.5, §15.7 step 12d). Always dark (docs/design.md §1).
struct ClaimInputView: View {
    @Environment(PurchasesModel.self) private var purchases
    @State private var model: ClaimModel
    @Binding var path: [PurchaseRoute]
    @FocusState private var descriptionFocused: Bool
    @FocusState private var amountFocused: Bool
    @State private var checking = false

    init(purchase: PurchaseSnapshot, deps: AppDependencies, wallet: Wallet, path: Binding<[PurchaseRoute]>) {
        _model = State(initialValue: ClaimModel(purchase: purchase, deps: deps, wallet: wallet))
        _path = path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                paidSection
                wholePriceSection
                warrantySection
                happenedSection
                dateSection
                checkButton
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Can I claim?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    descriptionFocused = false
                    amountFocused = false
                }
            }
        }
    }

    // MARK: 1. Card and date

    private var paidSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(model.paidQuestion)
                .monospacedDigit()
                .accessibilityIdentifier("claim.paid.question")
            ChipFlow {
                ChipButton(title: "Yes", isSelected: model.paid == .yes) {
                    Task { await model.answerYes(purchases) }
                }
                .accessibilityIdentifier("claim.paid.yes")
                ChipButton(title: "No, another card", isSelected: isOtherCard || model.choosingOtherCard) {
                    model.choosingOtherCard = true
                }
                .accessibilityIdentifier("claim.paid.otherCard")
            }
            if model.choosingOtherCard || isOtherCard {
                ChipFlow {
                    ForEach(model.otherCards, id: \.self) { cardId in
                        ChipButton(
                            title: PurchaseText.card(cardId, wallet: model.wallet, catalog: model.deps.catalog),
                            isSelected: model.paid == .otherCard(cardId)
                        ) {
                            model.answerOtherCard(cardId)
                        }
                        .monospacedDigit()
                        .accessibilityIdentifier("claim.otherCard.\(cardId)")
                    }
                }
            }
        }
    }

    private var isOtherCard: Bool {
        if case .otherCard = model.paid { return true }
        return false
    }

    // MARK: 1b. Whole price on the card (the §5.5 payout cap)

    private var wholePriceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Did the whole price go on this card?")
            ChipFlow {
                ForEach(PaidWithAnswer.allCases) { answer in
                    ChipButton(title: answer.label, isSelected: model.paidWith == answer) {
                        model.paidWith = answer
                        if answer != .partial { amountFocused = false }
                    }
                    .accessibilityIdentifier("claim.paidWith.\(answer.rawValue)")
                }
            }
            if model.paidWith == .partial {
                HStack(spacing: 6) {
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField("Amount on the card, if you know it", text: $model.amountOnCardText)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .accessibilityLabel("Amount on the card")
                        .accessibilityIdentifier("claim.paidWith.amount")
                }
                .font(.app(17))
                .monospacedDigit()
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if let hint = model.amountOnCardHint {
                    Label(hint, systemImage: "exclamationmark.triangle.fill")
                        .font(.app(13))
                        .foregroundStyle(.yellow)
                        .monospacedDigit()
                        .accessibilityIdentifier("claim.paidWith.amountHint")
                }
            }
        }
    }

    // MARK: 2. Maker's warranty

    private var warrantySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Maker's warranty:")
            ChipFlow {
                ForEach(WarrantyAnswer.allCases) { answer in
                    ChipButton(title: answer.label, isSelected: model.warranty == answer) {
                        model.warranty = answer
                    }
                    .accessibilityIdentifier("claim.warranty.\(answer.rawValue)")
                }
            }
        }
    }

    // MARK: 3. What happened

    private var happenedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("What happened?")
            TextField("", text: $model.description, axis: .vertical)
                .lineLimit(3...6)
                .font(.app(17))
                .focused($descriptionFocused)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel("What happened?")
                .accessibilityIdentifier("claim.description")
                .onChange(of: model.description) { model.descriptionChanged() }
            ChipFlow {
                ForEach(ClaimCause.allCases) { cause in
                    ChipButton(title: cause.label, isSelected: model.cause == cause) {
                        model.pick(cause)
                    }
                    .accessibilityIdentifier("claim.cause.\(cause.rawValue)")
                }
            }
            if model.classifying {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Reading what you wrote…")
                        .font(.app(13))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("claim.classifying")
            } else if let suggested = model.suggestedCause, model.cause == suggested, !model.userPickedCause {
                Text("Picked from what you wrote. Tap another if it's wrong.")
                    .font(.app(13))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("claim.cause.suggested")
            }
            if model.hasLongNumber {
                Label("Take out long numbers, such as a serial number, then check again.", systemImage: "exclamationmark.triangle.fill")
                    .font(.app(13))
                    .foregroundStyle(.yellow)
                    .accessibilityIdentifier("claim.longNumber")
            }
        }
    }

    // MARK: Date and Check

    private var dateSection: some View {
        DatePicker("When it happened", selection: $model.incidentDate, in: model.incidentRange, displayedComponents: .date)
            .font(.app(17))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityIdentifier("claim.date")
    }

    private var checkButton: some View {
        Button("Check") {
            descriptionFocused = false
            amountFocused = false
            checking = true
            Task {
                if let request = await model.prepareVerdict(purchases) {
                    path.append(.verdict(request))
                }
                checking = false
            }
        }
        .buttonStyle(AppButtonStyle(prominent: true))
        .disabled(!model.canCheck || checking)
        .accessibilityIdentifier("claim.check")
    }
}

/// design.md §3 section title: 20 / bold, −0.4.
private struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.app(20, .bold))
            .tracking(-0.4)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The verdict from `POST /v1/coverage?format=html` in a web view (§5.5). The page is always dark; so is this screen.
struct VerdictView: View {
    @State private var model: VerdictModel

    init(request: CoverageRequest, api: CoverageAPI) {
        _model = State(initialValue: VerdictModel(request: request, api: api))
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Checking your card's terms…")
                        .font(.app(15))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("verdict.loading")
            case .loaded(let html):
                VerdictWebView(html: html, baseURL: model.baseURL)
                    .ignoresSafeArea(edges: .bottom)
            case .failed(let line2):
                VStack(alignment: .leading, spacing: 20) {
                    GroupedCard { CouldntCheckView(line2: line2) }
                        .accessibilityIdentifier("verdict.error")
                    Button("Check again") {
                        Task { await model.load() }
                    }
                    .buttonStyle(AppButtonStyle(prominent: true))
                    .accessibilityIdentifier("verdict.retry")
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
        }
        // Dark (the Purchases tab forces it): the system background is black, like the page.
        .background(Color(.systemBackground))
        .navigationTitle(ItemName.short(model.request.purchase.item))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }
}

/// A `WKWebView` showing the server's HTML. No JavaScript (the page has none), no stored website data; links open
/// in Safari.
struct VerdictWebView: UIViewRepresentable {
    let html: String
    let baseURL: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.overrideUserInterfaceStyle = .dark
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.underPageBackgroundColor = .systemBackground
        webView.navigationDelegate = context.coordinator
        webView.accessibilityIdentifier = "verdict.web"
        webView.loadHTMLString(html, baseURL: baseURL)
        context.coordinator.loadedHTML = html
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard navigationAction.navigationType == .linkActivated else { return .allow }
            if let url = navigationAction.request.url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                await UIApplication.shared.open(url)
            }
            return .cancel
        }
    }
}
