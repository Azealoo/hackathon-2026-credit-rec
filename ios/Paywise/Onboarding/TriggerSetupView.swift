import ActivityKit
import SwiftUI

/// "Set Up Back Tap" (SPEC §5.1 steps 3–4, §15.7 step 14; the owner's Oct 16 request puts Back Tap first): get the
/// Paywise Shortcut, turn on Back Tap (the path, with a breadcrumb that walks it), then "Try it now" on a sample
/// checkout in the app, which confirms the setup when a press arrives. The Action Button is an optional "Prefer a
/// button?" card, for people who don't keep it on Silent. Skippable. Follows the system appearance (R18).
///
/// iOS has no Back Tap API: the app can't turn it on, read whether it's on, or open Accessibility › Touch › Back Tap
/// (its only Settings link opens Paywise's own page), so the screen shows the path instead of an "Open Settings" button.
struct TriggerSetupView: View {
    enum Mode {
        /// The last onboarding step: [Done] and [Skip for now].
        case onboarding
        /// From Settings or the Check tab: [Done]. Present it as the root of a sheet's `NavigationStack`, never pushed:
        /// [Done] on "Try it now" calls this screen's `dismiss`, which closes a sheet but can't pop the screen above.
        case standalone
    }

    /// The team's iCloud link for the Shortcut (ios/Shortcut/README.md "Share it"). Until it exists the screen offers
    /// "Show the steps" (`ShortcutGuideView`) instead of a link; no made-up URL.
    static let shortcutLink: URL? = nil
    static let practiceURL = URL(string: "https://paywise-store.onrender.com/checkout.html?item=laptop")!
    static let title = "Set Up Back Tap"
    /// How the trigger is explained everywhere (onboarding, the Check tab, Settings): Back Tap first.
    static let intro = "Double-tap the back of your iPhone on any checkout, and Paywise tells you which card covers it."
    static let actionButtonPath = "Settings › Action Button › Shortcut › Paywise"

    let mode: Mode
    var settings: PaywiseSettings
    var checkStore: CheckStore
    let finish: () -> Void
    @State private var showingGuide = false
    @State private var confirmed = false
    @Environment(\.dismiss) private var dismiss

    init(
        mode: Mode, settings: PaywiseSettings = .appGroup, checkStore: CheckStore = .appGroup,
        finish: @escaping () -> Void
    ) {
        self.mode = mode
        self.settings = settings
        self.checkStore = checkStore
        self.finish = finish
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(Self.intro)
                    .font(.app(15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("trigger.intro")

                if !ActivityAuthorizationInfo().areActivitiesEnabled {
                    // §9.1: check `areActivitiesEnabled` in onboarding.
                    GroupedCard {
                        Label("Live Activities are off for Paywise. Turn them on in Settings › Paywise so Checking shows in the Dynamic Island.", systemImage: "exclamationmark.triangle.fill")
                            .font(.app(15))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("trigger.activitiesOff")
                }

                StepCard(number: 1, title: "Get the Paywise Shortcut") {
                    if let link = Self.shortcutLink {
                        Link("Add the Shortcut", destination: link)
                            .buttonStyle(AppButtonStyle(prominent: false))
                            .accessibilityIdentifier("trigger.shortcutLink")
                    } else {
                        Text("Build it in the Shortcuts app in about a minute: Take Screenshot, then Paywise's Check Checkout.")
                            .stepBody()
                        Button("Show the steps") { showingGuide = true }
                            .buttonStyle(AppButtonStyle(prominent: false))
                            .accessibilityIdentifier("trigger.shortcutSteps")
                    }
                }
                StepCard(number: 2, title: "Turn on Back Tap") {
                    Text("In the Settings app, go to:")
                        .stepBody()
                    BackTapPath()
                        .accessibilityIdentifier("trigger.backTap")
                }
                StepCard(number: 3, title: "Try it now") {
                    if confirmed {
                        BackTapWorks()
                    } else {
                        Text("Double-tap the back of your iPhone on a sample checkout, right here in Paywise.")
                            .stepBody()
                        NavigationLink {
                            TryItNowView(settings: settings, checkStore: checkStore, done: complete)
                        } label: {
                            Text("Try it now")
                        }
                        .buttonStyle(AppButtonStyle(prominent: false))
                        .accessibilityIdentifier("trigger.tryItNow")
                    }
                }

                GroupedCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Prefer a button?")
                            .font(.app(17, .semibold))
                            .tracking(-0.3)
                            .accessibilityAddTraits(.isHeader)
                        Text("If you don't use the Action Button for Silent, press and hold it instead:")
                            .stepBody()
                        Text(Self.actionButtonPath)
                            .stepPath()
                            .accessibilityIdentifier("trigger.actionButton")
                    }
                }
                .accessibilityIdentifier("trigger.preferButton")

                VStack(spacing: 10) {
                    Button("Done", action: complete)
                        .buttonStyle(AppButtonStyle(prominent: true))
                        .accessibilityIdentifier("trigger.done")
                    if mode == .onboarding {
                        Button("Skip for now") { finish() }
                            .buttonStyle(AppButtonStyle(prominent: false))
                            .accessibilityIdentifier("trigger.skip")
                    }
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Self.title)
        .onAppear { confirmed = settings.triggerSetupConfirmed }
        .sheet(isPresented: $showingGuide) {
            NavigationStack {
                ShortcutGuideView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingGuide = false }
                        }
                    }
            }
        }
    }

    /// [Done], here or on "Try it now" once it worked.
    private func complete() {
        settings.triggerSetupDone = true
        finish()
        if mode == .standalone { dismiss() }
    }
}

