import SwiftUI
import AuthenticationServices

struct SupabaseConfigurationRequiredView: View {
    var body: some View {
        ZStack {
            DesignSystem.canvasBeige.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundColor(DesignSystem.accentNavy)

                VStack(spacing: 12) {
                    Text("Connect Cleave")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(.black.opacity(0.9))

                    Text("Onboarding is complete. Add the Supabase publishable key to the local configuration, rebuild the app, and Cleave will continue to sign in.")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundColor(.black.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Copy CleaveSecrets.example.xcconfig", systemImage: "1.circle.fill")
                    Label("Set CLEAVE_SUPABASE_ANON_KEY", systemImage: "2.circle.fill")
                    Label("Clean and rebuild the app", systemImage: "3.circle.fill")
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.black.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(Color.white.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Text("Use a publishable or legacy anon key here—never a service-role or secret key.")
                    .font(.caption)
                    .foregroundColor(.black.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .padding(32)
        }
    }
}

struct AuthView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var supabaseManager = SupabaseManager.shared
    var allowsDismiss = true

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showingPasswordReset = false

    var body: some View {
        ZStack {
            // Premium background
            DesignSystem.canvasBeige.ignoresSafeArea()

            // Subtle ambient glows
            Circle()
                .fill(DesignSystem.accentNavy.opacity(0.15))
                .blur(radius: 100)
                .frame(width: 300, height: 300)
                .offset(x: -100, y: -200)

            Circle()
                .fill(DesignSystem.accentSand.opacity(0.1))
                .blur(radius: 100)
                .frame(width: 300, height: 300)
                .offset(x: 100, y: 200)

            VStack(spacing: 30) {
                // Header
                VStack(spacing: 16) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)

                    Text(isSignUp ? "Create Account" : "Welcome Back")
                        .font(.system(size: 36, weight: .light, design: .serif))
                        .foregroundColor(.black)

                    Text(isSignUp ? "Join to create collaborative groups." : "Sign in to sync your groups.")
                        .font(.subheadline)
                        .foregroundColor(.black.opacity(0.6))
                }
                .padding(.bottom, 20)

                // Form Fields
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .font(.system(size: 18))
                        .foregroundColor(.black)
                        .padding()
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        )
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)

                    SecureField("Password", text: $password)
                        .font(.system(size: 18))
                        .foregroundColor(.black)
                        .padding()
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 30)

                if !isSignUp {
                    Button("Forgot password?") {
                        showingPasswordReset = true
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.accentNavy)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 30)
                    .accessibilityHint("Sends a secure password recovery link to your email")
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(DesignSystem.accentTeal)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }

