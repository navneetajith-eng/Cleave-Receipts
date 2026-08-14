import SwiftUI

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            Spacer()

            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 20))

                Text(message)
                    .font(DesignSystem.bodyFont(14))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .padding(16)
            .background(Color.red.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// Environment extension to manage global errors
@MainActor
final class ErrorManager: ObservableObject {
    static let shared = ErrorManager()

    @Published var errorMessage: String? = nil
    @Published var isShowingError = false

    private var dismissTask: Task<Void, Never>?

    func showError(_ message: String) {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized != "cancelled", normalized != "canceled", !normalized.contains("cancelled") else {
            return
        }
        dismissTask?.cancel()
        self.errorMessage = message
        withAnimation(.spring()) {
            self.isShowingError = true
        }

        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self.hideError()
        }
    }

    func hideError() {
        withAnimation(.spring()) {
            self.isShowingError = false
        }
    }
}
