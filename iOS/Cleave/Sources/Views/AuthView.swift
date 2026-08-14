import SwiftUI
import AuthenticationServices

struct SupabaseConfigurationRequiredView: View {
    var onEnterDemo: (() -> Void)? = nil

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

                #if DEBUG
                if let onEnterDemo {
                    Button(action: onEnterDemo) {
                        Label("Explore with demo data", systemImage: "flask.fill")
                            .font(DesignSystem.titleFont(17))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(DesignSystem.accentNavy, in: Capsule())
                    }
                }
                #endif
            }
            .padding(32)
        }
    }
}

struct AuthView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var supabaseManager = SupabaseManager.shared
    var allowsDismiss = true
    var onEnterDemo: (() -> Void)? = nil

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            DesignSystem.canvasBeige.ignoresSafeArea()

            CleaveAuthReceiptMotif(color: DesignSystem.cardOrange)
                .frame(width: 94, height: 126)
                .rotationEffect(.degrees(12))
                .offset(x: 174, y: -330)
                .opacity(0.82)

            CleaveAuthReceiptMotif(color: DesignSystem.cardTeal)
                .frame(width: 82, height: 110)
                .rotationEffect(.degrees(-12))
                .offset(x: -178, y: 330)
                .opacity(0.72)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    CleaveAuthBrandMark()
                        .padding(.top, 52)

                    VStack(spacing: 8) {
                        Text(isSignUp ? "JOIN CLEAVE" : "WELCOME BACK")
                            .font(DesignSystem.labelFont(11))
                            .tracking(2)
                            .foregroundStyle(DesignSystem.accentOrange)
                        Text(isSignUp ? "Create your account." : "Pick up where you left off.")
                            .font(DesignSystem.displayFont(34))
                            .foregroundStyle(DesignSystem.ink)
                            .multilineTextAlignment(.center)
                        Text(isSignUp ? "Make a group, scan once, settle clearly." : "Your groups and receipts will sync after sign in.")
                            .font(DesignSystem.bodyFont(15))
                            .foregroundStyle(DesignSystem.inkMuted)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 14) {
                        authField(icon: "envelope.fill", title: "Email") {
                            TextField(
                                "Email",
                                text: $email,
                                prompt: Text("you@example.com").foregroundStyle(DesignSystem.ink.opacity(0.34))
                            )
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                        }

                        authField(icon: "lock.fill", title: "Password") {
                            SecureField(
                                "Password",
                                text: $password,
                                prompt: Text("Password").foregroundStyle(DesignSystem.ink.opacity(0.34))
                            )
                            .textContentType(isSignUp ? .newPassword : .password)
                        }

                        if let error = errorMessage {
                            Label(error, systemImage: "exclamationmark.circle.fill")
                                .font(DesignSystem.bodyFont(13))
                                .foregroundStyle(DesignSystem.accentOrange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task { await authenticate() }
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    HStack {
                                        Text(isSignUp ? "Create account" : "Sign in")
                                        Spacer()
                                        Image(systemName: "arrow.right")
                                    }
                                }
                            }
                            .font(DesignSystem.titleFont(17))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .padding(.horizontal, 20)
                            .background(DesignSystem.accentNavy, in: Capsule())
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .disabled(isLoading || email.isEmpty || password.isEmpty)
                        .opacity(email.isEmpty || password.isEmpty ? 0.48 : 1)

                        HStack(spacing: 12) {
                            Rectangle().fill(DesignSystem.hairline).frame(height: 1)
                            Text("OR").font(DesignSystem.labelFont(10)).foregroundStyle(DesignSystem.inkMuted)
                            Rectangle().fill(DesignSystem.hairline).frame(height: 1)
                        }

                        SignInWithAppleButton(.continue) { request in
                            request.requestedScopes = [.fullName, .email]
                            let nonce = supabaseManager.generateNonce()
                            request.nonce = nonce
                        } onCompletion: { result in
                            Task { await handleAppleSignIn(result: result) }
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 52)
                        .clipShape(Capsule())
                    }
                    .padding(20)
                    .background(DesignSystem.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26).stroke(DesignSystem.hairline, lineWidth: 1))

                #if DEBUG
                if let onEnterDemo {
                    Button(action: onEnterDemo) {
                        Label("Explore with demo data", systemImage: "flask.fill")
                            .font(DesignSystem.titleFont(17))
                            .foregroundStyle(DesignSystem.accentNavy)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(DesignSystem.accentNavy.opacity(0.18), lineWidth: 1)
                            }
                    }
                    .accessibilityHint("Opens local sample groups without signing in")
                }
                #endif

                Button {
                    withAnimation {
                        isSignUp.toggle()
                        errorMessage = nil
                    }
                } label: {
                    Text(isSignUp ? "Already have an account?  Sign in" : "New to Cleave?  Create an account")
                        .font(DesignSystem.titleFont(14))
                        .foregroundStyle(DesignSystem.accentNavy)
                }
                .padding(.bottom, 28)
            }
            .padding(.horizontal, 24)
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
        .preferredColorScheme(.light)
    }

    private func authField<Field: View>(
        icon: String,
        title: String,
        @ViewBuilder field: () -> Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title.uppercased(), systemImage: icon)
                .font(DesignSystem.labelFont(10))
                .tracking(1.2)
                .foregroundStyle(DesignSystem.inkMuted)
            field()
                .font(DesignSystem.bodyFont(16))
                .foregroundStyle(DesignSystem.ink)
                .tint(DesignSystem.accentTeal)
                .padding(.horizontal, 15)
                .frame(height: 52)
                .background(DesignSystem.fieldSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
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
            email: email,
            ageBand: AgePreferences.ageBand
        )
        do {
            _ = try await CleaveAPI.shared.updatePaymentDetails(
                region: RegionManager.shared.currentRegion,
                venmoUsername: PaymentPreferences.venmoUsername,
                upiID: PaymentPreferences.upiID,
                aaniID: PaymentPreferences.aaniID
            )
            PaymentPreferences.markSynced()
        } catch {
            // Authentication and receipt splitting remain available. The local
            // values stay marked for a later retry from Profile.
            print("Payment preference sync deferred: \(error.localizedDescription)")
        }
    }
}

private struct CleaveAuthBrandMark: View {
    var body: some View {
        HStack(spacing: 13) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: DesignSystem.accentNavy.opacity(0.18), radius: 12, y: 7)

            VStack(alignment: .leading, spacing: 0) {
                Text("CLEAVE")
                    .font(DesignSystem.displayFont(25))
                    .tracking(1.4)
                    .foregroundStyle(DesignSystem.accentNavy)
                Text("SCAN · SPLIT · SETTLE")
                    .font(DesignSystem.labelFont(8))
                    .tracking(1.1)
                    .foregroundStyle(DesignSystem.accentTeal)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cleave")
    }
}

private struct CleaveAuthReceiptMotif: View {
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Capsule().frame(width: 38, height: 6)
            Capsule().frame(width: 54, height: 6)
            Capsule().frame(width: 44, height: 6)
            Spacer(minLength: 4)
            HStack(spacing: 5) {
                Circle().frame(width: 7, height: 7)
                Circle().frame(width: 7, height: 7)
                Circle().frame(width: 7, height: 7)
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(16)
        .background(color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: color.opacity(0.2), radius: 12, y: 7)
        .accessibilityHidden(true)
    }
}
