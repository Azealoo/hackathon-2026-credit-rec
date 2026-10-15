import SwiftUI

@main
struct PaywiseApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // `-gallery <state>` opens on one result snippet, for screenshots (Paywise/Debug/Gallery.swift).
            if let gallery = GalleryState.requested() {
                GalleryScreen(state: gallery)
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}
