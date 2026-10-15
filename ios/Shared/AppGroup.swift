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
}
