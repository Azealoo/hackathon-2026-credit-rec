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
                #if DEBUG
                DebugLiveActivitySection(status: $debugStatus)
                #endif
            }
            .navigationTitle("Paywise")
        }
        .task {
            // §6.2: on app launch, end any leftover activities. The debug autostart runs after it
            // in the same task, so the cleanup can't end the new activity.
            await SampleActivity.endAll()
            #if DEBUG
            if SampleActivity.autostartRequested {
                debugStatus = await SampleActivity.start()
            }
            #endif
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
