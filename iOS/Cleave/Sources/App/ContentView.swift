import SwiftUI

struct ContentView: View {
    @StateObject private var errorManager = ErrorManager.shared

    var body: some View {
        ZStack {
            RootView()

            if errorManager.isShowingError, let message = errorManager.errorMessage {
                ErrorBanner(message: message) {
                    errorManager.hideError()
                }
                .zIndex(100)
            }
        }
        .environmentObject(errorManager)
    }
}

#Preview {
    ContentView()
}
