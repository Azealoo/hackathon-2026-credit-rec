import ActivityKit
import SwiftUI

/// "Make it one press" (SPEC §5.1 steps 3–4, §15.7 step 14): get the Paywise Shortcut, bind it to the Action Button
/// (first) or Back Tap, then a practice press on the demo store. Skippable. Follows the system appearance.
struct TriggerSetupView: View {
    enum Mode {
        /// The last onboarding step: [Done] and [Skip for now].
        case onboarding
        /// From Settings or the Check tab: [Done].
        case standalone
    }

    /// The team's iCloud link for the Shortcut (ios/Shortcut/README.md "Share it"). Until it exists the screen offers
    /// "Show the steps" (`ShortcutGuideView`) instead of a link; no made-up URL.
    static let shortcutLink: URL? = nil
    static let practiceURL = URL(string: "https://paywise-store.onrender.com/checkout.html?item=laptop")!

    let mode: Mode
    var settings: PaywiseSettings = .appGroup
    let finish: () -> Void
    @State private var showingGuide = false
    @Environment(\.dismiss) private var dismiss

    init(mode: Mode, settings: PaywiseSettings = .appGroup, finish: @escaping () -> Void) {
        self.mode = mode
        self.settings = settings
        self.finish = finish
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Press and hold the Action Button on any checkout, and Paywise answers over the store's own page.")
                    .font(.app(15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

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
                StepCard(number: 2, title: "Set the Action Button") {
                    Text("Settings › Action Button › Shortcut › Paywise")
                        .stepPath()
                        .accessibilityIdentifier("trigger.actionButton")
                }
                StepCard(number: 3, title: "Keeping Silent on it, or no Action Button? Use Back Tap") {
                    Text("Settings › Accessibility › Touch › Back Tap › Double Tap › Paywise")
                        .stepPath()
                        .accessibilityIdentifier("trigger.backTap")
                }
                StepCard(number: 4, title: "Practice press") {
                    Text("Open the sample checkout in Safari, then press and hold the Action Button (or double-tap the back). Answer each prompt with Always Allow, and press once more: no prompts this time.")
                        .stepBody()
                    Link("Open the sample checkout", destination: Self.practiceURL)
                        .buttonStyle(AppButtonStyle(prominent: false))
                        .accessibilityIdentifier("trigger.practice")
                }

                VStack(spacing: 10) {
                    Button("Done") {
                        settings.triggerSetupDone = true
                        finish()
                        if mode == .standalone { dismiss() }
                    }
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
        .navigationTitle("Make it one press")
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
        Section(title: "Set the Action Button", steps: [
            Step(number: 13, text: "Go to **Settings › Action Button**, swipe to **Shortcut**, tap **Choose a Shortcut** and pick **Paywise**. Keeping Silent on the Action Button, or no Action Button? Go to **Settings › Accessibility › Touch › Back Tap › Double Tap** and pick **Paywise** instead."),
        ]),
        Section(title: "Practice press", steps: [
            Step(number: 14, text: "Open the sample checkout in Safari, then press and hold the Action Button (or double-tap the back). Answer each prompt with **Always Allow**. Press again: no prompts this time, just the answer."),
        ], showsPracticeLink: true),
        Section(title: "Check a screenshot you already took", steps: [
            Step(number: 15, text: "Open it in **Photos**, tap **Share** and pick **Paywise**. If it isn't in the list, tap **Edit Actions…** to add it."),
        ]),
    ]

    static let troubleTitle = "If it doesn't work"

    static let trouble: [Trouble] = [
        Trouble(symptom: "Nothing happens when you press", fix: "Check that **Settings › Action Button** (or **Back Tap › Double Tap**) still shows Paywise, and that **Show in Share Sheet** is on with **Images** only."),
        Trouble(symptom: "\"No checkout total found\" on the first press", fix: "The prompts covered the store's page. Press once more."),
        Trouble(symptom: "\"Use the Paywise shortcut\"", fix: "Check Checkout ran without a screenshot. Redo steps 8 and 10 so both fields hold a blue token."),
        Trouble(symptom: "A prompt on every press", fix: "You tapped **Allow Once**. In the Shortcut's **Details › Privacy**, tap **Reset Privacy**, press again and pick **Always Allow**."),
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