                // Submit Button
                Button(action: {
                    Task {
                        await authenticate()
                    }
                }) {
                    ZStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        } else {
                            Text(isSignUp ? "Sign Up" : "Sign In")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(DesignSystem.accentNavy)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.2), radius: 15, x: 0, y: 5)
                }
                .padding(.horizontal, 30)
                .disabled(isLoading || email.isEmpty || password.isEmpty)

                // Divider
                HStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.2))
                        .frame(height: 1)
                    Text("or")
                        .font(.system(size: 14))
                        .foregroundColor(.black.opacity(0.5))
                        .padding(.horizontal, 10)
                    Rectangle()
                        .fill(Color.black.opacity(0.2))
                        .frame(height: 1)
                }
                .padding(.horizontal, 50)

                // Apple Sign In
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                    let nonce = supabaseManager.generateNonce()
                    request.nonce = nonce
                } onCompletion: { result in
                    Task {
                        await handleAppleSignIn(result: result)
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .cornerRadius(16)
                .padding(.horizontal, 30)

                // Toggle mode
                Button(action: {
                    withAnimation {
                        isSignUp.toggle()
                        errorMessage = nil
                    }
                }) {
                    Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                        .font(.system(size: 14))
                        .foregroundColor(.black.opacity(0.6))
                }
                .padding(.top, 10)
            }
        }
        .overlay(alignment: .topTrailing) {
            if allowsDismiss {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.black.opacity(0.4))
                }
                .padding(20)
                .accessibilityLabel("Close")
            }
        }
        .sheet(isPresented: $showingPasswordReset) {
            PasswordResetRequestView(initialEmail: email)
        }
    }

    @MainActor
    private func authenticate() async {
        isLoading = true
        errorMessage = nil

        do {
            if isSignUp {
                try await supabaseManager.signUp(email: email, password: password)
            } else {
                try await supabaseManager.signIn(email: email, password: password)
            }
            try await bootstrapProfileIfNeeded()
            dismiss()
        } catch {
            ErrorManager.shared.showError(error.localizedDescription)
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    @MainActor
    private func handleAppleSignIn(result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil
        do {
            switch result {
            case .success(let authorization):
                if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                    guard let identityToken = appleIDCredential.identityToken,
                          let idTokenString = String(data: identityToken, encoding: .utf8) else {
                        throw URLError(.cannotDecodeRawData)
                    }

                    try await supabaseManager.signInWithApple(identityToken: idTokenString)
                    try await bootstrapProfileIfNeeded()
                    dismiss()
                }
            case .failure(let error):
                if let asError = error as? ASAuthorizationError, asError.code == .canceled {
                    // User cancelled, do nothing
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        } catch {
            ErrorManager.shared.showError(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func bootstrapProfileIfNeeded() async throws {
        guard let user = supabaseManager.currentUser,
              let email = user.email else { return }
        let suggestedUsername = email.split(separator: "@").first.map(String.init) ?? "member"
        _ = try await CleaveAPI.shared.bootstrapProfile(
            username: suggestedUsername,
            email: email
        )
    }
}

struct PasswordResetRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var supabaseManager = SupabaseManager.shared

    @State private var email: String
    @State private var isLoading = false
    @State private var didSend = false
    @State private var errorMessage: String?

    init(initialEmail: String) {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.canvasBeige.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: didSend ? "envelope.badge.fill" : "lock.rotation")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundColor(DesignSystem.accentNavy)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(didSend ? "Check your email" : "Reset your password")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.black.opacity(0.9))

                        Text(didSend
                             ? "If an account exists for that address, we sent a secure link. Open it on this iPhone to choose a new password."
                             : "Enter the email address for your Cleave account. We’ll send a secure recovery link.")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.black.opacity(0.62))
                            .lineSpacing(4)
                    }

                    if didSend {
                        Button("Done") { dismiss() }
                            .buttonStyle(CleavePrimaryButtonStyle())
                    } else {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 17))
                            .foregroundColor(.black)
                            .padding()
                            .background(Color.white.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundColor(.red)
                                .accessibilityLabel("Error: \(errorMessage)")
                        }

                        Button {
                            Task { await sendRecoveryEmail() }
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Send Recovery Link")
                                }
                            }
                        }
                        .buttonStyle(CleavePrimaryButtonStyle())
                        .disabled(isLoading || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Spacer()
                }
                .padding(30)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @MainActor
    private func sendRecoveryEmail() async {
        isLoading = true
        errorMessage = nil
        do {
            try await supabaseManager.requestPasswordReset(email: email)
            didSend = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct PasswordUpdateView: View {
    @ObservedObject private var supabaseManager = SupabaseManager.shared

    @State private var password = ""
    @State private var confirmation = ""
    @State private var isLoading = false
    @State private var didUpdate = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            DesignSystem.canvasBeige.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: didUpdate ? "checkmark.shield.fill" : "key.fill")
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundColor(DesignSystem.accentNavy)
                        .padding(.top, 42)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(didUpdate ? "Password updated" : "Choose a new password")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundColor(.black.opacity(0.9))

                        Text(didUpdate
                             ? "Your new password is ready. You can continue securely into Cleave."
                             : "Use at least eight characters, including a letter and a number.")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.black.opacity(0.62))
                            .lineSpacing(4)
                    }

                    if didUpdate {
                        Button("Continue to Cleave") {
                            supabaseManager.completePasswordRecovery()
                        }
                        .buttonStyle(CleavePrimaryButtonStyle())
                    } else {
                        VStack(spacing: 14) {
                            SecureField("New password", text: $password)
                                .textContentType(.newPassword)
                            SecureField("Confirm new password", text: $confirmation)
                                .textContentType(.newPassword)
                        }
                        .font(.system(size: 17))
                        .foregroundColor(.black)
                        .padding()
                        .background(Color.white.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundColor(.red)
                                .accessibilityLabel("Error: \(errorMessage)")
                        }

                        Button {
                            Task { await updatePassword() }
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Update Password")
                                }
                            }
                        }
                        .buttonStyle(CleavePrimaryButtonStyle())
                        .disabled(isLoading || password.isEmpty || confirmation.isEmpty)

                        Button("Cancel and Sign Out") {
                            Task { await supabaseManager.cancelPasswordRecovery() }
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.black.opacity(0.6))
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(30)
            }
        }
        .interactiveDismissDisabled()
    }

    @MainActor
    private func updatePassword() async {
        errorMessage = nil
        guard password == confirmation else {
            errorMessage = "The passwords do not match."
            return
        }

        isLoading = true
        do {
            try await supabaseManager.updatePassword(password)
            didUpdate = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct CleavePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(DesignSystem.accentNavy.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
