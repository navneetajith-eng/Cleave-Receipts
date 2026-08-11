import SwiftUI

@main
struct CleaveApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    SupabaseManager.shared.handleAuthCallback(url)
                }
                #if os(iOS)
                .preferredColorScheme(.dark)
                #endif
        }
    }
}
