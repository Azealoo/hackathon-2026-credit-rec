#if DEBUG
import FoundationModels
import SwiftUI
import UIKit

/// Feasibility test for reading carts with Apple's on-device model (branch experiment/on-device-parser).
///
/// Launch with `-parserLab` (and optionally `-parserLabRounds 3`). For every bundled fixture screen
/// (fixtures/ocr and fixtures/ocr-hard) it asks the on-device model for the same JSON the Claude parser returns
/// (backend/app/parser_llm.py RawScreen), with the same instructions (parser_prompt.txt is
/// `parser_llm.system_prompt()`, exported). Each result is one JSON line, printed with a `PARSERLAB ` prefix and
/// appended to Documents/parserlab.jsonl. Scoring happens on the Mac in backend/scripts/compare_parsers.py, through
/// the same parser_llm.build() as Claude's output, so the model is the only thing that differs.
///
/// Fixture text is fake (see fixtures/ocr-hard/README.md). Nothing leaves the phone.
enum ParserLabRequest {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("-parserLab") }
    static var rounds: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-parserLabRounds"), i + 1 < args.count, let n = Int(args[i + 1]) else {
            return 3
        }
        return max(1, n)
    }
}

// Field names and order match RawScreen's JSON keys in parser_llm.py (the model writes in declaration order).

@Generable(representNilExplicitlyInGeneratedContent: true)
struct LabItem {
    var name: String
    var price: String?
    @Guide(.anyOf(["unit", "line"])) var per: String
    var qty: Int
    // data/cards.json itemCategories ids, in catalog order.
    @Guide(.anyOf(["electronics", "computers", "phones", "audio", "cameras", "appliances", "tools", "bikes",
                   "instruments", "apparel", "home", "dining", "grocery", "pharmacy", "gift_card", "services",
                   "travel", "general"]))
    var cat: String
    @Guide(.anyOf(["new", "renewed", "used", "unknown"])) var cond: String
    @Guide(.anyOf(["merchant", "third_party", "unknown"])) var seller: String
}

@Generable(representNilExplicitlyInGeneratedContent: true)
struct LabExtra {
    @Guide(.anyOf(["shipping", "tax", "fee", "discount", "other"])) var kind: String
    var amount: String
}

@Generable(representNilExplicitlyInGeneratedContent: true)
struct LabPaying {
    @Guide(.anyOf(["saved_card", "card_form", "apple_pay", "unknown"])) var kind: String
    @Guide(.anyOf(["visa", "mastercard", "discover", "amex", "unknown"])) var network: String
}

@Generable(representNilExplicitlyInGeneratedContent: true)
struct LabConf {
    @Guide(.range(0...1)) var store: Double
    @Guide(.range(0...1)) var total: Double
    @Guide(.range(0...1)) var items: Double
}

@Generable(representNilExplicitlyInGeneratedContent: true)
struct LabScreen {
    @Guide(.anyOf(["checkout", "order_confirmation", "not_checkout", "unreadable"])) var screen: String
    var store: String?
    var items: [LabItem]
    var subtotal: String?
    var extras: [LabExtra]
    var total: String?
    @Guide(.element(.anyOf(["apple_pay", "saved_card", "card_form", "bnpl", "paypal", "other"])))
    var options: [String]
    var paying: LabPaying
    var planOffer: String?
    var bnpl: Bool
    var conf: LabConf
}

@MainActor
final class ParserLab: ObservableObject {
    @Published var log: [String] = []
    @Published var done = false

    private struct Case { let set: String; let fixture: String; let text: String }

    private let outURL = URL.documentsDirectory.appending(path: "parserlab.jsonl")

    func run(rounds: Int) async {
        UIApplication.shared.isIdleTimerDisabled = true  // keep the phone awake for the whole run
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        try? FileManager.default.removeItem(at: outURL)

        let model = SystemLanguageModel.default
        emit(["event": "start", "availability": String(describing: model.availability), "rounds": rounds,
              "os": UIDevice.current.systemVersion, "device": UIDevice.current.model,
              // Apple Intelligence eligibility depends on region and language, so log them (no personal data).
              "region": Locale.current.region?.identifier ?? "none",
              "languages": Locale.preferredLanguages, "timeZone": TimeZone.current.identifier])
        guard case .available = model.availability else {
            emit(["event": "done", "reason": "unavailable"])
            done = true
            return
        }
        guard let promptURL = Bundle.main.url(forResource: "parser_prompt", withExtension: "txt"),
              let instructions = try? String(contentsOf: promptURL, encoding: .utf8) else {
            emit(["event": "done", "reason": "no_prompt"])
            done = true
            return
        }
        let cases = loadCases()
        emit(["event": "cases", "count": cases.count])

        // One instruction-only token count, to see how much of the 4,096-token window the prompt uses.
        if let tokens = try? await model.tokenCount(for: Instructions(instructions)) {
            emit(["event": "instruction_tokens", "count": tokens])
        }

        var first = true
        for round in 1...rounds {
            for item in cases {
                let session = LanguageModelSession(model: model, instructions: instructions)
                let prompt = "<screen_text>\n\(item.text.trimmingCharacters(in: .whitespacesAndNewlines))\n</screen_text>"
                let started = ContinuousClock.now
                var record: [String: Any] = ["set": item.set, "fixture": item.fixture, "round": round, "cold": first]
                do {
                    let response = try await session.respond(
                        to: prompt, generating: LabScreen.self,
                        options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 1024))
                    record["ms"] = Self.milliseconds(since: started)
                    let json = response.rawContent.jsonString
                    record["raw"] = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) ?? json
                    record["usage"] = String(describing: response.usage)
                    record["error"] = NSNull()
                } catch {
                    record["ms"] = Self.milliseconds(since: started)
                    record["raw"] = NSNull()
                    record["error"] = String(describing: error)
                }
                first = false
                emit(record)
            }
        }
        emit(["event": "done", "reason": "finished"])
        done = true
    }

    private func loadCases() -> [Case] {
        var cases: [Case] = []
        for (set, folder) in [("base", "ocr"), ("hard", "ocr-hard")] {
            guard let dir = Bundle.main.url(forResource: folder, withExtension: nil),
                  let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            else { continue }
            for file in files.filter({ $0.pathExtension == "txt" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if let text = try? String(contentsOf: file, encoding: .utf8) {
                    cases.append(Case(set: set, fixture: file.deletingPathExtension().lastPathComponent, text: text))
                }
            }
        }
        return cases
    }

    private func emit(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }
        print("PARSERLAB \(line)")
        if let handle = try? FileHandle(forWritingTo: outURL) {
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            try? handle.close()
        } else {
            try? Data((line + "\n").utf8).write(to: outURL)
        }
        let summary = object["fixture"].map { "\($0) r\(object["round"] ?? "") \(object["ms"] ?? "") ms" + ((object["error"] is NSNull) ? "" : " error") }
        log.append(summary ?? line)
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let d = ContinuousClock.now - start
        return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
}

struct ParserLabScreen: View {
    @StateObject private var lab = ParserLab()

    var body: some View {
        NavigationStack {
            List(Array(lab.log.enumerated()), id: \.offset) { _, line in
                Text(line).font(.caption.monospaced())
            }
            .navigationTitle(lab.done ? "Parser lab: done" : "Parser lab: running")
        }
        .task {
            await lab.run(rounds: ParserLabRequest.rounds)
            // Debug-only harness: quit so `devicectl … launch --console` returns when the run ends.
            try? await Task.sleep(for: .seconds(2))
            exit(0)
        }
    }
}
#endif
