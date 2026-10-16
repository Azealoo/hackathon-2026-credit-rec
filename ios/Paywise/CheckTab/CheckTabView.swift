import PhotosUI
import SwiftUI

enum CheckRoute: Hashable {
    case sent
}

/// The Back Tap prompt, or the setup it leads to, as a sheet over the Check tab. Both follow the system appearance
/// (R18), unlike the tab, which is pinned light.
enum CheckSheet: String, Identifiable {
    case prompt, setup
    var id: String { rawValue }
}

/// The Check tab (SPEC §5.1, §9.1, §15.7 step 11): "Check a screenshot" from Photos through the same pipeline as a
/// press, the answer in the app. A paying moment, so always light (docs/design.md §1).
struct CheckTabView: View {
    static let idleTitle = "Double-tap the back of your iPhone on any checkout"
    static let idleLine = "Paywise tells you which of your cards covers it if it breaks or gets stolen, and what that costs in cash back. Or check a screenshot here."

    @State private var check: InAppCheck
    @State private var pickerItem: PhotosPickerItem?
    @State private var path: [CheckRoute] = []
    @State private var checkCount: Int
    @State private var triggerSetupDone: Bool
    @State private var sheet: CheckSheet?
    @Environment(\.scenePhase) private var scenePhase
    private let settings: PaywiseSettings
    private let catalog: CardCatalog
    /// Off while a debug `-checkState` answer is on screen.
    private let offersLastPress: Bool

