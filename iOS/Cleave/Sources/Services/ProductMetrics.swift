import Foundation
import OSLog

enum ProductMetric: String {
    case localGroupCreation = "group.create.local"
    case collaborativeGroupCreation = "group.create.collaborative"
    case receiptCaptureToReview = "receipt.capture_to_review"
}

struct ProductMetricSample: Codable, Equatable {
    let metric: String
    let milliseconds: Double
    let succeeded: Bool
    let recordedAt: Date
}

enum ProductMetrics {
    private static let logger = Logger(subsystem: "com.cleave.Cleave", category: "ProductMetrics")
    private static let storageKey = "cleave.product-metrics.v1"
    private static let maximumSamples = 200

    static func record(_ metric: ProductMetric, startedAt: Date, succeeded: Bool) {
        let milliseconds = max(0, Date().timeIntervalSince(startedAt) * 1_000)
        let sample = ProductMetricSample(
            metric: metric.rawValue,
            milliseconds: milliseconds,
            succeeded: succeeded,
            recordedAt: Date()
        )
        var values = samples()
        values.append(sample)
        if values.count > maximumSamples {
            values.removeFirst(values.count - maximumSamples)
        }
        if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        logger.info("\(metric.rawValue, privacy: .public) completed in \(milliseconds, privacy: .public)ms success=\(succeeded, privacy: .public)")
    }

    static func samples() -> [ProductMetricSample] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let values = try? JSONDecoder().decode([ProductMetricSample].self, from: data) else {
            return []
        }
        return values
    }

    static func percentile(_ percentile: Double, values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let clamped = min(max(percentile, 0), 1)
        let index = Int((Double(sorted.count - 1) * clamped).rounded(.up))
        return sorted[index]
    }
}
