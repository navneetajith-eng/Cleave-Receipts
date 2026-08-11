import AuthenticationServices
import CryptoKit
import Foundation
import Supabase

@MainActor
final class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()
    static let passwordRecoveryURL = URL(string: "cleave://auth-callback")!

    let client: SupabaseClient
    @Published private(set) var currentUser: User?
    @Published private(set) var hasCheckedSession = false
    @Published private(set) var isPasswordRecovery = false

    var currentNonce: String?
    private var authStateTask: Task<Void, Never>?

    private init() {
        let url = AppConfiguration.supabaseURL ?? URL(string: "https://configuration.invalid")!
        let key = AppConfiguration.supabaseAnonKey ?? "CONFIGURATION_REQUIRED"
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: .init(redirectToURL: Self.passwordRecoveryURL)
            )
        )
    }

    func checkSession() async {
        startObservingAuthState()
        defer { hasCheckedSession = true }
        guard AppConfiguration.supabaseURL != nil,
              AppConfiguration.supabaseAnonKey != nil else {
            currentUser = nil
            return
        }
        do {
            currentUser = try await client.auth.session.user
        } catch {
            currentUser = nil
        }
    }

    func startObservingAuthState() {
        guard authStateTask == nil else { return }
        authStateTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in client.auth.authStateChanges {
                guard !Task.isCancelled else { return }
                applyAuthState(event: event, session: session)
            }
        }
    }

    private func applyAuthState(event: AuthChangeEvent, session: Session?) {
        switch event {
        case .passwordRecovery:
            currentUser = session?.user
            isPasswordRecovery = true
        case .signedOut, .userDeleted:
            currentUser = nil
            isPasswordRecovery = false
        case .initialSession, .signedIn, .tokenRefreshed, .userUpdated, .mfaChallengeVerified:
            currentUser = session?.user
        }
    }

    func signIn(email: String, password: String) async throws {
        try requireConfiguration()
        try await client.auth.signIn(email: email, password: password)
        currentUser = try await client.auth.session.user
    }

    func signUp(email: String, password: String) async throws {
        try requireConfiguration()
        try await client.auth.signUp(email: email, password: password)
        do {
            try await client.auth.signIn(email: email, password: password)
            currentUser = try await client.auth.session.user
        } catch {
            currentUser = try? await client.auth.session.user
            if currentUser == nil {
                throw AuthFlowError.emailConfirmationRequired
            }
        }
    }

    func signInWithApple(identityToken: String) async throws {
        try requireConfiguration()
        try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: identityToken,
                nonce: currentNonce
            )
        )
        currentUser = try await client.auth.session.user
    }

    func requestPasswordReset(email: String) async throws {
        try requireConfiguration()
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
            throw AuthFlowError.invalidEmail
        }
        try await client.auth.resetPasswordForEmail(
            normalizedEmail,
            redirectTo: Self.passwordRecoveryURL
        )
    }

    func updatePassword(_ password: String) async throws {
        try requireConfiguration()
        if let message = PasswordPolicy.validationMessage(for: password) {
            throw AuthFlowError.invalidPassword(message)
        }
        currentUser = try await client.auth.update(user: .init(password: password))
    }

    func completePasswordRecovery() {
        isPasswordRecovery = false
    }

    func cancelPasswordRecovery() async {
        try? await client.auth.signOut()
        currentUser = nil
        isPasswordRecovery = false
    }

    func handleAuthCallback(_ url: URL) {
        guard Self.isAuthCallback(url) else { return }
        client.handle(url)
    }

    nonisolated static func isAuthCallback(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "cleave"
            && url.host?.lowercased() == "auth-callback"
    }

    func signOut() async throws {
        try await client.auth.signOut()
        currentUser = nil
    }

    func completeAccountDeletion() async {
        try? await client.auth.signOut()
        currentUser = nil
    }

    func accessToken() async throws -> String {
        try requireConfiguration()
        return try await client.auth.session.accessToken
    }

    func generateNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        while result.count < length {
            var random: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &random) == errSecSuccess else {
                continue
            }
            if random < charset.count {
                result.append(charset[Int(random)])
            }
        }
        currentNonce = result
        return SHA256.hash(data: Data(result.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func requireConfiguration() throws {
        guard AppConfiguration.supabaseURL != nil else {
            throw AppConfiguration.ConfigurationError.missing("Supabase URL")
        }
        guard AppConfiguration.supabaseAnonKey != nil else {
            throw AppConfiguration.ConfigurationError.missing("Supabase anon key")
        }
    }
}

enum AuthFlowError: LocalizedError {
    case emailConfirmationRequired
    case invalidEmail
    case invalidPassword(String)

    var errorDescription: String? {
        switch self {
        case .emailConfirmationRequired:
            "Check your email to confirm your account, then sign in."
        case .invalidEmail:
            "Enter a valid email address."
        case .invalidPassword(let message):
            message
        }
    }
}

enum PasswordPolicy {
    static let minimumLength = 8

    static func validationMessage(for password: String) -> String? {
        guard password.count >= minimumLength else {
            return "Use at least \(minimumLength) characters for your password."
        }
        guard password.contains(where: { $0.isLetter }),
              password.contains(where: { $0.isNumber }) else {
            return "Use at least one letter and one number."
        }
        return nil
    }
}
