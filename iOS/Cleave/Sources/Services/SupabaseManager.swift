import AuthenticationServices
import CryptoKit
import Foundation
import Supabase

@MainActor
final class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()

    let client: SupabaseClient
    @Published private(set) var currentUser: User?
    @Published private(set) var hasCheckedSession = false

    var currentNonce: String?

    private init() {
        let url = AppConfiguration.supabaseURL ?? URL(string: "https://configuration.invalid")!
        let key = AppConfiguration.supabaseAnonKey ?? "CONFIGURATION_REQUIRED"
        client = SupabaseClient(supabaseURL: url, supabaseKey: key)
    }

    func checkSession() async {
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

    var errorDescription: String? {
        "Check your email to confirm your account, then sign in."
    }
}
