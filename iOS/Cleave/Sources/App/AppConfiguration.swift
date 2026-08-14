import Foundation

enum AppConfiguration {
    enum ConfigurationError: LocalizedError {
        case missing(String)

        var errorDescription: String? {
            switch self {
            case .missing(let key):
                return "The app is missing its \(key) configuration."
            }
        }
    }

    static var apiBaseURL: URL? {
        url(for: "CleaveAPIBaseURL")
    }

    static var supabaseURL: URL? {
        url(for: "CleaveSupabaseURL")
    }

    static var supabaseAnonKey: String? {
        string(for: "CleaveSupabaseAnonKey")
    }

    static var websiteBaseURL: URL? {
        url(for: "CleaveWebsiteBaseURL")
    }

    static var privacyPolicyURL: URL? {
        websiteURL(path: "privacy")
    }

    static var supportURL: URL? {
        websiteURL(path: "support")
    }

    static var isSupabaseConfigured: Bool {
        supabaseURL != nil && supabaseAnonKey != nil
    }

    private static func string(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    private static func url(for key: String) -> URL? {
        guard let value = string(for: key) else { return nil }
        return URL(string: value)
    }

    private static func websiteURL(path: String) -> URL? {
        guard let baseURL = websiteBaseURL else { return nil }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }
}
