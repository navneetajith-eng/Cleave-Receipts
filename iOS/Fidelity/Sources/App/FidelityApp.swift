import SwiftUI

@main
struct FidelityApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(iOS)
                .preferredColorScheme(.dark)
                #endif
        }
    }
}