/// "Back Tap works ✓": a press arrived while "Try it now" was open.
struct BackTapWorks: View {
    var size: CGFloat = 17

    var body: some View {
        Text("Back Tap works \(Text("✓").foregroundStyle(.green))")
            .font(.app(size, size >= 20 ? .bold : .semibold))
            .tracking(-0.3)
            .accessibilityLabel("Back Tap works")
            .accessibilityIdentifier("trigger.works")
    }
}

/// Settings › Accessibility › Touch › Back Tap › Double Tap › Paywise, each segment lit in turn (a filled pill, so
/// color isn't the only cue). Still under Reduce Motion. Read as one path by VoiceOver.
struct BackTapPath: View {
    static let segments = ["Settings", "Accessibility", "Touch", "Back Tap", "Double Tap", "Paywise"]
    static var text: String { segments.joined(separator: " › ") }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit: Int?

    var body: some View {
        ChipFlow(spacing: 2) {
            ForEach(Array(Self.segments.enumerated()), id: \.offset) { index, segment in
                HStack(spacing: 2) {
                    Text(segment)
                        .font(.app(15, .semibold))
                        .foregroundStyle(lit == index ? Color.white : Color.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(lit == index ? Color("accent") : Color.clear, in: Capsule())
                    if index < Self.segments.count - 1 {
                        Text("›")
                            .font(.app(15, .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, -8)
        .accessibilityElement(children: .ignore)
        // Commas, not "›", so VoiceOver reads the path as a list of places.
        .accessibilityLabel(Self.segments.joined(separator: ", "))
        .task(id: reduceMotion) {
            guard !reduceMotion else {
                lit = nil
                return
            }
            await walk()
        }
    }

    private func walk() async {
        while !Task.isCancelled {
            for index in Self.segments.indices {
                withAnimation(.easeInOut(duration: 0.25)) { lit = index }
                try? await Task.sleep(for: .milliseconds(650))
                if Task.isCancelled { return }
            }
            try? await Task.sleep(for: .milliseconds(1100))
            withAnimation(.easeInOut(duration: 0.25)) { lit = nil }
            try? await Task.sleep(for: .milliseconds(700))
        }
    }
}

// MARK: Try it now

/// Step 3: a sample checkout on screen and "Double-tap the back of your iPhone now". The Shortcut's Check Checkout
/// runs in this app's process and stores a `CheckRecord` in the App Group, so a record that wasn't there when the step
/// opened means the press arrived: "Back Tap works ✓", and setup is confirmed (the prompt never shows again). Any
/// answer counts, even *Couldn't check*: the trigger worked. Safari's sample checkout stays as a fallback.
struct TryItNowView: View {
    let settings: PaywiseSettings
    let checkStore: CheckStore
    let done: () -> Void
    @State private var confirmed = false

    var body: some View {
        ScrollView {
            TryItNowContent(confirmed: confirmed, done: done)
                .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Try it now")
        .navigationBarTitleDisplayMode(.inline)
        .task { await watch() }
    }

    private func watch() async {
        let watch = NewCheckWatch(baseline: checkStore.storedCheckIds())
        #if DEBUG
        if SetupDemo.simulateBackTap {
            // `-simulateBackTap`: a press on this screen, as the Shortcut would make it (Paywise/Debug/SetupDemo.swift).
            Task { await SetupDemo.simulatePress() }
        }
        #endif
        while !Task.isCancelled {
            if watch.arrived(in: checkStore.storedCheckIds()) {
                BackTapPrompt.confirmSetup(settings: settings)
                withAnimation(.spring(duration: 0.4)) { confirmed = true }
                AccessibilityNotification.Announcement("Back Tap works").post()
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}

/// What "Try it now" shows; also what its screenshot holds (`SampleCheckoutRender`).
struct TryItNowContent: View {
    var confirmed: Bool
    var done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if confirmed {
                BackTapWorks(size: 22)
            } else {
                TryItNowHeader()
            }
            SampleCheckoutCard()
            if confirmed {
                Button("Done", action: done)
                    .buttonStyle(AppButtonStyle(prominent: true))
                    .accessibilityIdentifier("tryItNow.done")
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Waiting for a double tap…")
                        .font(.app(15))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("tryItNow.waiting")
                // Worded without "sample": this text is in the press's screenshot too, and with "sample store page"
                // here the backend's parser called the screen not a checkout in 2 of 6 tries (0 of 10 like this).
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nothing happens? Try the store page in Safari.")
                        .font(.app(15))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Open the store page in Safari", destination: TriggerSetupView.practiceURL)
                        .buttonStyle(AppButtonStyle(prominent: false))
                        .accessibilityIdentifier("trigger.practice")
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Double-tap the back of your iPhone now", and what the first press asks.
struct TryItNowHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Double-tap the back of your iPhone now")
                .font(.app(22, .bold))
                .tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("tryItNow.instruction")
            Text("The first time, Shortcuts asks for permission: tap Always Allow on each prompt, then double-tap again.")
                .font(.app(15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A sample checkout, clearly marked as one: the S1 laptop (fake data, SPEC §15.4) with enough of a checkout for the
/// on-device gate (a "Total" line with an amount, "Pay with", "Place order"). A paying moment, so always light
/// (design.md §1). "Place order" is a label, not a button.
struct SampleCheckoutCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sample checkout")
                    .font(.app(13, .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text("Northbay Electronics")
                    .font(.app(20, .bold))
                    .tracking(-0.4)
            }
            Divider()
            // The item's name and price stay on one line ("Aero 14 Laptop  $1,499.00" to the reader): with the name
            // wrapped at XXL, the backend's parser called the screen not a checkout in 5 of 10 tries (0 of 10
            // unwrapped). So the thumbnail goes first when the row is short of room, and only past that the price
            // moves under the name.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "laptopcomputer")
                        .font(.app(22))
                        .foregroundStyle(.secondary)
                        .frame(width: 52, height: 52)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                    item(stacked: false)
                }
                item(stacked: false)
                item(stacked: true)
            }
            Divider()
            HStack(spacing: 10) {
                Text("Pay with")
                    .font(.app(15))
                    .foregroundStyle(.secondary)
                Text("Mastercard ••5678")
                    .font(.app(17, .semibold))
            }
            Divider()
            HStack {
                Text("Total")
                    .font(.app(20, .bold))
                Spacer(minLength: 8)
                Text("$1,499.00")
                    .font(.app(20, .bold))
            }
            Text("Place order")
                .font(.app(17, .semibold))
                .foregroundStyle(Color(.systemBackground))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color(.label), in: Capsule())
                .accessibilityHidden(true)
        }
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .background {
            // The shadow on the card's shape only, not on each line of text.
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color(red: 10 / 255, green: 20 / 255, blue: 60 / 255).opacity(0.10), radius: 18, y: 8)
        }
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sample checkout. Northbay Electronics. Aero 14 Laptop, new, $1,499.00. Pay with Mastercard ending 5678. Total $1,499.00.")
        .accessibilityIdentifier("tryItNow.sampleCard")
    }

    /// "Aero 14 Laptop  $1,499.00", then "New" and "Qty 1"; `stacked` puts the price under the name.
    private func item(stacked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if stacked {
                Text("Aero 14 Laptop")
                    .font(.app(17, .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("$1,499.00")
                    .font(.app(17, .semibold))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Aero 14 Laptop")
                        .font(.app(17, .semibold))
                        .fixedSize()
                    Spacer(minLength: 8)
                    Text("$1,499.00")
                        .font(.app(17, .semibold))
                        .fixedSize()
                }
            }
            Text("New")
                .font(.app(15))
                .foregroundStyle(.secondary)
            Text("Qty 1")
                .font(.app(15))
                .foregroundStyle(.secondary)
        }
    }
}

/// The check IDs present when "Try it now" opened; any other ID is a press that arrived since.
struct NewCheckWatch: Sendable, Equatable {
    let baseline: Set<String>

    func newCheckIds(in ids: Set<String>) -> Set<String> {
        ids.subtracting(baseline)
    }

    func arrived(in ids: Set<String>) -> Bool {
        !newCheckIds(in: ids).isEmpty
    }
}

extension CheckStore {
    /// The ID of every record file in the folder, expired or not, without decoding them (polled twice a second by
    /// "Try it now").
    func storedCheckIds() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }.map { String($0.dropLast(5)) })
    }
}

private struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        GroupedCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("\(number)")
                        .font(.app(15, .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color("accent"), in: Circle())
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.app(17, .semibold))
                        .tracking(-0.3)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                content
            }
        }
    }
}

private extension Text {
    func stepBody() -> some View {
        font(.app(15))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    func stepPath() -> some View {
        font(.app(15, .medium))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Show the steps": how to build the Paywise Shortcut by hand, shown until the team's iCloud link exists. The
/// user-facing steps of ios/Shortcut/README.md (A2, B and C there, numbered the same), without its developer notes.
struct ShortcutGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(ShortcutSteps.inline(ShortcutSteps.intro))
                    .font(.app(15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GuideSection(title: ShortcutSteps.shapeTitle) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(ShortcutSteps.shape.enumerated()), id: \.offset) { _, row in
                            Text(ShortcutSteps.inline(row.text))
                                .font(.app(15))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.leading, CGFloat(row.indent) * 18)
                        }
                    }
                }
                .accessibilityIdentifier("trigger.guide.shape")

