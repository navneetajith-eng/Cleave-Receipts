import SwiftUI

enum DesignSystem {
    
    // Earthy, relaxed colors (Mini Motorways inspired)
    static let canvasDark = Color(hex: "242220") // Warm charcoal
    static let accentSage = Color(hex: "95A595")
    static let accentDustyRose = Color(hex: "C29591")
    static let accentMustard = Color(hex: "D9B273")
    static let accentSlate = Color(hex: "7C8C99")
    
    // Soft Gradient for primary buttons
    static let primaryGradient = LinearGradient(
        colors: [accentSage, accentSlate], 
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
                            colors: [Color.white.opacity(0.15), Color.clear, Color.white.opacity(0.05)],
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
                .background(DesignSystem.primaryGradient)
                .clipShape(Capsule())
                .shadow(color: accentSage.opacity(0.3), radius: 15, x: 0, y: 8)
        }
    }
}

// MARK: - Fluid Background
struct FluidBackground: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            DesignSystem.canvasDark.ignoresSafeArea()
            
            // Abstract earthy blobs
            Circle()
                .fill(DesignSystem.accentSage)
                .frame(width: 400, height: 400)
                .offset(x: animate ? -100 : 100, y: animate ? -150 : -50)
                .blur(radius: 90)
                .opacity(0.4)
            
            Circle()
                .fill(DesignSystem.accentDustyRose)
                .frame(width: 350, height: 350)
                .offset(x: animate ? 150 : -50, y: animate ? 200 : 50)
                .blur(radius: 90)
                .opacity(0.4)
            
            Circle()
                .fill(DesignSystem.accentMustard)
                .frame(width: 250, height: 250)
                .offset(x: animate ? -50 : 150, y: animate ? 100 : 250)
                .blur(radius: 80)
                .opacity(0.3)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Modifiers
extension View {
    func fidelityCard() -> some View {
        self.modifier(DesignSystem.CardModifier())
    }
    
    func primaryButton() -> some View {
        self.modifier(DesignSystem.PrimaryButtonModifier())
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
