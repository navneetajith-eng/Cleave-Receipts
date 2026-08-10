import Foundation

enum PaymentDeepLinkBuilder {

    /// Builds a Venmo deep link URL for requesting/paying.
    /// Format: venmo://paycharge?txn=pay&recipients=<handle>&amount=<amount>&note=<note>
    static func buildVenmoURL(handle: String, amount: Double, note: String = "Cleave Receipt Split") -> URL? {
        var components = URLComponents()
        components.scheme = "venmo"
        components.host = "paycharge"

        let sanitizedHandle = handle.replacingOccurrences(of: "@", with: "")
        let formattedAmount = String(format: "%.2f", amount)

        components.queryItems = [
            URLQueryItem(name: "txn", value: "pay"), // 'pay' or 'charge'
            URLQueryItem(name: "recipients", value: sanitizedHandle),
            URLQueryItem(name: "amount", value: formattedAmount),
            URLQueryItem(name: "note", value: note)
        ]

        // If Venmo is not installed, fallback to web
        if let url = components.url {
            return url
        }

        return URL(string: "https://venmo.com/\(sanitizedHandle)")
    }
}
