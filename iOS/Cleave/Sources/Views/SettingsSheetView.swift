import SwiftUI

struct SettingsSheetView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var store: AppStore
    @AppStorage("selectedRegion") private var selectedRegion: String = ""
    @AppStorage(DemoMode.defaultsKey) private var demoModeEnabled = false
    @AppStorage(HapticsManager.defaultsKey) private var hapticsEnabled = true
    @AppStorage("onboardingVersion") private var onboardingVersion = OnboardingVersion.current

    @State private var showingPrivacyPolicy = false
    @State private var showingFAQ = false
    @State private var showingProfileSheet = false
    @State private var showingResetDemoConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeletingAccount = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Settings")
                    .font(DesignSystem.displayFont(29))
                    .foregroundColor(DesignSystem.ink)
                Spacer()
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DesignSystem.ink)
                        .frame(width: 42, height: 42)
                        .background(DesignSystem.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(DesignSystem.hairline, lineWidth: 1))
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 30)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 30) {
                    // Region controls both display currency and payment handoff.
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Region")
                            .font(DesignSystem.labelFont(11))
                            .tracking(1.5)
                            .foregroundColor(DesignSystem.accentOrange)
                            .padding(.horizontal, 30)

                        Text("Currency and settlement method update automatically.")
                            .font(DesignSystem.bodyFont(14))
                            .foregroundColor(DesignSystem.inkMuted)
                            .padding(.horizontal, 30)

                        VStack(spacing: 10) {
                            ForEach(AppRegion.allCases) { region in
                                let isSelected = activeRegion == region
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        RegionManager.shared.select(region)
                                        selectedRegion = region.rawValue
                                        PaymentPreferences.save(
                                            region: region,
                                            venmo: PaymentPreferences.venmoUsername,
                                            upi: PaymentPreferences.upiID
                                        )
                                        syncRegionIfReady(region)
                                    }
                                }) {
                                    HStack(spacing: 14) {
                                        Text(region.flag)
                                            .font(.system(size: 28))

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(region.displayName)
                                                .font(DesignSystem.titleFont(16))
                                            Text("\(region.currency.rawValue) · \(region.settlementMethod.displayName)")
                                                .font(DesignSystem.bodyFont(13))
                                                .opacity(0.65)
                                        }

                                        Spacer()

                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 20, weight: .bold))
                                    }
                                    .foregroundColor(isSelected ? .white : .black.opacity(0.8))
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 14)
                                    .background(isSelected ? DesignSystem.accentNavy : DesignSystem.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.black.opacity(0.08), lineWidth: isSelected ? 0 : 1)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 30)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        settingsSectionLabel("Preferences")

                        VStack(spacing: 1) {
                            HStack(spacing: 13) {
                                settingsIcon("waveform", color: DesignSystem.accentTeal)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Haptic feedback")
                                        .font(DesignSystem.titleFont(15))
                                        .foregroundStyle(DesignSystem.ink)
                                    Text("Feel selections and confirmations")
                                        .font(DesignSystem.bodyFont(12))
                                        .foregroundStyle(DesignSystem.inkMuted)
                                }
                                Spacer()
                                Toggle("", isOn: $hapticsEnabled)
                                    .labelsHidden()
                                    .tint(DesignSystem.accentTeal)
                            }
                            .padding(16)
                            .background(DesignSystem.surface)

                            if !isDemoMode {
                                Button(action: { showingProfileSheet = true }) {
                                    settingsRow(
                                        title: "Payment & profile",
                                        subtitle: "Update how friends pay you",
                                        icon: "person.crop.circle",
                                        color: activeRegion.settlementMethod.brandBackground
                                    )
                                }
                            }

                            Button {
                                onboardingVersion = 0
                                isPresented = false
                            } label: {
                                settingsRow(
                                    title: "Replay onboarding",
                                    subtitle: "See the Cleave walkthrough again",
                                    icon: "sparkles",
                                    color: DesignSystem.accentOrange
                                )
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(DesignSystem.hairline, lineWidth: 1))
                        .padding(.horizontal, 30)
                    }

                    if isDemoMode {
                        VStack(alignment: .leading, spacing: 12) {
                            settingsSectionLabel("Demo Lab")

                            Button {
                                showingResetDemoConfirmation = true
                            } label: {
                                settingsRow(
                                    title: "Reset demo data",
                                    subtitle: "Restore the original sample groups",
                                    icon: "arrow.counterclockwise",
                                    color: DesignSystem.accentOrange
                                )
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(DesignSystem.hairline, lineWidth: 1))
                            .padding(.horizontal, 30)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        settingsSectionLabel("Help & legal")

                        VStack(spacing: 1) {
                            Button(action: { showingPrivacyPolicy = true }) {
                                settingsRow(title: "Privacy Policy", icon: "hand.raised.fill", color: DesignSystem.accentNavy)
                            }
                            Button(action: { showingFAQ = true }) {
                                settingsRow(title: "Help & FAQ", icon: "questionmark.circle.fill", color: DesignSystem.accentTeal)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(DesignSystem.hairline, lineWidth: 1))
                        .padding(.horizontal, 30)
                    }

                    // Account actions
                    Button(action: {
                        if isDemoMode {
                            store.clearForSignOut()
                            demoModeEnabled = false
                            isPresented = false
                            return
                        }
                        Task {
                            do {
                                try await SupabaseManager.shared.signOut()
                                await MainActor.run { isPresented = false }
                            } catch {
                                ErrorManager.shared.showError(error.localizedDescription)
                            }
                        }
                    }) {
                        Text(isDemoMode ? "Exit demo mode" : "Log out")
                            .font(DesignSystem.titleFont(16))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(DesignSystem.accentNavy)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .padding(.horizontal, 30)
                    }

                    if !isDemoMode {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Group {
                                if isDeletingAccount {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Delete Account")
                                }
                            }
                            .font(DesignSystem.titleFont(16))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.red.opacity(0.9))
                            .cornerRadius(16)
                            .padding(.horizontal, 30)
                        }
                        .disabled(isDeletingAccount)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .background(DesignSystem.canvasBeige.edgesIgnoringSafeArea(.all))
        .fullScreenCover(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .fullScreenCover(isPresented: $showingFAQ) {
            FAQView()
        }
        .sheet(isPresented: $showingProfileSheet) {
            ProfileSheetView(isPresented: $showingProfileSheet)
                .presentationDragIndicator(.visible)
                .presentationDetents([.large])
        }
        .alert("Reset the demo?", isPresented: $showingResetDemoConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset") {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    store.loadDemoData()
                }
                HapticsManager.shared.playNotification(type: .success)
                isPresented = false
            }
        } message: {
            Text("This replaces your demo changes with Cleave's original sample groups and receipts.")
        }
        .alert("Delete your account?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Permanently", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("This permanently deletes your profile, owned groups, receipts, assignments, ratings, and uploaded memories. This cannot be undone.")
        }
        .onAppear {
            selectedRegion = RegionManager.shared.migrateLegacyPreferenceIfNeeded().rawValue
        }
    }

    private var activeRegion: AppRegion {
        AppRegion(rawValue: selectedRegion) ?? RegionManager.shared.currentRegion
    }

    private var isDemoMode: Bool {
        DemoMode.isEnabled
    }

    private func syncRegionIfReady(_ region: AppRegion) {
        guard PaymentPreferences.isComplete(
            for: region,
            venmo: PaymentPreferences.venmoUsername,
            upi: PaymentPreferences.upiID
        ) else { return }
        Task {
            do {
                _ = try await CleaveAPI.shared.updatePaymentDetails(
                    region: region,
                    venmoUsername: PaymentPreferences.venmoUsername,
                    upiID: PaymentPreferences.upiID
                )
                PaymentPreferences.markSynced()
            } catch {
                // Keep the local selection and retry when the user saves Profile.
            }
        }
    }

    private func deleteAccount() async {
        guard !isDeletingAccount,
              let userID = SupabaseManager.shared.currentUser?.id else { return }
        isDeletingAccount = true
        do {
            try await CleaveAPI.shared.deleteAccount()
            store.clearForDeletedAccount(userID: userID)
            await SupabaseManager.shared.completeAccountDeletion()
            isPresented = false
        } catch {
            isDeletingAccount = false
            ErrorManager.shared.showError(error.localizedDescription)
        }
    }

    private func settingsSectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(DesignSystem.labelFont(11))
            .tracking(1.5)
            .foregroundStyle(DesignSystem.accentOrange)
            .padding(.horizontal, 30)
    }

    private func settingsIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 34, height: 34)
            .background(color.opacity(0.11))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func settingsRow(
        title: String,
        subtitle: String? = nil,
        icon: String,
        color: Color
    ) -> some View {
        HStack(spacing: 13) {
            settingsIcon(icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.titleFont(15))
                    .foregroundColor(DesignSystem.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(DesignSystem.bodyFont(12))
                        .foregroundStyle(DesignSystem.inkMuted)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(DesignSystem.ink.opacity(0.24))
        }
        .padding(16)
        .background(DesignSystem.surface)
    }
}

