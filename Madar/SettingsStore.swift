import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Keys {
        static let universe = "universe"
        static let minTarget = "minTarget"
        static let maxStop = "maxStop"
        static let btcFilter = "btcFilter"
        static let autoRefresh = "autoRefresh"
        static let notifications = "notifications"
    }

    @Published var universe: Int { didSet { defaults.set(universe, forKey: Keys.universe) } }
    @Published var minTarget: Double { didSet { defaults.set(minTarget, forKey: Keys.minTarget) } }
    @Published var maxStop: Double { didSet { defaults.set(maxStop, forKey: Keys.maxStop) } }
    @Published var btcFilter: Bool { didSet { defaults.set(btcFilter, forKey: Keys.btcFilter) } }
    @Published var autoRefresh: Bool { didSet { defaults.set(autoRefresh, forKey: Keys.autoRefresh) } }
    @Published var notifications: Bool { didSet { defaults.set(notifications, forKey: Keys.notifications) } }

    private let defaults = UserDefaults.standard

    private init() {
        universe = defaults.object(forKey: Keys.universe) == nil ? 50 : defaults.integer(forKey: Keys.universe)
        minTarget = defaults.object(forKey: Keys.minTarget) == nil ? 20 : defaults.double(forKey: Keys.minTarget)
        maxStop = defaults.object(forKey: Keys.maxStop) == nil ? 8 : defaults.double(forKey: Keys.maxStop)
        btcFilter = defaults.object(forKey: Keys.btcFilter) == nil ? true : defaults.bool(forKey: Keys.btcFilter)
        autoRefresh = defaults.bool(forKey: Keys.autoRefresh)
        notifications = defaults.object(forKey: Keys.notifications) == nil ? true : defaults.bool(forKey: Keys.notifications)
    }

    var config: ScanConfig {
        ScanConfig(limit: universe, minTarget: minTarget, maxStop: maxStop, btcFilter: btcFilter)
    }
}
