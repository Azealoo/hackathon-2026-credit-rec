import SwiftUI

@main
struct PaywiseApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // `-gallery <state>` opens on one result snippet, for screenshots (Paywise/Debug/Gallery.swift).
            Group {
                if let gallery = GalleryState.requested() {
                    GalleryScreen(state: gallery)
                } else {
                    ContentView()
                }
            }
            // `-forceReduceMotion` (Paywise/Debug/SetupDemo.swift): Reduce Motion on, for the still variants.
            .modifier(ForcedReduceMotion(enabled: SetupDemo.forceReduceMotion))
            #else
            ContentView()
            #endif
        }
    }
}

#if DEBUG
/// Sets the environment's Reduce Motion value for the whole window, sheets included.
private struct ForcedReduceMotion: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.environment(\._accessibilityReduceMotion, true)
        } else {
            content
        }
    }
}
#endif
