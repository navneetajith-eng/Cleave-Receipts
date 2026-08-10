import SwiftUI

@main
struct CleaveApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(iOS)
                .preferredColorScheme(.dark)
                #endif
        }
    }
}
