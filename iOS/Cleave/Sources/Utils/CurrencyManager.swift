import Foundation
import SwiftUI

enum Currency: String, CaseIterable, Identifiable {
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"
    case cad = "CAD"
    case aud = "AUD"
    case chf = "CHF"
    case cny = "CNY"
    case inr = "INR"
    case aed = "AED"

    var id: String { self.rawValue }

    var symbol: String {
        switch self {
        case .usd, .cad, .aud: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        case .jpy, .cny: return "¥"
        case .chf: return "Fr"
        case .inr: return "₹"
        case .aed: return "د.إ"
        }
    }

    var displayName: String {
        return "\(self.rawValue) (\(self.symbol))"
    }

    var iconName: String {
        switch self {
        case .usd, .cad, .aud: return "dollarsign.circle.fill"
        case .eur: return "eurosign.circle.fill"
        case .gbp: return "sterlingsign.circle.fill"
        case .jpy, .cny: return "yensign.circle.fill"
        case .chf: return "francsign.circle.fill"
        case .inr: return "indianrupeesign.circle.fill"
        case .aed: return "a.circle.fill"
        }
    }
}

class CurrencyManager {
    static let shared = CurrencyManager()

    // We get the value from UserDefaults directly here if needed outside a View
    var currentCurrency: Currency {
        let rawValue = UserDefaults.standard.string(forKey: "selectedCurrency") ?? Currency.usd.rawValue
        return Currency(rawValue: rawValue) ?? .usd
    }

    private let cache = NSCache<NSString, NumberFormatter>()

    private func formatter(for currency: Currency) -> NumberFormatter {
        let key = currency.rawValue as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = currency.symbol
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        cache.setObject(formatter, forKey: key)
        return formatter
    }

    func format(_ amount: Double) -> String {
        let fmt = formatter(for: currentCurrency)
        return fmt.string(from: NSNumber(value: amount)) ?? "\(currentCurrency.symbol)\(String(format: "%.2f", amount))"
    }

    static func format(_ amount: Double, currency: Currency) -> String {
        return shared.format(amount, currency: currency)
    }

    func format(_ amount: Double, currency: Currency) -> String {
        let fmt = formatter(for: currency)
        return fmt.string(from: NSNumber(value: amount)) ?? "\(currency.symbol)\(String(format: "%.2f", amount))"
    }
}