    init(deps: AppDependencies) {
        let check = InAppCheck(deps: deps)
        var offersLastPress = true
        #if DEBUG
        // `-checkState <state>`: one of the island's answers, as the app shows it (screenshots).
        if let demo = CheckTabDemo.requested(),
           let phase = demo.phase(catalog: deps.catalog, wallet: deps.walletStore.load()) {
            check.show(phase)
            offersLastPress = false
        }
        #endif
        self.offersLastPress = offersLastPress
        _check = State(initialValue: check)
        settings = deps.settings
        catalog = deps.catalog
        _checkCount = State(initialValue: deps.settings.inAppCheckCount)
        _triggerSetupDone = State(initialValue: deps.settings.triggerSetupDone)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if check.phase == .idle {
                        // The trigger, Back Tap first (owner request, Oct 16), then what the answer tells you.
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Self.idleTitle)
                                .font(.app(17, .semibold))
                                .tracking(-0.3)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("check.idleTitle")
                            Text(Self.idleLine)
                                .font(.app(15))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if check.showsLastPress {
                        // §6.6 "save later": the last press's answer, which had no [Paying with …] where it showed.
                        Text("Your last check")
                            .font(.app(13, .semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("check.lastPress")
                    }
                    InAppResultCard(check: check, catalog: catalog, done: { check.reset() })
                    #if DEBUG
                    if CheckTabDemo.doubleSave {
                        // `-doubleSave`: what each save returned, read by the UI test (not drawn).
                        Color.clear
                            .frame(width: 1, height: 1)
                            .accessibilityElement()
                            .accessibilityLabel(check.saveOutcomes.joined(separator: ","))
                            .accessibilityIdentifier("debug.saveOutcomes")
                    }
                    #endif
                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        Text("Check a screenshot")
                    }
                    // One primary button at a time: under a result with [Paying with …], that is the primary one;
                    // under any other answer (Keep, No checkout, Couldn't check, Saved), this is.
                    .buttonStyle(AppButtonStyle(prominent: !showsSaveButton))
                    .disabled(check.isChecking)
                    .accessibilityIdentifier("check.pickScreenshot")

                    GroupedCard(padding: 0) {
                        NavigationLink(value: CheckRoute.sent) {
                            LinkRow(title: "What we sent", systemImage: "paperplane")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("check.whatWeSent")
                        if checkCount >= 2 && !triggerSetupDone {
                            // §5.1 step 3: the setup is offered again after the 2nd in-app check, as this row and
                            // (once) as the Back Tap prompt.
                            Divider().padding(.leading, 52)
                            Button { sheet = .setup } label: {
                                LinkRow(title: TriggerSetupView.title, systemImage: "hand.tap")
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("check.triggerSetup")
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Check")
            .navigationDestination(for: CheckRoute.self) { route in
                switch route {
                case .sent:
                    SentListView(checkStore: check.deps.checkStore, catalog: catalog)
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await run(item) }
        }
        .task {
            if offersLastPress { check.offerLastPress() }
            #if DEBUG
            if SetupDemo.showBackTapPrompt { sheet = .prompt }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            // A press runs while the app is in the background; its result is offered when the app comes back.
            if phase == .active, offersLastPress { check.offerLastPress() }
        }
        // The Back Tap prompt's second showing: when the tab is back at its start (after [Done], or on a later
        // launch), never over an answer the user is reading.
        .task(id: promptMoment) { await offerPromptIfDue() }
        .sheet(item: $sheet) { route in
            Group {
                switch route {
                case .prompt:
                    BackTapPromptSheet(
                        setUp: { sheet = .setup },
                        notNow: {
                            BackTapPrompt.notNow(settings: settings)
                            sheet = nil
                        }
                    )
                case .setup:
                    NavigationStack {
                        TriggerSetupView(mode: .standalone, settings: settings, checkStore: check.deps.checkStore) {
                            triggerSetupDone = settings.triggerSetupDone
                        }
                    }
                }
            }
            .followsSystemAppearance()
            .onDisappear { triggerSetupDone = settings.triggerSetupDone }
        }
    }

    /// The tab at its start, nothing pushed, the app in front: when the prompt may show.
    private var promptMoment: Bool {
        check.phase == .idle && path.isEmpty && scenePhase == .active
    }

    private func offerPromptIfDue() async {
        guard promptMoment, offersLastPress else { return }
        // Let a tab switch or a pop settle first.
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled, promptMoment, sheet == nil,
              BackTapPrompt.shouldOffer(.checkTab, settings: settings)
        else { return }
        BackTapPrompt.didShow(.checkTab, settings: settings)
        sheet = .prompt
    }

    private var showsSaveButton: Bool {
        check.record.map { CheckResultView.showsSaveButton($0, catalog: catalog) } ?? false
    }

    private func run(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        // Loaded into memory only; the screenshot is never saved (§10 retention copy).
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await check.run(imageData: data)
        settings.inAppCheckCount += 1
        checkCount = settings.inAppCheckCount
    }
}

/// The in-app answer: *Checking*, then the result view the snippet uses, drawn like the snippet and always light.
struct InAppResultCard: View {
    let check: InAppCheck
    let catalog: CardCatalog
    /// Off for onboarding's sample check, so the sample never becomes a saved purchase.
    var showsSaveButton = true
    /// The Saved and Sent views' [Done]; nil shows none.
    var done: (@MainActor () -> Void)?

    var body: some View {
        Group {
            switch check.phase {
            case .idle:
                EmptyView()
            case .checking:
                CheckingCard()
            case .record(let record):
                card {
                    CheckResultView(
                        record: record,
                        catalog: catalog,
                        showsSaveButton: showsSaveButton,
                        actions: .init(
                            save: {
                                Task { await check.save() }
                                #if DEBUG
                                // `-doubleSave`: a second save racing the first, for the idempotency UI test.
                                if CheckTabDemo.doubleSave { Task { await check.save() } }
                                #endif
                            },
                            showSent: { Task { await check.showSent() } },
                            done: done
                        )
                    )
                }
                .accessibilityIdentifier("check.result")
            case .message(let state):
                card {
                    MessageSnippetView(
                        line1: state.line1, line2: state.line2, line3: state.line3, isWarning: state.glyph == .warning
                    )
                }
                .accessibilityIdentifier("check.result")
            }
        }
        .environment(\.colorScheme, .light)
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 40, style: .continuous))
            .shadow(color: Color(red: 10 / 255, green: 20 / 255, blue: 60 / 255).opacity(0.12), radius: 24, y: 12)
            .accessibilityElement(children: .contain)
    }
}

/// §6.3 *Checking*, in the app: the logo leading and the spinner trailing, as the island pairs its glyph with the
/// progress ring. (The logo inside a large spinner, as the shield was, collides with the spokes: it is wider.)
private struct CheckingCard: View {
    var body: some View {
        HStack(spacing: 14) {
            PaywiseMark(size: 32)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Reading this screen…")
                    .font(.app(17, .semibold))
                    .tracking(-0.3)
                Text("Only the order summary leaves your phone")
                    .font(.app(15))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ProgressView()
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 40, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("check.progress")
    }
}

/// A navigation row inside a grouped card.
struct LinkRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.app(17))
                .foregroundStyle(Color("accent"))
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(title)
                .font(.app(17))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.app(13, .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
