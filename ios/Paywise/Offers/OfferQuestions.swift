import SwiftUI

/// One-tap questions per wallet card, from the catalog's `confirmQuestion` ("Activated your Q4 5%?") and events
/// ("Is your Discover card in the Capital One app?"). The answers are `OfferRecords` on this phone only (D1); there
/// is no screenshot capture and no model call (D2, D3).
struct OfferQuestion: Identifiable, Equatable, Sendable {
    enum Subject: Equatable, Sendable {
        case offer(id: String)
        case event(id: String)
    }

    var cardId: String
    var subject: Subject
    var text: String
    var detail: String?
    /// An `account_age` offer: after a Yes, ask the opening month (these choices, yyyy-MM).
    var openingMonths: [String]
    /// The offer has a spend cap: after a Yes, the user may say how much of it is used.
    var hasCap: Bool

    var id: String {
        switch subject {
        case .offer(let id): "\(cardId)/offer/\(id)"
        case .event(let id): "\(cardId)/event/\(id)"
        }
    }
}

enum OfferQuestions {
    /// The questions for this wallet today, in wallet order then catalog order: device offers with a question whose
    /// window hasn't ended (and, for activation, whose deadline hasn't passed unanswered), and events from `askFrom`.
    static func questions(
        wallet: Wallet, catalog: CardCatalog, records: OfferRecords, today: String
    ) -> [OfferQuestion] {
        wallet.cards.map(\.cardId).flatMap { cardId -> [OfferQuestion] in
            let offers = catalog.offers.compactMap { offer -> OfferQuestion? in
                guard offer.evaluation == "device", offer.cardIds.contains(cardId),
                      let text = offer.confirmQuestion, offer.window?.endsOn.map({ today <= $0 }) ?? true
                else { return nil }
                let answered = records.state(cardId: cardId, offerId: offer.id) != nil
                let deadlinePassed = offer.requires.contains { $0.kind == "activation" && ($0.deadline.map { today > $0 } ?? false) }
                if deadlinePassed && !answered { return nil }
                let acquisition = offer.requires.first { $0.kind == "acquisition_offer" }
                let asksMonth = offer.requires.contains { $0.kind == "account_age" }
                return OfferQuestion(
                    cardId: cardId, subject: .offer(id: offer.id), text: text, detail: offer.title,
                    openingMonths: asksMonth ? months(from: acquisition?.openedFrom, through: acquisition?.openedThrough) : [],
                    hasCap: offer.limits?.spendCapUsd != nil
                )
            }
            let events = catalog.events.compactMap { event -> OfferQuestion? in
                guard event.cardIds.contains(cardId), let askFrom = event.askFrom, askFrom <= today else { return nil }
                return OfferQuestion(
                    cardId: cardId, subject: .event(id: event.id), text: event.confirmQuestion, detail: event.title,
                    openingMonths: [], hasCap: false
                )
            }
            return offers + events
        }
    }

    /// Stores a one-tap answer. A Yes to an activation question records today as the activation day.
    static func answer(_ answer: OfferAnswer, to question: OfferQuestion, today: String, in store: OfferStore) throws {
        try store.update { records in
            var facts = records.facts(question.cardId)
            switch question.subject {
            case .offer(let id):
                var state = facts.offers[id] ?? OfferState(answer: answer, answeredOn: today)
                state.answer = answer
                state.answeredOn = today
                state.activatedOn = answer == .yes ? (state.activatedOn ?? today) : nil
                facts.offers[id] = state
            case .event(let id):
                facts.events[id] = OfferState(answer: answer, answeredOn: today)
            }
            records.cards[question.cardId] = facts
        }
    }

    static func setOpeningMonth(_ month: String?, cardId: String, in store: OfferStore) throws {
        try store.update { records in
            var facts = records.facts(cardId)
            facts.openedOn = month
            records.cards[cardId] = facts
        }
    }

    static func setSpent(_ usd: Decimal?, cardId: String, offerId: String, in store: OfferStore) throws {
        try store.update { records in
            var facts = records.facts(cardId)
            guard var state = facts.offers[offerId] else { return }
            state.spentTowardCapUsd = usd.map { max(0, $0) }
            facts.offers[offerId] = state
            records.cards[cardId] = facts
        }
    }

    /// yyyy-MM months from one day's month through another's (at most 24), for the opening-month picker.
    static func months(from start: String?, through end: String?) -> [String] {
        guard let start, let end, start <= end else { return [] }
        var months: [String] = []
        var month = String(start.prefix(7))
        while month <= String(end.prefix(7)), months.count < 24 {
            months.append(month)
            guard let next = OfferMath.day("\(month)-01", plusMonths: 1) else { break }
            month = String(next.prefix(7))
        }
        return months
    }

