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

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        policySection(title: "1. Information Collection", content: "We collect information you provide directly to us, such as when you create an account, scan receipts, or use our collaborative features. This includes images of receipts and any associated metadata.")

                        policySection(title: "2. Use of Information", content: "We use the information we collect to provide, maintain, and improve our services, particularly to accurately parse and split your receipts.")

                        policySection(title: "3. Data Security", content: "We implement robust security measures, including Row-Level Security on our databases, to ensure your data is protected against unauthorized access.")

                        policySection(title: "4. Third-Party Services", content: "We may use third-party services (like Google Gemini) for processing receipt images. We only share the minimum necessary information with these services.")

                        policySection(title: "5. Your Rights", content: "You have the right to access, correct, or delete your personal data. You can request deletion of your account and associated data through the app settings.")
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
