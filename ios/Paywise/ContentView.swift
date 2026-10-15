import ActivityKit
import SwiftUI

struct ContentView: View {
    @State private var debugStatus = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Paywise tells you which of your cards covers this purchase if it breaks or gets stolen, and what that costs in cash back.")
                        .foregroundStyle(.secondary)
                }
                CheckSettingsSection()
                #if DEBUG
                DebugLiveActivitySection(status: $debugStatus)
                #endif
            }
            .navigationTitle("Paywise")
        }
        .task {
            // §6.2: on app launch, end any leftover activities. The debug autostart runs after it
            // in the same task, so the cleanup can't end the new activity.
            await LiveActivityController.shared.endAll()
            #if DEBUG
            if SampleActivity.autostartRequested {
                debugStatus = await SampleActivity.start()
            }
            // `-demoActivity <state|end>`: a Live Activity state for screenshots (Paywise/Debug/DemoActivity.swift).
            if let command = DemoActivity.command() {
                debugStatus = await DemoActivity.run(command)
            }
            #endif
        }
    }
}

/// How results appear and sound (R5), stored in App Group `UserDefaults` so the intents read them on every press.
/// Lets a device test switch Pattern A / Pattern B / the island fallback without a rebuild.
private struct CheckSettingsSection: View {
    @AppStorage(PaywiseSettings.Key.snippetMode, store: PaywiseSettings.appGroup.defaults)
    private var snippetMode = SnippetMode.snippet.rawValue
    @AppStorage(PaywiseSettings.Key.silentAlerts, store: PaywiseSettings.appGroup.defaults)
    private var silentAlerts = true
    @AppStorage(PaywiseSettings.Key.replayEnabled, store: PaywiseSettings.appGroup.defaults)
    private var replayEnabled = true

    var body: some View {
        Section {
            Picker("Results", selection: $snippetMode) {
                Text("Snippet").tag(SnippetMode.snippet.rawValue)
                Text("Confirm").tag(SnippetMode.confirm.rawValue)
                Text("Island").tag(SnippetMode.island.rawValue)
            }
            Toggle("Silent island alerts", isOn: $silentAlerts)
            Toggle("Replay when offline", isOn: $replayEnabled)
        } header: {
            Text("Check")
        } footer: {
            Text("Snippet: result with a Paying with button. Confirm: the system's confirm prompt. Island: switch results as an island alert, held 8 s. A replayed result is always labelled.")
        }
    }
}

#if DEBUG
/// Debug-only: start and end a sample *Checking* Live Activity to check the island on a real phone.
private struct DebugLiveActivitySection: View {
    @Binding var status: String

    var body: some View {
        Section {
            Button("Start sample Live Activity") {
                Task { status = await SampleActivity.start() }
            }
            Menu("Start demo state") {
                ForEach(DemoActivity.allCases, id: \.self) { demo in
                    Button(demo.rawValue) {
                        Task { status = await DemoActivity.run(.start(demo)) }
                    }
                }
            }
            Button("End Live Activity", role: .destructive) {
                Task {
                    await SampleActivity.endAll()
                    status = "Ended all Paywise activities"
                }
            }
            if !status.isEmpty {
                Text(status)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Debug")
        } footer: {
            Text("Live Activities enabled: \(ActivityAuthorizationInfo().areActivitiesEnabled ? "yes" : "no")")
        }
    }
}
#endif

#Preview {
    ContentView()
}
