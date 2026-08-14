import SwiftUI

enum OnboardingVersion {
    static let current = 4
}

enum OnboardingFlow {
    static func steps(isReplay: Bool) -> [Int] {
        isReplay ? [0, 1, 5] : [0, 1, 2, 3, 4, 5]
    }
}

struct OnboardingView: View {
    let isReplay: Bool
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: PaymentField?
    @State private var step = 0
    @State private var direction = 1
    @State private var selectedRegion = RegionManager.shared.currentRegion
    @State private var venmoUsername = PaymentPreferences.venmoUsername
    @State private var upiID = PaymentPreferences.upiID
    @State private var aaniID = PaymentPreferences.aaniID
    @State private var ageBand = AgePreferences.ageBand

    init(isReplay: Bool = false, onComplete: @escaping () -> Void) {
        self.isReplay = isReplay
        self.onComplete = onComplete
    }

    private var stepOrder: [Int] { OnboardingFlow.steps(isReplay: isReplay) }
    private var stepIndex: Int { stepOrder.firstIndex(of: step) ?? 0 }
    private var isLastStep: Bool { stepIndex == stepOrder.count - 1 }

    var body: some View {
        ZStack {
            onboardingBackground

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    Group {
                        switch step {
                        case 0: heroPage
                        case 1: howItWorksPage
                        case 2: regionPage
                        case 3: paymentPage
                        case 4: agePage
                        default: readyPage
                        }
                    }
                    .id(step)
                    .transition(pageTransition)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)

                footer
            }
        }
        .preferredColorScheme(.light)
        .animation(.spring(response: 0.48, dampingFraction: 0.84), value: step)
    }

    private var onboardingBackground: some View {
        GeometryReader { proxy in
            DesignSystem.canvasBeige
                .ignoresSafeArea()

            GroupReceiptMotif(color: DesignSystem.cardNavy)
                .frame(width: 92, height: 122)
                .rotationEffect(.degrees(-13))
                .position(x: proxy.size.width * 0.08, y: proxy.size.height * 0.18)

            GroupReceiptMotif(color: DesignSystem.cardOrange)
                .frame(width: 74, height: 98)
                .rotationEffect(.degrees(12))
                .position(x: proxy.size.width * 0.94, y: proxy.size.height * 0.29)

            GroupReceiptMotif(color: DesignSystem.cardTeal)
                .frame(width: 86, height: 114)
                .rotationEffect(.degrees(9))
                .position(x: proxy.size.width * 0.11, y: proxy.size.height * 0.73)

            GroupReceiptMotif(color: DesignSystem.cardPeach)
                .frame(width: 68, height: 90)
                .rotationEffect(.degrees(-11))
                .position(x: proxy.size.width * 0.92, y: proxy.size.height * 0.84)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 14) {
            if stepIndex > 0 {
                Button {
                    focusedField = nil
                    direction = -1
                    step = stepOrder[stepIndex - 1]
                    HapticsManager.shared.playImpact(style: .light)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(DesignSystem.accentNavy)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.72), in: Circle())
                }
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 40, height: 40)
            }

            HStack(spacing: 6) {
                ForEach(stepOrder.indices, id: \.self) { index in
                    Capsule()
                        .fill(index <= stepIndex ? DesignSystem.accentNavy : Color.black.opacity(0.1))
                        .frame(maxWidth: index == stepIndex ? 34 : 14, maxHeight: 6)
                }
            }

            Spacer()

            Text("\(stepIndex + 1) / \(stepOrder.count)")
                .font(.custom("AvenirNext-DemiBold", size: 12))
                .foregroundStyle(.black.opacity(0.45))
                .frame(width: 40)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var heroPage: some View {
        VStack(spacing: 22) {
            ReceiptSplitAnimation(reduceMotion: reduceMotion)
                .frame(height: 300)
                .accessibilityHidden(true)

            HStack(spacing: 9) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("CLEAVE")
                    .font(DesignSystem.labelFont(12))
                    .tracking(2.4)
                    .foregroundStyle(DesignSystem.accentNavy)
            }

            VStack(spacing: 6) {
                Text("Cleave the debt.")
                    .font(.custom("AvenirNext-Heavy", size: 39))
                    .foregroundStyle(DesignSystem.accentNavy)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)

                Text("Keep the Ties.")
                    .font(.custom("AvenirNext-DemiBold", size: 31))
                    .foregroundStyle(DesignSystem.accentOrange)

                Text("Scan. Split. Settle.")
                    .onboardingBody()
            }
        }
        .padding(.top, 8)
    }

    private var howItWorksPage: some View {
        VStack(alignment: .leading, spacing: 26) {
            pageHeading(
                eyebrow: "HOW IT WORKS",
                title: "One receipt.\nThree simple moves.",
                body: ""
            )

            VStack(spacing: 12) {
                guideCard(number: "01", icon: "viewfinder", title: "Scan", detail: "Capture every item.", color: DesignSystem.accentOrange)
                guideCard(number: "02", icon: "person.2.fill", title: "Split", detail: "Tap who shared what.", color: DesignSystem.accentTeal)
                guideCard(number: "03", icon: "arrow.up.right.circle.fill", title: "Settle", detail: "Open the right payment app.", color: DesignSystem.accentNavy)
            }
        }
        .padding(.top, 28)
    }

    private var regionPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            pageHeading(
                eyebrow: "YOUR REGION",
                title: "Where do you split?",
                body: "Currency and payment app update together."
            )

            VStack(spacing: 12) {
                ForEach(AppRegion.allCases) { region in
                    Button {
                        selectedRegion = region
                        focusedField = nil
                        HapticsManager.shared.playImpact(style: .light)
                    } label: {
                        HStack(spacing: 16) {
                            Text(region.flag)
                                .font(.system(size: 34))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(region.displayName)
                                    .font(.custom("AvenirNext-Heavy", size: 17))
                                Text("\(region.currency.rawValue)  •  \(region.settlementMethod.displayName)")
                                    .font(.custom("AvenirNext-DemiBold", size: 13))
                                    .foregroundStyle(.black.opacity(0.48))
                            }

                            Spacer()

                            Image(systemName: selectedRegion == region ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(selectedRegion == region ? DesignSystem.accentTeal : .black.opacity(0.16))
                        }
                        .padding(18)
                        .background(selectedRegion == region ? Color.white : Color.white.opacity(0.55))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(selectedRegion == region ? DesignSystem.accentTeal : .clear, lineWidth: 2)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(selectedRegion == region ? 0.08 : 0.03), radius: 14, y: 7)
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .foregroundStyle(DesignSystem.accentNavy)
                }
            }
        }
        .padding(.top, 28)
    }

    private var paymentPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            pageHeading(
                eyebrow: "GET PAID",
                title: paymentTitle,
                body: paymentBody
            )

            paymentMethodCard

            switch selectedRegion {
            case .unitedStates:
                paymentField(
                    label: "VENMO USERNAME",
                    placeholder: "your-venmo",
                    text: $venmoUsername,
                    field: .venmo,
                    prefix: "@",
                    isValid: venmoUsername.isEmpty || PaymentPreferences.isValidVenmo(venmoUsername),
                    error: "Use 2–64 letters, numbers, dashes, or underscores."
                )
            case .india:
                paymentField(
                    label: "UPI ID",
                    placeholder: "name@bank",
                    text: $upiID,
                    field: .upi,
                    prefix: nil,
                    isValid: upiID.isEmpty || PaymentPreferences.isValidUPI(upiID),
                    error: "Enter a UPI ID such as name@bank."
                )
            case .unitedArabEmirates:
                paymentField(
                    label: "AANI ID OR MOBILE",
                    placeholder: "+971… or your Aani ID",
                    text: $aaniID,
                    field: .aani,
                    prefix: nil,
                    isValid: aaniID.isEmpty || PaymentPreferences.isValidAani(aaniID),
                    error: "Enter a valid Aani ID or mobile number."
                )
            }

            Label("Cleave never moves money or stores bank credentials.", systemImage: "lock.fill")
                .font(.custom("AvenirNext-DemiBold", size: 12))
                .foregroundStyle(.black.opacity(0.42))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.top, 28)
    }

    private var agePage: some View {
        VStack(alignment: .leading, spacing: 24) {
            pageHeading(
                eyebrow: "AGE RANGE",
                title: "Which range are you in?",
                body: "We ask for an age range—not your birthday—to support age-appropriate access while collecting less personal data."
            )

            VStack(spacing: 12) {
                ForEach(AgeBand.allCases) { band in
                    Button {
                        ageBand = band
                        HapticsManager.shared.playImpact(style: .light)
                    } label: {
                        HStack {
                            Text(band.displayName)
                                .font(.custom("AvenirNext-Heavy", size: 17))
                            Spacer()
                            Image(systemName: ageBand == band ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 23, weight: .bold))
                                .foregroundStyle(ageBand == band ? DesignSystem.accentTeal : .black.opacity(0.18))
                        }
                        .foregroundStyle(DesignSystem.accentNavy)
                        .padding(18)
                        .background(.white.opacity(ageBand == band ? 1 : 0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(PressScaleButtonStyle())
                }
            }

            if ageBand == .under13 {
                Label("Cleave's internal beta currently supports people age 13 and older.", systemImage: "info.circle.fill")
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .foregroundStyle(DesignSystem.accentOrange)
            }
        }
        .padding(.top, 28)
    }

    private var readyPage: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 24)

            ZStack {
                Circle()
                    .fill(DesignSystem.accentTeal.opacity(0.13))
                    .frame(width: 190, height: 190)
                Circle()
                    .fill(DesignSystem.accentNavy)
                    .frame(width: 118, height: 118)
                Image(systemName: "checkmark")
                    .font(.system(size: 54, weight: .black))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 10) {
                Text(isReplay ? "You’re all caught up." : "You’re ready to Cleave.")
                    .font(.custom("AvenirNext-Heavy", size: 36))
                    .foregroundStyle(DesignSystem.accentNavy)
                    .multilineTextAlignment(.center)
                Text(isReplay ? "Your account details stayed exactly as you left them." : "Split here. Settle in \(selectedRegion.settlementMethod.displayName).")
                    .onboardingBody()
            }

            HStack(spacing: 14) {
                summaryPill(value: selectedRegion.flag, label: selectedRegion.displayName)
                summaryPill(value: selectedRegion.currency.rawValue, label: selectedRegion.settlementMethod.displayName)
            }

            Spacer(minLength: 20)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                advance()
            } label: {
                HStack(spacing: 10) {
                    Text(isLastStep ? (isReplay ? "Back to Cleave" : "Start splitting") : continueLabel)
                    Image(systemName: isLastStep ? "sparkles" : "arrow.right")
                }
                .font(.custom("AvenirNext-Heavy", size: 17))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(canContinue ? DesignSystem.accentNavy : Color.black.opacity(0.18), in: Capsule())
                .shadow(color: canContinue ? DesignSystem.accentNavy.opacity(0.22) : .clear, radius: 15, y: 7)
            }
            .disabled(!canContinue)
            .buttonStyle(PressScaleButtonStyle())

            if (step == 3 || step == 4) && !canContinue {
                Text(step == 4 ? "Choose an eligible age range to continue" : paymentRequirementMessage)
                    .font(.custom("AvenirNext-DemiBold", size: 12))
                    .foregroundStyle(.black.opacity(0.45))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private var canContinue: Bool {
        if step == 3 {
            let regionComplete = PaymentPreferences.isComplete(
                for: selectedRegion,
                venmo: venmoUsername,
                upi: upiID
            )
            let aaniComplete = selectedRegion != .unitedArabEmirates
                || aaniID.isEmpty
                || PaymentPreferences.isValidAani(aaniID)
            return regionComplete && aaniComplete
        }
        if step == 4 {
            return ageBand != nil && ageBand != .under13
        }
        return true
    }

    private var continueLabel: String {
        switch step {
        case 0: return "Show me how"
        case 2: return "Use \(selectedRegion.displayName)"
        case 3: return selectedRegion == .unitedArabEmirates ? "Looks good" : "Save payment method"
        case 4: return "Confirm age range"
        default: return "Continue"
        }
    }

    private var paymentTitle: String {
        switch selectedRegion {
        case .unitedStates: return "Your Venmo"
        case .india: return "Your UPI ID"
        case .unitedArabEmirates: return "Your Aani"
        }
    }

    private var paymentBody: String {
        switch selectedRegion {
        case .unitedStates: return "Used to prepare a Venmo handoff."
        case .india: return "Any valid UPI ID works with Google Pay."
        case .unitedArabEmirates: return "Add an Aani ID if you want friends to find the right recipient faster."
        }
    }

    private var paymentRequirementMessage: String {
        switch selectedRegion {
        case .unitedStates: return "Add your Venmo username to continue"
        case .india: return "Add your UPI ID to continue"
        case .unitedArabEmirates: return "Check the Aani ID if you entered one"
        }
    }

    private var paymentMethodCard: some View {
        HStack(spacing: 15) {
            PaymentBrandIdentity(method: selectedRegion.settlementMethod)
            Spacer()

            Text("\(selectedRegion.flag)  \(selectedRegion.currency.rawValue)")
                .font(.custom("AvenirNext-Heavy", size: 11))
                .foregroundStyle(selectedRegion.settlementMethod.brandAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 18)
        .frame(height: 72)
        .background(selectedRegion.settlementMethod.brandBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: selectedRegion.settlementMethod.brandBackground.opacity(0.2), radius: 14, y: 7)
    }

    private func pageHeading(eyebrow: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(eyebrow)
                .font(.custom("AvenirNext-Heavy", size: 12))
                .tracking(1.6)
                .foregroundStyle(DesignSystem.accentOrange)
            Text(title)
                .font(.custom("AvenirNext-Heavy", size: 36))
                .foregroundStyle(DesignSystem.accentNavy)
                .fixedSize(horizontal: false, vertical: true)
            if !body.isEmpty {
                Text(body)
                    .font(.custom("AvenirNext-Medium", size: 16))
                    .foregroundStyle(.black.opacity(0.56))
                    .lineSpacing(3)
            }
        }
    }

    private func guideCard(number: String, icon: String, title: String, detail: String, color: Color) -> some View {
        HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(color)
                    .frame(width: 58, height: 58)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(number)  \(title.uppercased())")
                    .font(.custom("AvenirNext-Heavy", size: 13))
                    .foregroundStyle(DesignSystem.accentNavy)
                Text(detail)
                    .font(.custom("AvenirNext-Medium", size: 15))
                    .foregroundStyle(.black.opacity(0.54))
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func paymentField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        field: PaymentField,
        prefix: String?,
        isValid: Bool,
        error: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.custom("AvenirNext-Heavy", size: 12))
                .tracking(1.2)
                .foregroundStyle(.black.opacity(0.45))

            HStack(spacing: 7) {
                if let prefix {
                    Text(prefix)
                        .font(.custom("AvenirNext-Heavy", size: 18))
                        .foregroundStyle(.black.opacity(0.35))
                }
                TextField(
                    placeholder,
                    text: text,
                    prompt: Text(placeholder).foregroundStyle(DesignSystem.ink.opacity(0.34))
                )
                    .font(.custom("AvenirNext-DemiBold", size: 17))
                    .foregroundStyle(DesignSystem.ink)
                    .tint(DesignSystem.accentTeal)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(field == .upi ? .emailAddress : .asciiCapable)
                    .focused($focusedField, equals: field)
                    .submitLabel(.done)
            }
            .padding(17)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isValid ? DesignSystem.accentTeal.opacity(0.55) : DesignSystem.accentOrange, lineWidth: focusedField == field ? 2 : 1)
            }

            if !isValid {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.custom("AvenirNext-DemiBold", size: 12))
                    .foregroundStyle(DesignSystem.accentOrange)
            }
        }
    }

    private func summaryPill(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.custom("AvenirNext-Heavy", size: value.count <= 3 ? 27 : 17))
                .foregroundStyle(DesignSystem.accentNavy)
            Text(label)
                .font(.custom("AvenirNext-DemiBold", size: 11))
                .foregroundStyle(.black.opacity(0.46))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 82)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func advance() {
        guard canContinue else { return }
        focusedField = nil
        HapticsManager.shared.playImpact(style: isLastStep ? .medium : .light)

        if !isLastStep {
            direction = 1
            step = stepOrder[stepIndex + 1]
        } else {
            if !isReplay {
                PaymentPreferences.save(region: selectedRegion, venmo: venmoUsername, upi: upiID, aani: aaniID)
                AgePreferences.ageBand = ageBand
            }
            onComplete()
        }
    }
}

