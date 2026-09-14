import Foundation
import UserNotifications

actor NotificationManager {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let seenKey = "madar-notified-signal-ids-v1"

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func notifyNewSignals(_ signals: [Signal]) async {
        var seen = Set(defaults.stringArray(forKey: seenKey) ?? [])
        var didChange = false
        for signal in signals where !signal.isExpired && !seen.contains(signal.id) {
            let content = UNMutableNotificationContent()
            content.title = "إشارة شراء جديدة · \(signal.base)/USDT"
            content.body = "دخول \(format(signal.entry, digits: signal.digits)) · وقف \(format(signal.stop, digits: signal.digits)) · الهدف الأول \(format(signal.targets[0], digits: signal.digits))"
            content.sound = .default
            content.userInfo = ["symbol": signal.symbol, "signalID": signal.id]
            let request = UNNotificationRequest(identifier: "madar-\(signal.id)", content: content, trigger: nil)
            try? await center.add(request)
            seen.insert(signal.id)
            didChange = true
        }
        if didChange {
            defaults.set(Array(seen.suffix(200)), forKey: seenKey)
        }
    }

    private func format(_ value: Double, digits: Int) -> String {
        String(format: "%.*f", digits, value)
    }
}
