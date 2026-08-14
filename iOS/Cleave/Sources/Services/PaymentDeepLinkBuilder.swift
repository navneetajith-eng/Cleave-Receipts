import Foundation

enum PaymentDeepLinkBuilder {
    static let venmoAppStoreURL = URL(string: "https://apps.apple.com/us/app/venmo/id351727428")!
    static let googlePayAppStoreURL = URL(string: "https://apps.apple.com/in/app/google-pay-save-pay-manage/id1193357041")!
    static let aaniAppStoreURL = URL(string: "https://apps.apple.com/ae/app/aani/id6444847879")!

    /// Opens Venmo's person-to-person composer. The user must choose and verify
    /// the recipient inside Venmo before authorizing the payment.
    static func buildVenmoURL(
        recipient: String? = nil,
        amount: Double,
        note: String = "Cleave Receipt Split"
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "venmo"
        components.host = "paycharge"

        let formattedAmount = String(format: "%.2f", amount)

        var queryItems = [
            URLQueryItem(name: "txn", value: "pay"),
            URLQueryItem(name: "amount", value: formattedAmount),
            URLQueryItem(name: "note", value: note)
        ]
        if let recipient, !recipient.isEmpty {
            queryItems.insert(URLQueryItem(name: "recipients", value: recipient), at: 1)
        }
        components.queryItems = queryItems

        return components.url
    }

    /// Opens Google Pay's standard UPI handoff. Google Pay remains responsible
    /// for displaying and verifying the final recipient before authorization.
    static func buildGooglePayURL(
        upiID: String,
        recipientName: String,
        amount: Double,
        note: String
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "gpay"
        components.host = "upi"
        components.path = "/pay"
        components.queryItems = [
            URLQueryItem(name: "pa", value: upiID),
            URLQueryItem(name: "pn", value: recipientName),
            URLQueryItem(name: "am", value: String(format: "%.2f", amount)),
            URLQueryItem(name: "cu", value: "INR"),
            URLQueryItem(name: "tn", value: note)
        ]
        return components.url
    }

    static func clipboardSummary(
        region: AppRegion,
        amount: Double,
        memberName: String,
        note: String,
        paymentAddress: String? = nil
    ) -> String {
        [
            "Pay \(memberName)",
            CurrencyManager.format(amount, currency: region.currency),
            note,
            paymentAddress.map { "Payment ID: \($0)" }
        ].compactMap { $0 }.joined(separator: " • ")
    }
}
