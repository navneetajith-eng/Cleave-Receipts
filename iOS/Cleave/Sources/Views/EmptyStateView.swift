import SwiftUI

struct EmptyStateView: View {
    let iconName: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.03))
                    .frame(width: 120, height: 120)

                Circle()
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    .frame(width: 140, height: 140)

                Image(systemName: iconName)
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(DesignSystem.accentNavy.opacity(0.8))
            }
            .padding(.bottom, 10)

            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.black.opacity(0.85))

                Text(message)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.black.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .padding(.vertical, 40)
    }
}
