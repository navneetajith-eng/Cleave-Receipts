import Foundation
import SwiftUI

enum Currency: String, CaseIterable, Identifiable, Codable {
    case usd = "USD"
    case inr = "INR"
    case aed = "AED"

    var id: String { self.rawValue }

    var symbol: String {
        switch self {
        case .usd: return "$"
        case .inr: return "₹"
        case .aed: return "AED"
        }
    }

    var displayName: String {
        return "\(self.rawValue) (\(self.symbol))"
    }

    var iconName: String {
        switch self {
        case .usd: return "dollarsign.circle.fill"
        case .inr: return "indianrupeesign.circle.fill"
        case .aed: return "a.circle.fill"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .usd: return "en_US"
        case .inr: return "en_IN"
        case .aed: return "en_AE"
        }
    }
}

/// Currency-aware integer money used at financial boundaries. UI text fields may
/// still edit decimal values, but allocation and persistence must round once into
/// minor units instead of repeatedly operating on binary floating-point values.
struct Money: Codable, Equatable, Comparable {
    let minorUnits: Int64
    let currency: Currency

    init(minorUnits: Int64, currency: Currency) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    init(amount: Double, currency: Currency) {
        self.init(
            minorUnits: Int64((amount * 100).rounded(.toNearestOrAwayFromZero)),
            currency: currency
        )
    }

    var amount: Double { Double(minorUnits) / 100 }

    static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(lhs.currency == rhs.currency, "Cannot compare different currencies")
        return lhs.minorUnits < rhs.minorUnits
    }
}

enum MoneyAllocator {
    /// Largest-remainder proportional allocation. The returned minor units always
    /// sum exactly to `totalMinorUnits` for positive weights.
    static func allocate(
        totalMinorUnits: Int64,
        weights: [String: Int64]
    ) -> [String: Int64] {
        let positive = weights.filter { $0.value > 0 }
        let weightTotal = positive.values.reduce(0, +)
        guard totalMinorUnits > 0, weightTotal > 0 else {
            return Dictionary(uniqueKeysWithValues: weights.keys.map { ($0, 0) })
        }

        var result: [String: Int64] = [:]
        var remainders: [(key: String, remainder: Int64)] = []
        for (key, weight) in positive {
            let numerator = totalMinorUnits * weight
            result[key] = numerator / weightTotal
            remainders.append((key, numerator % weightTotal))
        }

        let allocated = result.values.reduce(0, +)
        let unitsLeft = Int(totalMinorUnits - allocated)
        for entry in remainders.sorted(by: {
            $0.remainder == $1.remainder ? $0.key < $1.key : $0.remainder > $1.remainder
        }).prefix(unitsLeft) {
            result[entry.key, default: 0] += 1
        }
        for key in weights.keys where result[key] == nil { result[key] = 0 }
        return result
    }
}

enum SettlementMethod: String {
    case venmo
    case googlePayUPI
    case aani

    var displayName: String {
        switch self {
        case .venmo: return "Venmo"
        case .googlePayUPI: return "Google Pay (UPI)"
        case .aani: return "Aani"
        }
    }

    var actionLabel: String {
        switch self {
        case .venmo: return "Settle with Venmo"
        case .googlePayUPI: return "Settle with Google Pay"
        case .aani: return "Settle with Aani"
        }
    }

    var iconName: String {
        switch self {
        case .venmo: return "v.square.fill"
        case .googlePayUPI: return "indianrupeesign.circle.fill"
        case .aani: return "bolt.horizontal.circle.fill"
        }
    }
}

enum AppRegion: String, CaseIterable, Identifiable {
    case unitedStates = "US"
    case india = "IN"
    case unitedArabEmirates = "AE"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unitedStates: return "United States"
        case .india: return "India"
        case .unitedArabEmirates: return "United Arab Emirates"
        }
    }

    var flag: String {
        switch self {
        case .unitedStates: return "🇺🇸"
        case .india: return "🇮🇳"
        case .unitedArabEmirates: return "🇦🇪"
        }
    }

    var currency: Currency {
        switch self {
        case .unitedStates: return .usd
        case .india: return .inr
        case .unitedArabEmirates: return .aed
        }
    }

    var settlementMethod: SettlementMethod {
        switch self {
        case .unitedStates: return .venmo
        case .india: return .googlePayUPI
        case .unitedArabEmirates: return .aani
        }
    }

    static func fromLegacyCurrency(_ rawValue: String?) -> AppRegion? {
        switch rawValue {
        case Currency.usd.rawValue: return .unitedStates
        case Currency.inr.rawValue: return .india
        case Currency.aed.rawValue: return .unitedArabEmirates
        default: return nil
        }
    }
}

