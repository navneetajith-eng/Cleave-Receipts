import UIKit

class HapticsManager {
    static let shared = HapticsManager()
    static let defaultsKey = "preferences.hapticsEnabled"

    private init() {
        if UserDefaults.standard.object(forKey: Self.defaultsKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.defaultsKey)
        }
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.defaultsKey) == nil
            || UserDefaults.standard.bool(forKey: Self.defaultsKey)
    }

    func playImpact(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    func playNotification(type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    func playSelection() {
        guard isEnabled else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}
