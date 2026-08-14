import SwiftUI

struct SettingsSheetView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var store: AppStore
    @Environment(\.openURL) private var openURL
    @AppStorage("selectedRegion") private var selectedRegion: String = ""
    @AppStorage(DemoMode.defaultsKey) private var demoModeEnabled = false
    @AppStorage(HapticsManager.defaultsKey) private var hapticsEnabled = true
    @AppStorage("onboardingVersion") private var onboardingVersion = OnboardingVersion.current
    @AppStorage("onboardingReplayRequested") private var onboardingReplayRequested = false

    @State private var showingProfileSheet = false
    @State private var showingResetDemoConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeletingAccount = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ZStack {
                HStack(spacing: 9) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text("Settings")
                        .font(DesignSystem.displayFont(25))
                        .foregroundColor(DesignSystem.ink)
                }
                HStack {
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

                            if !demoModeEnabled {
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
                                onboardingReplayRequested = true
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

                    if demoModeEnabled {
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
                            Button(action: { openWebsite(AppConfiguration.privacyPolicyURL) }) {
                                settingsRow(
                                    title: "Privacy Policy",
                                    subtitle: "Read the current policy online",
                                    icon: "hand.raised.fill",
                                    color: DesignSystem.accentNavy
                                )
                            }
                            Button(action: { openWebsite(AppConfiguration.supportURL) }) {
                                settingsRow(
                                    title: "Help & FAQ",
                                    subtitle: "Answers for scans, splits, privacy, and payments",
                                    icon: "questionmark.circle.fill",
                                    color: DesignSystem.accentTeal
                                )
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(DesignSystem.hairline, lineWidth: 1))
                        .padding(.horizontal, 30)
                    }

                    // Account actions
                    Button(action: {
                        if demoModeEnabled {
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
                        Text(demoModeEnabled ? "Exit demo mode" : "Log out")
                            .font(DesignSystem.titleFont(16))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(DesignSystem.accentNavy)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .padding(.horizontal, 30)
                    }

                    if !demoModeEnabled {
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
                    upiID: PaymentPreferences.upiID,
                    aaniID: PaymentPreferences.aaniID
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

    private func openWebsite(_ url: URL?) {
        guard let url else {
            ErrorManager.shared.showError("Cleave's support website is temporarily unavailable.")
            return
        }
        openURL(url)
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