struct PrivacyPolicyView: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        ZStack {
            DesignSystem.canvasBeige.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.black.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.horizontal, 30)
                .padding(.top, 20)

                Text("Privacy Policy")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.85))
                    .padding(.horizontal, 30)

                Text("Effective August 11, 2026")
                    .font(DesignSystem.labelFont(12))
                    .foregroundColor(DesignSystem.inkMuted)
                    .padding(.horizontal, 30)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Cleave makes shared expenses simpler without turning receipts into an advertising profile.")
                            .font(DesignSystem.titleFont(16))
                            .foregroundColor(DesignSystem.inkMuted)
                            .lineSpacing(4)

                        policySection(title: "1. Information We Collect", content: "Account information includes your email, username, account identifier, optional profile photo, selected region, and optional Venmo username or UPI ID. Shared-expense information includes groups, invitations, receipts, images, merchants, line items, amounts, currency, assignments, balances, settlement status, ratings, and optional memory photos. Our services also create limited security and diagnostic logs.")

                        policySection(title: "2. How We Use Information", content: "We use this information to authenticate you, synchronize collaborative groups, parse and review receipts, reconcile splits, prepare payment-app handoffs, provide support, secure the service, and diagnose reliability problems. Cleave does not process payments, sell personal information, or track you across other companies’ apps and websites.")

                        policySection(title: "3. Sharing and Providers", content: "Collaborative group members can see group content and payment identifiers needed to pay one another. Supabase provides authentication and database infrastructure. Google Cloud hosts the backend, private media, and operational logs. Google Gemini processes receipt images to extract proposed receipt data. Apple provides Sign in with Apple and App Store services. Payment apps receive details only when you choose to open a handoff.")

                        policySection(title: "4. Storage and Retention", content: "Collaborative records are stored in a protected database. Receipt images, profile photos, and memory photos are kept in private cloud storage and served only after an access check. We retain account content while your account is active. Limited logs and backups may remain temporarily after deletion for security, legal, and disaster-recovery purposes.")

                        policySection(title: "5. Your Choices and Deletion", content: "You can update your profile and payment details, manage camera and photo-library access in iOS Settings, sign out, or permanently delete your account in Cleave Settings. Account deletion removes authentication, database records owned by the account, uploaded media, and account-scoped local data, subject to limited backup retention.")

                        policySection(title: "6. Contact", content: "For access, correction, deletion, support, or privacy questions, email cleave.receipts@gmail.com. We may need to verify your identity before fulfilling a request.")

                        Link("View the full policy online", destination: URL(string: "https://navneetajith-eng.github.io/cleave/privacy/")!)
                            .font(DesignSystem.titleFont(16))
                            .foregroundColor(DesignSystem.accentNavy)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(DesignSystem.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func policySection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(DesignSystem.bgNavy)

            Text(content)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundColor(.black.opacity(0.7))
                .lineSpacing(4)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 5)
    }
}

