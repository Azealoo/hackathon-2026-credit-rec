import SwiftUI

/// "What we sent" (SPEC §10, §15.7 step 10): every check from the last 24 h, newest first, with the exact payload that
/// left the phone (`CheckRecord.sentPayload`): the redacted text (`screen.ocrText`), then every other field as sent
/// (`CheckRecord.sentFields`), in monospaced type. Replayed results say so.
struct SentListView: View {
    let checkStore: CheckStore
    let catalog: CardCatalog
    @State private var records: [CheckRecord] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Cards sent as product names only. No screenshot, no last 4.")
                    .font(.app(14))
                    .foregroundStyle(.secondary)
                if loaded && records.isEmpty {
                    GroupedCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nothing sent yet")
                                .font(.app(17, .semibold))
                            Text("Each check shows here for 24 hours, exactly as it left your iPhone.")
                                .font(.app(14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("sent.empty")
                }
                ForEach(records) { record in
                    SentRow(record: record, catalog: catalog)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("What we sent")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("sent.list")
        .task {
            records = checkStore.newestFirst()
            loaded = true
        }
    }
}

private struct SentRow: View {
    let record: CheckRecord
    let catalog: CardCatalog

    var body: some View {
        GroupedCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(SentText.title(record, catalog: catalog))
                        .font(.app(17, .semibold))
                        .tracking(-0.3)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    if record.replayed {
                        // §15.7 step 10: a replayed result is always labelled.
                        Text("replayed")
                            .font(.app(13, .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                            .accessibilityIdentifier("sent.replayed")
                    }
                }
                Text(SentText.time(record))
                    .font(.app(13))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                // The exact payload: the redacted text, then the card IDs, clientDate, redaction kinds and the rest.
                VStack(alignment: .leading, spacing: 10) {
                    Text(record.sentText)
                        .accessibilityIdentifier("sent.text")
                    let fields = record.sentFields
                    if !fields.isEmpty {
                        Text(fields.joined(separator: "\n"))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("sent.fields")
                    }
                }
                .font(.system(.footnote, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sent.row")
    }
}

enum SentText {
    /// "Northbay Electronics · $1,499.00": the merchant and total the server read, else what the phone can find in the
    /// sent text (the replay key's merchant and "Total" line).
    static func title(_ record: CheckRecord, catalog: CardCatalog) -> String {
        let cart = record.parsedResponse.cart
        let text = record.sentText
        let merchantId = catalog.merchantId(in: text)
        let merchant = cart?.merchant?.name
            ?? catalog.merchants.first { $0.id == merchantId }?.names?.first
        let total = cart?.totalUsd ?? ReplayStore.totalCents(in: text).map { Double($0) / 100 }
        let parts = [merchant, total.map(PurchaseText.price)].compactMap { $0 }
        return parts.isEmpty ? "Check" : parts.joined(separator: " · ")
    }

    /// "Today, 2:02 PM" style: the record's own timestamp.
    static func time(_ record: CheckRecord) -> String {
        guard let date = record.createdDate else { return record.createdAt }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

}