private enum PaymentField: Hashable {
    case venmo
    case upi
    case aani
}

private struct ReceiptSplitAnimation: View {
    let reduceMotion: Bool
    @State private var expanded = false

    private let colors: [Color] = [
        DesignSystem.cardSand,
        DesignSystem.cardPeach,
        DesignSystem.cardOrange,
        DesignSystem.cardTeal,
        DesignSystem.cardNavy
    ]

    var body: some View {
        ZStack {
            Capsule()
                .fill(DesignSystem.accentNavy.opacity(0.12))
                .frame(width: expanded ? 265 : 145, height: 32)
                .blur(radius: 10)
                .offset(y: 105)

            ForEach(colors.indices, id: \.self) { index in
                ReceiptSlip(color: colors[index], index: index)
                    .frame(width: 118, height: 160)
                    .rotationEffect(.degrees(expanded ? Double(index - 2) * 6.5 : Double(index - 2) * 0.8))
                    .offset(
                        x: expanded ? CGFloat(index - 2) * 47 : CGFloat(index - 2) * 4,
                        y: expanded ? CGFloat(abs(index - 2)) * 12 : CGFloat(index) * 4
                    )
                    .scaleEffect(expanded ? 1 : 0.94)
                    .zIndex(Double(index))
                    .shadow(color: .black.opacity(expanded ? 0.15 : 0.09), radius: 14, y: 9)
            }

            Image(systemName: "person.3.fill")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(DesignSystem.accentNavy, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 3))
                .scaleEffect(expanded ? 1 : 0.72)
                .opacity(expanded ? 1 : 0)
                .offset(y: 102)
                .zIndex(10)
        }
        .onAppear {
            guard !reduceMotion else {
                expanded = true
                return
            }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                expanded = true
            }
        }
    }
}