    /// "2026-07" → "Jul 2026".
    static func monthLabel(_ month: String) -> String {
        Day.medium("\(month)-01").map { "\($0.prefix(3)) \($0.suffix(4))" } ?? month
    }
}

/// Settings > Cards > Card offers: each wallet card's questions, answered with one tap.
struct OfferQuestionsView: View {
    let deps: AppDependencies

    @State private var records = OfferRecords()
    @State private var spentText: [String: String] = [:]
    @State private var error: String?

    private var wallet: Wallet { deps.walletStore.load() }
    private var today: String { Day.today(settings: deps.settings, now: deps.now(), timeZone: deps.timeZone) }
    private var questions: [OfferQuestion] {
        OfferQuestions.questions(wallet: wallet, catalog: deps.catalog, records: records, today: today)
    }

    var body: some View {
        Form {
            let byCard = Dictionary(grouping: questions, by: \.cardId)
            if byCard.isEmpty {
                Text("No offers to confirm for your cards right now.")
                    .foregroundStyle(.secondary)
            }
            ForEach(wallet.cards.map(\.cardId).filter { byCard[$0] != nil }, id: \.self) { cardId in
                Section(deps.catalog.shortName(cardId) ?? cardId) {
                    ForEach(byCard[cardId] ?? []) { question in
                        row(question)
                    }
                }
            }
            Section {
                Button("Delete all offer answers", role: .destructive) {
                    deps.offers.removeAll()
                    reload()
                }
                .accessibilityIdentifier("offers.deleteAll")
            } footer: {
                Text("Your answers stay on this iPhone. Paywise uses them after each check to add your offers to the cash numbers, and never sends them.")
            }
        }
        .navigationTitle("Card offers")
        .onAppear(perform: reload)
        .alert("Couldn't save", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    @ViewBuilder
    private func row(_ question: OfferQuestion) -> some View {
        let state = current(question)
        VStack(alignment: .leading, spacing: 8) {
            Text(question.text).font(.body.weight(.semibold))
            if let detail = question.detail {
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                ForEach([OfferAnswer.yes, .no, .notSure], id: \.self) { answer in
                    let selected = state?.answer == answer
                    Button(label(answer)) { save(answer, question) }
                        .buttonStyle(.bordered)
                        .tint(selected ? Color.accentColor : Color.secondary)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("offers.\(question.id).\(answer.rawValue)")
                }
            }
            if state?.answer == .yes, !question.openingMonths.isEmpty {
                Picker("Opened in", selection: openingMonth(question.cardId)) {
                    Text("Not sure").tag(String?.none)
                    ForEach(question.openingMonths, id: \.self) { month in
                        Text(OfferQuestions.monthLabel(month)).tag(Optional(month))
                    }
                }
            }
            if state?.answer == .yes, question.hasCap, case .offer(let offerId) = question.subject {
                TextField("Spent toward the cap so far ($, optional)", text: spent(question.cardId, offerId))
                    .keyboardType(.decimalPad)
            }
        }
        .padding(.vertical, 4)
    }

    private func label(_ answer: OfferAnswer) -> String {
        switch answer {
        case .yes: "Yes"
        case .no: "No"
        case .notSure: "Not sure"
        }
    }

    private func current(_ question: OfferQuestion) -> OfferState? {
        let facts = records.facts(question.cardId)
        switch question.subject {
        case .offer(let id): return facts.offers[id]
        case .event(let id): return facts.events[id]
        }
    }

    private func save(_ answer: OfferAnswer, _ question: OfferQuestion) {
        perform { try OfferQuestions.answer(answer, to: question, today: today, in: deps.offers) }
    }

    private func openingMonth(_ cardId: String) -> Binding<String?> {
        Binding(
            get: { records.facts(cardId).openedOn },
            set: { month in perform { try OfferQuestions.setOpeningMonth(month, cardId: cardId, in: deps.offers) } }
        )
    }

    private func spent(_ cardId: String, _ offerId: String) -> Binding<String> {
        let key = "\(cardId)/\(offerId)"
        return Binding(
            get: {
                spentText[key] ?? records.state(cardId: cardId, offerId: offerId)?.spentTowardCapUsd.map { "\($0)" } ?? ""
            },
            set: { text in
                spentText[key] = text
                let usd = Decimal(string: text.filter { $0.isNumber || $0 == "." }, locale: Locale(identifier: "en_US_POSIX"))
                perform { try OfferQuestions.setSpent(usd, cardId: cardId, offerId: offerId, in: deps.offers) }
            }
        )
    }

    private func perform(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            self.error = error.localizedDescription
        }
        reload()
    }

    private func reload() {
        records = deps.offers.load()
    }
}
