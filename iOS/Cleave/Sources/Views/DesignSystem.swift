import SwiftUI

enum DesignSystem {

    // Soft Beige Background
    static let canvasBeige = Color(hex: "E4DCCF") // Slightly deeper, earthier beige

    // Retro Sunset Background Blobs
    static let bgNavy = Color(hex: "01204E")
    static let bgTeal = Color(hex: "028391")
    static let bgOrange = Color(hex: "F85525")

    // Retro Sunset Card Colors
    static let cardNavy = Color(hex: "01204E")
    static let cardTeal = Color(hex: "028391")
    static let cardSand = Color(hex: "F6DCAC")
    static let cardPeach = Color(hex: "FAA968")
    static let cardOrange = Color(hex: "F85525")

    // Primary Accents
    static let accentNavy = cardNavy
    static let accentTeal = cardTeal
    static let accentSand = cardSand
    static let accentPeach = cardPeach
    static let accentOrange = cardOrange

    // Gradient for primary buttons
    static let primaryGradient = LinearGradient(
        colors: [accentTeal, accentNavy],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Glassmorphic Card
    struct CardModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .padding(24)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(LinearGradient(
                            colors: [Color.black.opacity(0.15), Color.clear, Color.black.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
        }
    }

    // Expressive Button
    struct PrimaryButtonModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(.system(.title3, design: .serif).weight(.medium))
                .foregroundColor(.white)
                .padding(.vertical, 18)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.85))
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.2), radius: 15, x: 0, y: 8)
        }
    }

    // Helper to get group color
    static func color(forGroupId id: String, in groups: [GroupModel]) -> Color {
        let cardColors = [cardNavy, cardTeal, cardOrange, cardPeach]
        if let index = groups.firstIndex(where: { $0.id.uuidString == id }) {
            return cardColors[index % cardColors.count]
        }
        return accentNavy
    }
}

// MARK: - Fluid Background
struct FluidBackground: View {
    var body: some View {
        DesignSystem.canvasBeige.ignoresSafeArea()
    }
}

// MARK: - Modifiers
extension View {
    func cleaveCard() -> some View {
        self.modifier(DesignSystem.CardModifier())
    }

    func primaryButton() -> some View {
        self.modifier(DesignSystem.PrimaryButtonModifier())
    }
}

// MARK: - Button Styles
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