final class RegionManager {
    static let shared = RegionManager()

    private let defaults = UserDefaults.standard

    var currentRegion: AppRegion {
        if let stored = defaults.string(forKey: "selectedRegion"),
           let region = AppRegion(rawValue: stored) {
            return region
        }

        if let legacyRegion = AppRegion.fromLegacyCurrency(defaults.string(forKey: "selectedCurrency")) {
            return legacyRegion
        }

        switch Locale.current.region?.identifier {
        case AppRegion.india.rawValue: return .india
        case AppRegion.unitedArabEmirates.rawValue: return .unitedArabEmirates
        default: return .unitedStates
        }
    }

    func select(_ region: AppRegion) {
        defaults.set(region.rawValue, forKey: "selectedRegion")
        defaults.removeObject(forKey: "selectedCurrency")
    }

    @discardableResult
    func migrateLegacyPreferenceIfNeeded() -> AppRegion {
        let region = currentRegion
        if defaults.string(forKey: "selectedRegion") == nil {
            select(region)
        }
        return region
    }
}

enum PaymentPreferences {
    static let venmoKey = "payment.venmoUsername"
    static let upiKey = "payment.upiID"
    static let syncPendingKey = "payment.syncPending"

    static var venmoUsername: String {
        UserDefaults.standard.string(forKey: venmoKey) ?? ""
    }

    static var upiID: String {
        UserDefaults.standard.string(forKey: upiKey) ?? ""
    }

    static var needsSync: Bool {
        UserDefaults.standard.bool(forKey: syncPendingKey)
    }

    static func normalizedVenmo(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasPrefix("@") { normalized.removeFirst() }
        return normalized
    }

    static func normalizedUPI(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isValidVenmo(_ value: String) -> Bool {
        normalizedVenmo(value).range(
            of: #"^[A-Za-z0-9_-]{2,64}$"#,
            options: .regularExpression
        ) != nil
    }

    static func isValidUPI(_ value: String) -> Bool {
        normalizedUPI(value).range(
            of: #"^[A-Za-z0-9._-]{2,191}@[A-Za-z][A-Za-z0-9.-]{1,62}$"#,
            options: .regularExpression
        ) != nil
    }

    static func isComplete(for region: AppRegion, venmo: String, upi: String) -> Bool {
        switch region {
        case .unitedStates: return isValidVenmo(venmo)
        case .india: return isValidUPI(upi)
        case .unitedArabEmirates: return true
        }
    }

    static func save(region: AppRegion, venmo: String, upi: String) {
        RegionManager.shared.select(region)
        UserDefaults.standard.set(
            region == .unitedStates ? normalizedVenmo(venmo) : "",
            forKey: venmoKey
        )
        UserDefaults.standard.set(
            region == .india ? normalizedUPI(upi) : "",
            forKey: upiKey
        )
        UserDefaults.standard.set(true, forKey: syncPendingKey)
    }

    static func markSynced() {
        UserDefaults.standard.set(false, forKey: syncPendingKey)
    }

    static func hydrate(region: AppRegion, venmo: String?, upi: String?) {
        RegionManager.shared.select(region)
        UserDefaults.standard.set(
            region == .unitedStates ? normalizedVenmo(venmo ?? "") : "",
            forKey: venmoKey
        )
        UserDefaults.standard.set(
            region == .india ? normalizedUPI(upi ?? "") : "",
            forKey: upiKey
        )
        markSynced()
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: venmoKey)
        UserDefaults.standard.removeObject(forKey: upiKey)
        UserDefaults.standard.removeObject(forKey: syncPendingKey)
        UserDefaults.standard.removeObject(forKey: "selectedRegion")
        UserDefaults.standard.removeObject(forKey: "selectedCurrency")
    }
}

class CurrencyManager {
    static let shared = CurrencyManager()

    // We get the value from UserDefaults directly here if needed outside a View
    var currentCurrency: Currency {
        RegionManager.shared.currentRegion.currency
    }

    private let cache = NSCache<NSString, NumberFormatter>()

    private func formatter(for currency: Currency) -> NumberFormatter {
        let key = currency.rawValue as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: currency.localeIdentifier)
        formatter.currencyCode = currency.rawValue
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
