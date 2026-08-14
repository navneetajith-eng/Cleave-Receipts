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

    // Core interface colors. Keeping these semantic avoids the accidental
    // dark-mode inheritance that previously washed out form text in sheets.
    static let ink = Color(hex: "0A2447")
    static let inkMuted = Color(hex: "5F625F")
    static let surface = Color(hex: "FFFDFC")
    static let fieldSurface = Color(hex: "F3EFE8")
    static let hairline = Color.black.opacity(0.08)

    // Cleave typography — the same family used by onboarding.
    static func displayFont(_ size: CGFloat) -> Font {
        .custom("AvenirNext-Heavy", size: size)
    }

    static func titleFont(_ size: CGFloat) -> Font {
        .custom("AvenirNext-DemiBold", size: size)
    }

    static func bodyFont(_ size: CGFloat) -> Font {
        .custom("AvenirNext-Medium", size: size)
    }

    static func labelFont(_ size: CGFloat) -> Font {
        .custom("AvenirNext-Heavy", size: size)
    }

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
        @Environment(\.isEnabled) private var isEnabled

        func body(content: Content) -> some View {
            content
                .font(DesignSystem.titleFont(18))
                .foregroundColor(.white)
                .padding(.vertical, 18)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
                .background(isEnabled ? DesignSystem.accentNavy : DesignSystem.accentNavy.opacity(0.35))
                .clipShape(Capsule())
                .shadow(color: isEnabled ? DesignSystem.accentNavy.opacity(0.22) : .clear, radius: 14, x: 0, y: 7)
                .animation(.easeOut(duration: 0.2), value: isEnabled)
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

// MARK: - Shared flow components
struct CleaveSectionHeading: View {
    let eyebrow: String?
    let title: String
    let detail: String?

    init(_ title: String, eyebrow: String? = nil, detail: String? = nil) {
        self.title = title
        self.eyebrow = eyebrow
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(DesignSystem.labelFont(10))
                    .tracking(1.8)
                    .foregroundStyle(DesignSystem.accentOrange)
            }
            Text(title)
                .font(DesignSystem.displayFont(28))
                .foregroundStyle(DesignSystem.ink)
            if let detail {
                Text(detail)
                    .font(DesignSystem.bodyFont(14))
                    .foregroundStyle(DesignSystem.inkMuted)
            }
        }
    }
}

struct CleaveIconButton: View {
    let systemName: String
    let accessibilityText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DesignSystem.ink)
                .frame(width: 44, height: 44)
                .background(DesignSystem.surface.opacity(0.82))
                .clipShape(Circle())
                .overlay(Circle().stroke(DesignSystem.hairline, lineWidth: 1))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(accessibilityText)
    }
}

struct CleaveReceiptWatermark: View {
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().frame(width: 8, height: 8)
                Spacer()
                Image(systemName: "person.2.fill").font(.system(size: 8, weight: .bold))
            }
            Capsule().frame(width: 42, height: 4)
            Capsule().frame(width: 28, height: 4)
        }
        .foregroundStyle(color)
        .padding(12)
        .frame(width: 82, height: 68)
        .background(color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(color.opacity(0.11), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

// MARK: - Regional payment handoff branding
extension SettlementMethod {
    var brandBackground: Color {
        switch self {
        case .venmo: return Color(hex: "008CFF")
        case .googlePayUPI: return Color.black
        case .aani: return Color(hex: "064B5B")
        }
    }

    var brandForeground: Color { .white }

    var brandAccent: Color {
        switch self {
        case .venmo, .googlePayUPI: return .white
        case .aani: return Color(hex: "E8B541")
        }
    }
}

struct PaymentBrandIdentity: View {
    let method: SettlementMethod
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 8 : 11) {
            switch method {
            case .venmo:
                Text("venmo")
                    .font(.custom("AvenirNext-Heavy", size: compact ? 18 : 22))
                    .tracking(-0.8)

            case .googlePayUPI:
                GoogleColorMark()
                    .frame(width: compact ? 23 : 28, height: compact ? 23 : 28)
                Text("Google Pay")
                    .font(.custom("AvenirNext-DemiBold", size: compact ? 16 : 19))

            case .aani:
                AaniBrandMark()
                    .stroke(method.brandAccent, style: StrokeStyle(lineWidth: compact ? 2.8 : 3.4, lineCap: .round, lineJoin: .round))
                    .frame(width: compact ? 24 : 30, height: compact ? 24 : 30)
                Text("Aani")
                    .font(.custom("AvenirNext-Heavy", size: compact ? 17 : 20))
            }
        }
        .foregroundStyle(method.brandForeground)
    }
}

struct PaymentBrandButtonLabel: View {
    let method: SettlementMethod
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            PaymentBrandIdentity(method: method, compact: compact)

            Spacer()

            Text("OPEN")
                .font(.custom("AvenirNext-Heavy", size: compact ? 9 : 10))
                .tracking(1.2)
                .opacity(0.72)

            Image(systemName: "arrow.up.right")
                .font(.system(size: compact ? 12 : 14, weight: .black))
        }
        .foregroundStyle(method.brandForeground)
        .padding(.horizontal, compact ? 14 : 18)
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 48 : 56)
        .background(method.brandBackground)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 13 : 17, style: .continuous))
        .shadow(color: method.brandBackground.opacity(0.22), radius: 10, y: 5)
    }
}

private struct GoogleColorMark: View {
    private let colors: [Color] = [
        Color(hex: "4285F4"),
        Color(hex: "EA4335"),
        Color(hex: "FBBC04"),
        Color(hex: "34A853")
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(colors.indices, id: \.self) { index in
                Capsule()
                    .fill(colors[index])
                    .frame(width: 4)
                    .offset(y: index.isMultiple(of: 2) ? -3 : 3)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct AaniBrandMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.14, y: rect.height * 0.60))
        path.addLine(to: CGPoint(x: rect.width * 0.76, y: rect.height * 0.10))
        path.addLine(to: CGPoint(x: rect.width * 0.76, y: rect.height * 0.86))
        path.addLine(to: CGPoint(x: rect.width * 0.12, y: rect.height * 0.35))
        path.addLine(to: CGPoint(x: rect.width * 0.92, y: rect.height * 0.35))
        return path
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
