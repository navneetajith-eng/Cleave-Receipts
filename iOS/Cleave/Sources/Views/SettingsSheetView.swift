import SwiftUI

struct SettingsSheetView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var store: AppStore
    @AppStorage("selectedCurrency") private var selectedCurrency: String = Currency.usd.rawValue

    @State private var showingPrivacyPolicy = false
    @State private var showingFAQ = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeletingAccount = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Settings")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.85))
                Spacer()
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color.black.opacity(0.3))
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 30)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 30) {
                    // Currency Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Currency / Region")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.black.opacity(0.5))
                            .padding(.horizontal, 30)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Currency.allCases) { currency in
                                    let isSelected = selectedCurrency == currency.rawValue
                                    Button(action: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            selectedCurrency = currency.rawValue
                                        }
                                    }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: currency.iconName)
                                                .foregroundColor(isSelected ? .white : .black)
                                            Text(currency.displayName)
                                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                                .foregroundColor(isSelected ? .white : .black)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(isSelected ? Color.black.opacity(0.85) : Color.white)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.black.opacity(0.1), lineWidth: isSelected ? 0 : 1)
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, 30)
                        }
                    }

                    // Future sections placeholder
                    VStack(alignment: .leading, spacing: 12) {
                        Text("More")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.black.opacity(0.5))
                            .padding(.horizontal, 30)

                        VStack(spacing: 1) {
                            Button(action: { showingPrivacyPolicy = true }) {
                                settingsRow(title: "Privacy Policy")
                            }
                            Button(action: { showingFAQ = true }) {
                                settingsRow(title: "FAQ")
                            }
                        }
                        .background(Color.white)
                        .cornerRadius(16)
                        .padding(.horizontal, 30)
                    }

                    // Account actions
                    Button(action: {
                        Task {
                            do {
                                try await SupabaseManager.shared.signOut()
                                await MainActor.run { isPresented = false }
                            } catch {
                                ErrorManager.shared.showError(error.localizedDescription)
                            }
                        }
                    }) {
                        Text("Log Out")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.black.opacity(0.85))
                            .cornerRadius(16)
                            .padding(.horizontal, 30)
                    }

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
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.red.opacity(0.9))
                        .cornerRadius(16)
                        .padding(.horizontal, 30)
                    }
                    .disabled(isDeletingAccount)
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
        .alert("Delete your account?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Permanently", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("This permanently deletes your profile, owned groups, receipts, assignments, ratings, and uploaded memories. This cannot be undone.")
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

    private func settingsRow(title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.black)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color.black.opacity(0.3))
        }
        .padding()
        .background(Color.white)
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
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.black.opacity(0.5))
                    .padding(.horizontal, 30)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Cleave makes shared expenses simpler without turning your receipts into an advertising profile. This policy describes the Cleave iOS app, website, and related services.")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.black.opacity(0.72))
                            .lineSpacing(4)

                        policySection(
                            title: "1. Information We Collect",
                            content: "Account and profile information includes your email address, username, account identifier, and optional profile photo. Collaborative information includes group names, membership, invitations, inbox activity, and the people you split with. Receipt and purchase information includes receipt images, merchants, line items, amounts, tax, tip, discounts, assignments, balances, settlements, ratings, and optional memory photos. Our online services also generate security and service logs, including request identifiers, IP addresses, timestamps, and error details."
                        )

                        policySection(
                            title: "2. How We Use Information",
                            content: "We use information to authenticate you, operate local and collaborative groups, parse receipts, calculate and reconcile splits, synchronize devices, deliver group activity, provide support, secure the service, diagnose errors, and improve reliability. We do not sell personal information, use it for targeted advertising, or track you across other companies’ apps and websites."
                        )

                        policySection(
                            title: "3. Sharing and Service Providers",
                            content: "Members can see information shared with their collaborative group. Supabase provides authentication and database infrastructure. Google Cloud hosts the backend, private media, and operational logs. Google Gemini receives receipt images and parsing instructions. Apple processes Sign in with Apple and App Store services. We may also disclose information when required by law or needed to protect people or the service."
                        )

                        policySection(
                            title: "4. Storage, Security, and Retention",
                            content: "Collaborative records are stored in a protected database. Receipt images, profile photos, and memory photos are held in private cloud storage and returned only after an access check. Cleave uses encrypted network connections and access controls. We retain account content while your account is active or as needed to operate the service. Logs and backups may remain for a limited period after deletion or when required for legal, security, fraud-prevention, or dispute-resolution purposes."
                        )

                        policySection(
                            title: "5. Your Choices and Deletion",
                            content: "You can update your username and profile photo, manage camera and photo-library access in iOS Settings, and sign out at any time. Settings → Delete Account permanently removes your authentication account, profile, owned groups and associated receipts, assignments, ratings, uploaded media, and account-scoped local cache. Content belonging to other users may remain where their rights or records require it."
                        )

                        policySection(
                            title: "6. Children and International Processing",
                            content: "Cleave is not directed to children under 13, and we do not knowingly collect their personal information. Our providers may process information in countries with different data-protection laws and use safeguards appropriate to the service and applicable law."
                        )

                        policySection(
                            title: "7. Changes and Contact",
                            content: "We may update this policy as Cleave changes and will post the revised effective date. For access, correction, deletion, support, or privacy questions, email cleave.receipts@gmail.com. We may need to verify your identity before fulfilling a request."
                        )

                        Link(
                            "View the full policy online",
                            destination: URL(string: "https://navneetajith-eng.github.io/cleave/privacy/")!
                        )
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.accentNavy)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
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

                        faqSection(question: "How do I settle up?", answer: "After calculating balances, you can tap 'Settle via Venmo' on any individual's balance card to open Venmo pre-filled with the amount and description.")
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