struct FAQView: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        ZStack {
            DesignSystem.canvasBeige.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.black.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.horizontal, 30)
                .padding(.top, 20)

                Text("FAQ")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.85))
                    .padding(.horizontal, 30)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        faqSection(question: "How does the receipt scanning work?", answer: "We use advanced AI (Google Gemini) to instantly parse the items, prices, tax, and tip from any receipt image you capture.")

                        faqSection(question: "Can I edit an item after scanning?", answer: "Yes! During the assignment phase, you can assign items to individuals. Full manual editing of items is planned for a future update.")

                        faqSection(question: "How is tax and tip calculated?", answer: "Tax and tip are proportionally divided based on the subtotal of the items each person was assigned.")

                        faqSection(question: "Is my data secure?", answer: "Absolutely. Your data is stored securely using Supabase and is only accessible by you and your collaborative group members.")

                        faqSection(question: "How do I settle up?", answer: "Choose your region in Settings. Cleave uses Venmo for the United States, Google Pay (UPI) for India, and Aani for the UAE. Cleave hands the settlement to that app; always verify the recipient and amount there.")

                        faqSection(question: "Does Cleave charge payment fees?", answer: "No. Cleave does not process money and charges no settlement fee. The payment provider, bank, card, or transfer option you choose may still charge its own fee, so review the payment app before confirming.")
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func faqSection(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(DesignSystem.bgNavy)

            Text(answer)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundColor(.black.opacity(0.7))
                .lineSpacing(4)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 5)
    }
}
