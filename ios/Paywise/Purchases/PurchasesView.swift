import SwiftUI

/// Where the Purchases tab's stack can go: a purchase, its claim input, the HTML verdict.
enum PurchaseRoute: Hashable {
    case detail(String)
    case claim(String)
    case verdict(CoverageRequest)
}

/// The Purchases tab (SPEC §5.4, §9.1, §15.7 step 12a). Always dark (docs/design.md §1: the "14 months later"
/// screens), grouped card rows (§4). Each row reads exactly the §15.7 step 12a line.
struct PurchasesView: View {
    @Environment(PurchasesModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Binding var path: [PurchaseRoute]
    @State private var pendingDelete: PurchaseSnapshot?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.loaded && model.purchases.isEmpty {
                        empty
                    } else if !model.purchases.isEmpty {
                        list
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Purchases")
            .navigationDestination(for: PurchaseRoute.self) { route in
                destination(route)
            }
        }
        .task { await model.reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.reload() } }
        }
        .confirmationDialog(
            "Delete this purchase?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { purchase in
            Button("Delete purchase", role: .destructive) {
                Task { await model.delete(id: purchase.id) }
            }
        } message: { purchase in
            Text("\(purchase.shortItemName) and its coverage dates are removed from this iPhone.")
        }
    }

    private var list: some View {
        let wallet = model.wallet
        let catalog = model.deps.catalog
        let today = Day.today(settings: model.deps.settings, now: model.deps.now(), timeZone: model.deps.timeZone)
        return GroupedCard(padding: 0) {
            ForEach(Array(model.purchases.enumerated()), id: \.element.id) { index, purchase in
                if index > 0 {
                    // Separator inset to the text (design.md §4: 80 pt on rows with a thumbnail).
                    Divider().padding(.leading, 74)
                }
                let line = PurchaseText.line(purchase, wallet: wallet, catalog: catalog, today: today)
                NavigationLink(value: PurchaseRoute.detail(purchase.id)) {
                    PurchaseRow(purchase: purchase, line: line)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(line)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("purchase.row")
                .contextMenu {
                    Button("Delete purchase", systemImage: "trash", role: .destructive) {
                        pendingDelete = purchase
                    }
                }
            }
        }
    }

    private var empty: some View {
        GroupedCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("No purchases yet")
                    .font(.app(17, .semibold))
                    .tracking(-0.3)
                Text("Tap Paying with … on a result and the purchase is saved here with its coverage dates.")
                    .font(.app(14))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("purchases.empty")
    }

    @ViewBuilder private func destination(_ route: PurchaseRoute) -> some View {
        switch route {
        case .detail(let id):
            PurchaseDetailView(purchaseId: id, path: $path)
        case .claim(let id):
            if let purchase = model.purchase(id: id) {
                ClaimInputView(purchase: purchase, deps: model.deps, wallet: model.wallet, path: $path)
            }
        case .verdict(let request):
            VerdictView(request: request, api: model.deps.coverage)
        }
    }
}

/// One purchase row: an icon tile and the §15.7 step 12a line (the item name in row-title type, the rest as meta).
private struct PurchaseRow: View {
    let purchase: PurchaseSnapshot
    let line: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: PurchaseText.symbol(category: purchase.category))
                .font(.app(20, .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            Text(styled)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.app(13, .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    /// The same characters as `line`; only the type changes after the item name.
    private var styled: AttributedString {
        let name = purchase.shortItemName
        guard line.hasPrefix(name) else { return AttributedString(line) }
        var title = AttributedString(name)
        title.font = .app(17, .semibold)
        title.foregroundColor = .primary
        var meta = AttributedString(String(line.dropFirst(name.count)))
        meta.font = .app(14)
        meta.foregroundColor = .secondary
        return title + meta
    }
}

/// One purchase (SPEC §5.4): item, price, card, coverage lines, [I bought this] and [Something happened]. Dark.
struct PurchaseDetailView: View {
    @Environment(PurchasesModel.self) private var model
    let purchaseId: String
    @Binding var path: [PurchaseRoute]

    var body: some View {
        ScrollView {
            if let purchase = model.purchase(id: purchaseId) {
                content(purchase)
                    .padding(16)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ purchase: PurchaseSnapshot) -> some View {
        let catalog = model.deps.catalog
        let wallet = model.wallet
        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(purchase.item)
                    .font(.app(28, .bold))
                    .tracking(-0.6)
                    .accessibilityIdentifier("purchase.detail.title")
                Text(PurchaseText.price(purchase.priceUsd))
                    .font(.app(20, .semibold))
                    .monospacedDigit()
                    .accessibilityIdentifier("purchase.detail.price")
                Text(meta(purchase))
                    .font(.app(14))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            GroupedCard(padding: 0) {
                HStack(spacing: 14) {
                    CardThumb(cardId: purchase.cardId, catalog: catalog)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(PurchaseText.card(purchase.cardId, wallet: wallet, catalog: catalog))
                            .font(.app(17, .semibold))
                            .tracking(-0.3)
                            .monospacedDigit()
                        StatusLabel(status: purchase.status)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("purchase.detail.card")

                Divider().padding(.leading, 16)

                VStack(alignment: .leading, spacing: 10) {
                    let today = Day.today(settings: model.deps.settings, now: model.deps.now(), timeZone: model.deps.timeZone)
                    let lines = PurchaseText.coverageLines(purchase, today: today)
                    if lines.isEmpty {
                        Text("No card coverage is saved for this purchase.")
                            .font(.app(15))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(lines, id: \.self) { line in
                        // Ended cover is greyed with a slashed shield, so it never reads as live cover (the words
                        // say "ended" too, so the state doesn't rest on color).
                        Label {
                            Text(line.text)
                                .font(.app(15, .medium))
                                .monospacedDigit()
                                .foregroundStyle(line.ended ? .secondary : .primary)
                        } icon: {
                            Image(systemName: line.ended ? "shield.slash" : "checkmark.shield.fill")
                                .foregroundStyle(line.ended ? Color.secondary : Color.green)
                        }
                    }
                    if let footnote = PurchaseText.warrantyFootnote(purchase) {
                        Text(footnote + (purchase.status == .planned ? " Planned: confirm after you pay." : ""))
                            .font(.app(13))
                            .foregroundStyle(.secondary)
                    } else if purchase.status == .planned {
                        Text("Planned: confirm after you pay.")
                            .font(.app(13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("purchase.detail.coverage")
            }

            VStack(spacing: 10) {
                if purchase.status == .planned {
                    Button("I bought this") {
                        Task { await model.confirm(id: purchase.id) }
                    }
                    .buttonStyle(AppButtonStyle(prominent: true))
                    .accessibilityIdentifier("purchase.boughtThis")
                }
                Button("Something happened") {
                    path.append(.claim(purchase.id))
                }
                .buttonStyle(AppButtonStyle(prominent: purchase.status == .confirmed))
                .accessibilityIdentifier("purchase.somethingHappened")
            }
        }
    }

    private func meta(_ purchase: PurchaseSnapshot) -> String {
        let bought = Day.medium(purchase.purchaseDate).map { "bought \($0)" }
        return [purchase.merchant, bought].compactMap { $0 }.joined(separator: " · ")
    }
}

/// "Planned" / "Confirmed" with a symbol, so the state never rests on color alone.
private struct StatusLabel: View {
    let status: Purchase.Status

    var body: some View {
        Label {
            Text(PurchaseText.status(status))
        } icon: {
            Image(systemName: status == .confirmed ? "checkmark.circle.fill" : "clock")
        }
        .font(.app(14))
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("purchase.detail.status")
    }
}
