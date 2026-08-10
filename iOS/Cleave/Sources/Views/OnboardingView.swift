import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var currentPage = 0

    let pages = [
        OnboardingPage(title: "Welcome to Cleave", message: "The most beautiful way to split receipts with your friends.", iconName: "AppLogo", isSystemImage: false),
        OnboardingPage(title: "Scan Magic", message: "Automatically extract items, tax, and tip from any receipt in seconds.", iconName: "camera.viewfinder", isSystemImage: true),
        OnboardingPage(title: "Settle Up", message: "Instantly calculate who owes what and pay via Venmo.", iconName: "dollarsign.arrow.circlepath", isSystemImage: true)
    ]

    var body: some View {
        ZStack {
            DesignSystem.canvasBeige.ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        completeOnboarding()
                    }) {
                        Text("Skip")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(Color.black.opacity(0.4))
                    }
                    .padding()
                }

                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        VStack(spacing: 30) {
                            Spacer()

                            ZStack {
                                Circle()
                                    .fill(DesignSystem.accentTeal.opacity(0.1))
                                    .frame(width: 200, height: 200)

                                if pages[index].isSystemImage {
                                    Image(systemName: pages[index].iconName)
                                        .font(.system(size: 80, weight: .ultraLight))
                                        .foregroundColor(DesignSystem.accentNavy)
                                } else {
                                    Image(pages[index].iconName)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 120, height: 120)
                                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                                }
                            }

                            VStack(spacing: 16) {
                                Text(pages[index].title)
                                    .font(.system(size: 32, weight: .black, design: .rounded))
                                    .foregroundColor(.black.opacity(0.9))

                                Text(pages[index].message)
                                    .font(.system(size: 18, weight: .medium, design: .rounded))
                                    .foregroundColor(.black.opacity(0.6))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }

                            Spacer()
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
                .onAppear {
                    setupPageControlAppearance()
                }

                Button(action: {
                    HapticsManager.shared.playImpact(style: .light)
                    if currentPage < pages.count - 1 {
                        withAnimation {
                            currentPage += 1
                        }
                    } else {
                        completeOnboarding()
                    }
                }) {
                    Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(DesignSystem.accentNavy)
                        .clipShape(Capsule())
                        .shadow(color: DesignSystem.accentNavy.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
    }

    private func completeOnboarding() {
        HapticsManager.shared.playImpact(style: .medium)
        withAnimation {
            onComplete()
        }
    }

    private func setupPageControlAppearance() {
        UIPageControl.appearance().currentPageIndicatorTintColor = UIColor(DesignSystem.accentNavy)
        UIPageControl.appearance().pageIndicatorTintColor = UIColor.black.withAlphaComponent(0.1)
    }
}

struct OnboardingPage {
    let title: String
    let message: String
    let iconName: String
    let isSystemImage: Bool
}