                ForEach(ShortcutSteps.sections) { section in
                    GuideSection(title: section.title) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(section.steps) { step in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("\(step.number).")
                                        .font(.app(15, .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .frame(minWidth: 26, alignment: .trailing)
                                        .accessibilityHidden(true)
                                    Text(ShortcutSteps.inline(step.text))
                                        .font(.app(15))
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Step \(step.number). \(String(ShortcutSteps.inline(step.text).characters))")
                            }
                            if section.showsPracticeLink {
                                Link("Open the sample checkout", destination: TriggerSetupView.practiceURL)
                                    .buttonStyle(AppButtonStyle(prominent: false))
                            }
                        }
                    }
                }

                GuideSection(title: ShortcutSteps.troubleTitle) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(ShortcutSteps.trouble.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.symptom)
                                    .font(.app(15, .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(ShortcutSteps.inline(item.fix))
                                    .font(.app(15))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("The Paywise Shortcut")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("trigger.guide")
    }
}

private struct GuideSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.app(13, .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            GroupedCard {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The steps in "Show the steps", in plain words for the person setting up their phone. Keep them in step with
/// ios/Shortcut/README.md (same numbers, same Shortcuts labels), which holds the developer notes these leave out.
enum ShortcutSteps {
    struct Step: Identifiable, Equatable, Sendable {
        let number: Int
        let text: String
        var id: Int { number }
    }

    struct Section: Identifiable, Equatable, Sendable {
        let title: String
        let steps: [Step]
        var showsPracticeLink = false
        var id: String { title }
    }

    struct Row: Equatable, Sendable {
        let indent: Int
        let text: String
    }

    struct Trouble: Equatable, Sendable {
        let symptom: String
        let fix: String
    }

    static let intro = """
    Build it once in the **Shortcuts** app, in about a minute. Open Paywise once and add your cards first: \
    Shortcuts lists Paywise's actions only after that.
    """

    static let shapeTitle = "When you're done it looks like this"

    /// The finished Shortcut, one action a row.
    static let shape: [Row] = [
        Row(indent: 0, text: "Receive **Images** from **Share Sheet** · If there's no input: **Continue**"),
        Row(indent: 0, text: "**If** Shortcut Input has any value"),
        Row(indent: 1, text: "**Check Checkout** · Screenshot: Shortcut Input"),
        Row(indent: 0, text: "**Otherwise**"),
        Row(indent: 1, text: "**Take Screenshot**"),
        Row(indent: 1, text: "**Check Checkout** · Screenshot: Screenshot"),
        Row(indent: 0, text: "**End If**"),
    ]

    static let sections: [Section] = [
        Section(title: "Build it", steps: [
            Step(number: 1, text: "Open **Shortcuts**, go to the **Shortcuts** tab and tap **+** at the top right."),
            Step(number: 2, text: "Tap the name at the top (**New Shortcut**), then **Rename**. Type **Paywise** and tap **Done**."),
            Step(number: 3, text: "Tap **ⓘ** (Details), turn on **Show in Share Sheet** and tap **Done**. A **Receive … from Share Sheet** row appears at the top."),
            Step(number: 4, text: "In that row, tap **Any**, then **Clear**. Tick **Images** only and tap **Done**. The row must still say **If there's no input: Continue**."),
            Step(number: 5, text: "In the search at the bottom, type **if** and tap **If**. Its first token must read **Shortcut Input**; if not, tap it and pick **Shortcut Input**."),
            Step(number: 6, text: "Tap **Condition** and pick **has any value**."),
            Step(number: 7, text: "Search **Check Checkout** (listed under **Paywise**) and tap it. Drag it up between **If** and **Otherwise**."),
            Step(number: 8, text: "In that action, tap **Screenshot** and pick **Shortcut Input**."),
            Step(number: 9, text: "Search **Take Screenshot** and tap it. Drag it between **Otherwise** and **End If**."),
            Step(number: 10, text: "Add **Check Checkout** again and drag it under **Take Screenshot**, above **End If**. Its field must show a blue **Screenshot** token; if it's grey, tap it and pick **Screenshot**."),
            Step(number: 11, text: "Leave **Show When Run** on in both Check Checkout actions, so the answer shows."),
            Step(number: 12, text: "Tap **Done**."),
        ]),
        Section(title: "Turn on Back Tap", steps: [
            Step(number: 13, text: "Go to **Settings › Accessibility › Touch › Back Tap › Double Tap** and pick **Paywise** (under Shortcuts). Prefer a button? If you don't use the Action Button for Silent, go to **Settings › Action Button**, swipe to **Shortcut**, tap **Choose a Shortcut** and pick **Paywise** instead."),
        ]),
        Section(title: "Try it", steps: [
            Step(number: 14, text: "Open the sample checkout in Safari, then double-tap the back of your iPhone (or press and hold the Action Button). Answer each prompt with **Always Allow**. Double-tap again: no prompts this time, just the answer."),
        ], showsPracticeLink: true),
        Section(title: "Check a screenshot you already took", steps: [
            Step(number: 15, text: "Open it in **Photos**, tap **Share** and pick **Paywise**. If it isn't in the list, tap **Edit Actions…** to add it."),
        ]),
    ]

    static let troubleTitle = "If it doesn't work"

    static let trouble: [Trouble] = [
        Trouble(symptom: "Nothing happens when you double-tap", fix: "Check that **Settings › Accessibility › Touch › Back Tap › Double Tap** (or **Settings › Action Button**) still shows Paywise, and that **Show in Share Sheet** is on with **Images** only."),
        Trouble(symptom: "\"No checkout total found\" the first time", fix: "The prompts covered the store's page. Double-tap once more."),
        Trouble(symptom: "\"Use the Paywise shortcut\"", fix: "Check Checkout ran without a screenshot. Redo steps 8 and 10 so both fields hold a blue token."),
        Trouble(symptom: "A prompt every time", fix: "You tapped **Allow Once**. In the Shortcut's **Details › Privacy**, tap **Reset Privacy**, double-tap again and pick **Always Allow**."),
        Trouble(symptom: "Check Checkout isn't in the search", fix: "Open the Paywise app once, then search **Paywise**."),
    ]

    /// Inline Markdown (bold) as styled text.
    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    /// Every word the guide shows, for tests.
    static var allText: String {
        var parts = [intro, shapeTitle, troubleTitle]
        parts += shape.map(\.text)
        for section in sections {
            parts.append(section.title)
            parts += section.steps.map(\.text)
        }
        parts += trouble.flatMap { [$0.symptom, $0.fix] }
        return parts.joined(separator: "\n")
    }
}
