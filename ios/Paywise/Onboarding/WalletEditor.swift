import SwiftUI

/// The wallet being edited in onboarding ("Add my cards", SPEC §5.1 step 1) and Settings: which cards, the default,
/// and an optional last 4 per card (exactly 4 digits; it stays on the phone and is never sent).
struct WalletDraft: Equatable, Sendable {
    var selected: Set<String>
    var defaultId: String?
    var last4: [String: String]

    init(selected: Set<String> = [], defaultId: String? = nil, last4: [String: String] = [:]) {
        self.selected = selected
        self.defaultId = defaultId
        self.last4 = last4
    }

    init(_ wallet: Wallet) {
        selected = Set(wallet.cards.map(\.cardId))
        defaultId = wallet.defaultCardId
        last4 = Dictionary(wallet.cards.compactMap { card in card.last4.map { (card.cardId, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    mutating func toggle(_ cardId: String, order: [String]) {
        if selected.contains(cardId) {
            selected.remove(cardId)
            if defaultId == cardId {
                defaultId = order.first(where: selected.contains)
            }
        } else {
            selected.insert(cardId)
            if defaultId == nil || !selected.contains(defaultId!) {
                defaultId = cardId
            }
        }
    }

    mutating func setDefault(_ cardId: String) {
        guard selected.contains(cardId) else { return }
        defaultId = cardId
    }

    /// Keeps only digits, at most 4.
    mutating func setLast4(_ text: String, for cardId: String) {
        let digits = String(text.filter { $0.isASCII && $0.isNumber }.prefix(4))
        last4[cardId] = digits.isEmpty ? nil : digits
    }

    /// A last 4 is either left empty or exactly 4 digits.
    static func isValidLast4(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return true }
        return text.count == 4 && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    var isValid: Bool {
        !selected.isEmpty && defaultId.map(selected.contains) == true
            && selected.allSatisfy { Self.isValidLast4(last4[$0]) }
    }

    /// The wallet in catalog order (the order breaks cash ties, §7.2), the default flagged.
    func wallet(order: [String]) -> Wallet {
        Wallet(cards: order.filter(selected.contains).map { id in
            Wallet.Card(cardId: id, isDefault: id == defaultId, last4: Self.isValidLast4(last4[id]) ? last4[id] : nil)
        })
    }
}

/// Card tiles from the bundled cards.json (art at the snippet size, design.md §7, and `shortName`), the default, and
/// the optional last 4 for each picked card.
struct WalletEditor: View {
    @Binding var draft: WalletDraft
    let catalog: CardCatalog
    @Environment(\.dynamicTypeSize) private var typeSize

    private var order: [String] { catalog.cards.map(\.id) }

    /// Two tiles a row, one at accessibility sizes. The name sits under the art at the tile's full width, so a
    /// name of one or two words ("Freedom Rise") fits whole and never breaks mid-word (checked at default, XL and
    /// XXL in the screenshot tour).
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(catalog.cards) { card in
                    CardTile(card: card, catalog: catalog, isSelected: draft.selected.contains(card.id)) {
                        draft.toggle(card.id, order: order)
                    }
                }
            }

            if !draft.selected.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Default card and last 4")
                        .font(.app(13, .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    GroupedCard(padding: 0) {
                        let picked = order.filter(draft.selected.contains)
                        ForEach(Array(picked.enumerated()), id: \.element) { index, cardId in
                            if index > 0 { Divider().padding(.leading, 16) }
                            CardSettingsRow(cardId: cardId, draft: $draft, catalog: catalog)
                        }
                    }
                    Text("Last 4 is optional and stays on your phone. It is never sent.")
                        .font(.app(13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct CardTile: View {
    let card: CardCatalog.Card
    let catalog: CardCatalog
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    CardThumb(cardId: card.id, catalog: catalog)
                    Spacer(minLength: 0)
                    // ✓ and the accent border: color is never the only cue (§6.4).
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.app(20))
                        .foregroundStyle(isSelected ? Color("accent") : Color(.tertiaryLabel))
                        .accessibilityHidden(true)
                }
                // Wraps between words only; never truncated.
                Text(card.shortName ?? card.displayName ?? card.id)
                    .font(.app(15, .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Color("accent") : Color.clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(card.shortName ?? card.id)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("wallet.tile.\(card.id)")
    }
}

private struct CardSettingsRow: View {
    let cardId: String
    @Binding var draft: WalletDraft
    let catalog: CardCatalog

    var body: some View {
        let isDefault = draft.defaultId == cardId
        let last4 = draft.last4[cardId] ?? ""
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button {
                    draft.setDefault(cardId)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isDefault ? "largecircle.fill.circle" : "circle")
                            .font(.app(20))
                            .foregroundStyle(isDefault ? Color("accent") : Color(.tertiaryLabel))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(catalog.shortName(cardId) ?? cardId)
                                .font(.app(17))
                                .foregroundStyle(.primary)
                            if isDefault {
                                Text("Default")
                                    .font(.app(13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(catalog.shortName(cardId) ?? cardId), default card")
                .accessibilityAddTraits(isDefault ? .isSelected : [])
                .accessibilityIdentifier("wallet.default.\(cardId)")

                Spacer(minLength: 8)

                HStack(spacing: 2) {
                    Text("••")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("Last 4", text: Binding(
                        get: { draft.last4[cardId] ?? "" },
                        set: { draft.setLast4($0, for: cardId) }
                    ))
                    .keyboardType(.numberPad)
                    .textContentType(.none)
                    .autocorrectionDisabled()
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .accessibilityLabel("Last 4 of \(catalog.shortName(cardId) ?? cardId)")
                    .accessibilityIdentifier("wallet.last4.\(cardId)")
                }
                .font(.app(17))
            }
            if !WalletDraft.isValidLast4(last4) {
                Text("Enter all 4 digits, or leave it empty.")
                    .font(.app(13))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("wallet.last4.error.\(cardId)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