private struct ReceiptSlip: View {
    let color: Color
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("RECEIPT")
                    .font(.custom("AvenirNext-Heavy", size: 8))
                    .tracking(1.2)
                Spacer()
                Image(systemName: index.isMultiple(of: 2) ? "person.2.fill" : "person.fill")
                    .font(.system(size: 10, weight: .bold))
            }
            .opacity(0.68)

            Capsule().frame(width: 66, height: 7)
            Capsule().frame(width: 45, height: 7)
            Divider().overlay(.white.opacity(0.38))

            HStack(spacing: 5) {
                Circle().frame(width: 7, height: 7)
                Capsule().frame(height: 6)
            }
            HStack(spacing: 5) {
                Circle().frame(width: 7, height: 7)
                Capsule().frame(width: 48, height: 6)
            }
        }
        .foregroundStyle(color == DesignSystem.cardSand || color == DesignSystem.cardPeach ? DesignSystem.accentNavy.opacity(0.72) : Color.white.opacity(0.86))
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color)
        .clipShape(OnboardingReceiptShape())
    }
}

private struct GroupReceiptMotif: View {
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Capsule().frame(width: 34, height: 6)
                Spacer()
                Image(systemName: "person.2.fill")
                    .font(.system(size: 10, weight: .bold))
            }
            Capsule().frame(width: 50, height: 7)
            Capsule().frame(width: 36, height: 7)
            Divider()
            Capsule().frame(height: 6)
        }
        .foregroundStyle(color)
        .padding(12)
        .background(color.opacity(0.12))
        .clipShape(OnboardingReceiptShape())
        .opacity(0.20)
    }
}

private struct OnboardingReceiptShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius: CGFloat = min(16, rect.width * 0.16)
        let toothHeight: CGFloat = min(10, rect.height * 0.08)
        let toothCount = max(5, Int(rect.width / 16))
        let toothWidth = rect.width / CGFloat(toothCount)

        path.move(to: CGPoint(x: 0, y: radius))
        path.addArc(center: CGPoint(x: radius, y: radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: rect.width - radius, y: 0))
        path.addArc(center: CGPoint(x: rect.width - radius, y: radius), radius: radius, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - toothHeight))

        for index in 0..<toothCount {
            let right = rect.width - CGFloat(index) * toothWidth
            path.addLine(to: CGPoint(x: right - toothWidth * 0.5, y: rect.height))
            path.addLine(to: CGPoint(x: right - toothWidth, y: rect.height - toothHeight))
        }

        path.addLine(to: CGPoint(x: 0, y: radius))
        path.closeSubpath()
        return path
    }
}

private extension View {
    func onboardingBody() -> some View {
        font(.custom("AvenirNext-Medium", size: 17))
            .foregroundStyle(.black.opacity(0.56))
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .padding(.horizontal, 8)
    }
}
