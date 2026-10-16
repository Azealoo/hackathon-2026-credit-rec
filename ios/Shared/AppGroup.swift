import Foundation

/// The App Group shared by the app and the widget extension (SPEC §9.1).
enum AppGroup {
    static let identifier = "group.com.azealoo.paywise"

    /// The shared container. Falls back to the app's own Application Support folder when the
    /// entitlement is missing (an unsigned build), so a check still runs end to end.
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        return URL.applicationSupportDirectory.appending(path: "AppGroupFallback", directoryHint: .isDirectory)
    }
}

/// How a snippet-presented result appears (R5; switchable on the device without a rebuild).
enum SnippetMode: String, CaseIterable, Sendable {
    /// Pattern A: `ShowsSnippetIntent` + `CheckResultSnippetIntent` with a [Paying with …] button (default).
    case snippet
    /// Pattern B: `requestConfirmation` with a custom verb (§15.5).
    case confirm
    /// §6.6 G2 fallback: Switch / Keep-protected become `switch_fallback` island alerts, `.default` sound, held 8 s.
    case island
}

/// Settings in App Group `UserDefaults`, read by the intents on every run.
struct PaywiseSettings: Sendable {
    enum Key {
        static let snippetMode = "snippetMode"
        static let silentAlerts = "silentAlerts"
        static let replayEnabled = "replayEnabled"
        static let wallet = "wallet"
        /// The first-launch onboarding (§5.1) finished or was skipped.
        static let onboarded = "onboarded"
        /// "Pretend today is…" (§12.1 "14 months later"): on/off and the day, yyyy-MM-dd.
        static let dateOverrideEnabled = "dateOverrideEnabled"
        static let dateOverride = "dateOverride"
        /// In-app "Check a screenshot" runs, so the trigger setup is offered again after the 2nd (§5.1 step 3).
        static let inAppCheckCount = "inAppCheckCount"
        /// The trigger setup screen (§15.7 step 14) was finished, not skipped.
        static let triggerSetupDone = "triggerSetupDone"
        /// The check ID of the last press that stored a `CheckRecord` in a fallback mode (§6.6 "save later").
        static let lastPressCheckId = "lastPressCheckId"
    }

    /// `nil` means `UserDefaults.standard`. Tests pass a unique suite name.
    let suiteName: String?

    static let appGroup = PaywiseSettings(suiteName: AppGroup.identifier)

    var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    var snippetMode: SnippetMode {
        get { defaults.string(forKey: Key.snippetMode).flatMap(SnippetMode.init(rawValue:)) ?? .snippet }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.snippetMode) }
    }

    /// true: island alerts use `.named("silent.caf")`; false: `.default` (§6.6 "G2 fails on sound").
    var silentAlerts: Bool {
        get { defaults.object(forKey: Key.silentAlerts) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.silentAlerts) }
    }

    /// Replay a bundled response when the request fails or times out (§15.7 step 10). Default on.
    var replayEnabled: Bool {
        get { defaults.object(forKey: Key.replayEnabled) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.replayEnabled) }
    }

    var onboarded: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        nonmutating set { defaults.set(newValue, forKey: Key.onboarded) }
    }

    var dateOverrideEnabled: Bool {
        get { defaults.bool(forKey: Key.dateOverrideEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.dateOverrideEnabled) }
    }

    /// The stored "Pretend today is…" day (yyyy-MM-dd), whether or not the override is on.
    var dateOverrideValue: String? {
        get { defaults.string(forKey: Key.dateOverride) }
        nonmutating set { defaults.set(newValue, forKey: Key.dateOverride) }
    }

    /// The day the app treats as today when "Pretend today is…" is on and holds a valid day; nil otherwise.
    /// Used for the check's `clientDate` (so the purchase and its coverage dates follow it) and the claim's `asOf`.
    var dateOverrideDay: String? {
        guard dateOverrideEnabled else { return nil }
        let day = dateOverrideValue ?? Self.defaultDateOverride
        return Self.isDay(day) ? day : nil
    }

    /// §12.1 "14 months later" for the demo: Dec 18, 2027 (the override's day until another is picked).
    static let defaultDateOverride = "2027-12-18"

    var inAppCheckCount: Int {
        get { defaults.integer(forKey: Key.inAppCheckCount) }
        nonmutating set { defaults.set(newValue, forKey: Key.inAppCheckCount) }
    }

    var triggerSetupDone: Bool {
        get { defaults.bool(forKey: Key.triggerSetupDone) }
        nonmutating set { defaults.set(newValue, forKey: Key.triggerSetupDone) }
    }

    /// The last press's check (`CheckCheckoutIntent`) in the island or confirm mode, which the Check tab offers to save
    /// while it still can be: §6.6's island fallback and Pattern B's static snippet have no [Paying with …], so the
    /// purchase is saved later in the app. Pattern A's snippet has the button, so a press in that mode clears it, as
    /// does a check run in the app.
    var lastPressCheckId: String? {
        get { defaults.string(forKey: Key.lastPressCheckId) }
        nonmutating set { defaults.set(newValue, forKey: Key.lastPressCheckId) }
    }

    /// A real calendar day written yyyy-MM-dd.
    static func isDay(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return false }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == year && back.month == month && back.day == day
    }
}
