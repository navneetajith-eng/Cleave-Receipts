import SwiftUI

struct EmptyStateView: View {
    let iconName: String
    let title: String
    let message: String
    var onDarkBackground = false

    private var primaryColor: Color { onDarkBackground ? .white : DesignSystem.ink }
    private var secondaryColor: Color { onDarkBackground ? .white.opacity(0.72) : DesignSystem.inkMuted }

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(onDarkBackground ? Color.white.opacity(0.10) : Color.black.opacity(0.03))
                    .frame(width: 120, height: 120)

                Circle()
                    .stroke(onDarkBackground ? Color.white.opacity(0.18) : Color.black.opacity(0.05), lineWidth: 1)
                    .frame(width: 140, height: 140)

                Image(systemName: iconName)
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(onDarkBackground ? .white.opacity(0.9) : DesignSystem.accentNavy.opacity(0.8))
            }
            .padding(.bottom, 10)

            VStack(spacing: 12) {
                Text(title)
                    .font(DesignSystem.titleFont(22))
                    .foregroundColor(primaryColor)

                Text(message)
                    .font(DesignSystem.bodyFont(15))
                    .foregroundColor(secondaryColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .padding(.vertical, 40)
    }
}
